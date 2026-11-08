import AppKit
import Combine
import SwiftUI
import ColimaBarCore

/// Status-bar item: llama icon + state badge, and a branded SwiftUI popover (`StatusPopoverView`).
/// Also watches the polled state for container crashes and sustained high CPU / RAM.
final class StatusBarController: NSObject {
    private let store: AppStore
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var lastState: ColimaAppState = .unknown
    /// Set when the transient popover was closed by a mouse-down on the status icon: the action
    /// of that same click (fired on mouse-up) must not reopen it. Consumed by the next toggle,
    /// or cleared right after the click's mouse-up if no toggle follows (e.g. drag off the icon).
    private var closedByIconClick = false
    private var clickMonitor: Any?
    private var breathTimer: Timer?
    private var breathStart = Date()
    private var currentBadgeColor: NSColor?
    private lazy var baseGlyph: NSImage = NSImage(named: "colimabar")
        ?? NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Colima Desktop")!
    private var consecutiveHighCPU = 0
    private var consecutiveHighRAM = 0

    init(store: AppStore) {
        self.store = store
        super.init()
        setupStatusItem()
        setupPopover()
        store.$state
            .dropFirst()
            .sink { [weak self] state in self?.update(state: state) }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        updateIcon(colima: .unknown)
    }

    private func setupPopover() {
        let root = StatusPopoverView(close: { [weak self] in self?.popover.performClose(nil) })
            .environmentObject(store)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private func clearIconClickFlag() {
        closedByIconClick = false
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
    }

    @objc private func togglePopover() {
        // A fresh mouse-down on the icon that did not close a popover invalidates a stranded flag.
        if closedByIconClick, NSApp.currentEvent?.type != .leftMouseUp, NSApp.currentEvent?.type != .rightMouseUp {
            clearIconClickFlag()
        }
        if popover.isShown {
            clearIconClickFlag()
            popover.performClose(nil)
            return
        }
        // The transient popover closes on mouse-down outside it, before this action runs.
        if closedByIconClick {
            clearIconClickFlag()
            return
        }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - State updates

    private func update(state: ColimaAppState) {
        if case .running = state.colima, case .running = lastState.colima {
            detectContainerCrashes(prev: lastState.containers, new: state.containers)
        }
        lastState = state
        updateIcon(colima: state.colima)
        checkResourceAlerts(state.usage)
    }

    /// Fires a notification after 2 consecutive cycles above threshold.
    private func checkResourceAlerts(_ usage: ResourceUsage?) {
        guard let u = usage else { return }
        if u.cpuPercent > 80 {
            consecutiveHighCPU += 1
            if consecutiveHighCPU == 2 {
                let value = String(format: "%.0f%%", u.cpuPercent)
                (NSApp.delegate as? AppDelegate)?.showError(L.t("CPU élevé : \(value)", "High CPU: \(value)"))
                consecutiveHighCPU = 0
            }
        } else { consecutiveHighCPU = 0 }

        if u.memUsedPercent > 90 {
            consecutiveHighRAM += 1
            if consecutiveHighRAM == 2 {
                let value = String(format: "%.0f%%", u.memUsedPercent)
                (NSApp.delegate as? AppDelegate)?.showError(L.t("RAM élevée : \(value)", "High RAM: \(value)"))
                consecutiveHighRAM = 0
            }
        } else { consecutiveHighRAM = 0 }
    }

    private func updateIcon(colima: ColimaRunningState) {
        guard let button = statusItem.button else { return }
        let badgeColor: NSColor?
        switch colima {
        case .running:           badgeColor = Theme.Status.running
        case .transitioning:     badgeColor = Theme.Status.transitioning
        case .stopped, .unknown: badgeColor = nil   // dimmed glyph, no badge
        }
        currentBadgeColor = badgeColor
        if case .transitioning = colima, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            startBreathing()
        } else {
            stopBreathing()
            button.image = colimaIcon(badgeColor: badgeColor)
        }
        button.toolTip = "ColimaBar"

        if ColimaConfig.compactModeEnabled, case .running = colima {
            let running = lastState.containers.filter { $0.isRunning }.count
            button.title         = " ▶\(running)"
            button.imagePosition = .imageLeft
        } else {
            button.title         = ""
            button.imagePosition = .imageOnly
        }
    }

    // MARK: - Breathing icon

    /// Starts the ~15 fps redraw timer (no-op if already running); only used while transitioning.
    private func startBreathing() {
        guard breathTimer == nil else { return }
        breathStart = Date()
        redrawBreathingIcon()
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.redrawBreathingIcon()
        }
        RunLoop.main.add(timer, forMode: .common)
        breathTimer = timer
    }

    private func stopBreathing() {
        breathTimer?.invalidate()
        breathTimer = nil
    }

    private func redrawBreathingIcon() {
        let alpha = BreathingCurve.alpha(at: Date().timeIntervalSince(breathStart))
        statusItem.button?.image = colimaIcon(badgeColor: currentBadgeColor, glyphAlpha: alpha)
    }

    deinit {
        breathTimer?.invalidate()
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
    }

    /// Menu bar icon: the llama glyph tinted with the menu bar label color,
    /// dimmed when Colima is stopped, with a colored status badge otherwise.
    /// `glyphAlpha` (breathing) scales the glyph only; the badge stays fully opaque.
    private func colimaIcon(badgeColor: NSColor?, glyphAlpha: Double = 1.0) -> NSImage {
        let base = baseGlyph
        let size = NSSize(width: 22, height: 22)
        let result = NSImage(size: size, flipped: false) { rect in
            // Glyph in labelColor (adapts to dark/light menu bar)
            base.draw(in: rect, from: .zero, operation: .sourceOver,
                      fraction: badgeColor == nil ? 0.55 : CGFloat(glyphAlpha))
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)

            guard let badgeColor else { return true }

            // Status badge — bottom-right corner
            let d: CGFloat = 7
            let badge = NSRect(x: rect.width - d - 0.5, y: 0.5, width: d, height: d)

            // Knock out a transparent ring so the badge reads on any background
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: badge.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            badgeColor.setFill()
            NSBezierPath(ovalIn: badge).fill()
            return true
        }
        result.isTemplate = false
        result.accessibilityDescription = "ColimaBar"
        return result
    }

    private func detectContainerCrashes(prev: [DockerContainer], new: [DockerContainer]) {
        guard !prev.isEmpty else { return }
        let prevMap = Dictionary(uniqueKeysWithValues: prev.map { ($0.name, $0.state) })
        let appDelegate = NSApp.delegate as? AppDelegate
        for c in new {
            if let ps = prevMap[c.name], ps == .running,
               c.state == .exited || c.state == .dead {
                appDelegate?.showError(L.t(
                    "Container '\(c.name)' s'est arrêté inopinément",
                    "Container '\(c.name)' exited unexpectedly"))
            }
        }
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        clearIconClickFlag()
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDown || event.type == .rightMouseDown,
              let button = statusItem.button, event.window === button.window,
              button.bounds.contains(button.convert(event.locationInWindow, from: nil)) else { return }
        closedByIconClick = true
        // The click's action fires during this mouse-up's dispatch; clear the flag right after.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            DispatchQueue.main.async { self?.clearIconClickFlag() }
            return event
        }
    }
}
