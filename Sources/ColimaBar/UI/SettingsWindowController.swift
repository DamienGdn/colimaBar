import AppKit
import Combine
import ColimaBarCore

/// Settings window: instance picker on top, then the shared `SettingsPanelViewController`.
/// Opened from the dashboard gear menu (and the status-bar popover) through `show(store:)`.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private weak var store: AppStore?
    private weak var content: SettingsContentViewController?
    private var stateSub: AnyCancellable?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.title = L.t("Réglages", "Settings")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func show(store: AppStore) {
        self.store = store
        if window?.isVisible != true {
            rebuildContent(store: store)
            window?.center()
        }
        // Keep the panel in sync with the instance / Colima state while the window is open.
        stateSub = store.$state
            .map { state -> Bool in if case .running = state.colima { return true } else { return false } }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.content?.resyncPanel() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// (Re)creates the content so it reflects the current Colima state, login item and language.
    private func rebuildContent(store: AppStore) {
        let content = SettingsContentViewController(store: store) { [weak self] in
            guard let self, let store = self.store else { return }
            // Language changed: rebuild with the new strings, and re-render the SwiftUI
            // views (dashboard, status popover) that read `L.t` in their body.
            self.window?.title = L.t("Réglages", "Settings")
            self.rebuildContent(store: store)
            store.objectWillChange.send()
        }
        self.content = content
        window?.contentViewController = content
        window?.title = L.t("Réglages", "Settings")
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stateSub?.cancel()
        stateSub = nil
    }
}

private final class SettingsContentViewController: NSViewController {
    private let store: AppStore
    private let onLanguageChange: () -> Void
    private let panel = SettingsPanelViewController()
    private let instancePicker = NSPopUpButton()

    init(store: AppStore, onLanguageChange: @escaping () -> Void) {
        self.store = store
        self.onLanguageChange = onLanguageChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let root = ThemedView(fill: Theme.Tokens.bg)
        root.frame = NSRect(x: 0, y: 0, width: 420, height: 620)
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let label = NSTextField(labelWithString: L.t("Instance", "Instance").uppercased())
        label.font = .systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = Theme.Tokens.text3
        label.translatesAutoresizingMaskIntoConstraints = false

        instancePicker.target = self
        instancePicker.action = #selector(instanceSelected)
        instancePicker.controlSize = .small
        instancePicker.translatesAutoresizingMaskIntoConstraints = false

        let line = Theme.separator()

        wirePanel()
        addChild(panel)
        panel.view.translatesAutoresizingMaskIntoConstraints = false

        for sub in [label, instancePicker, line, panel.view] as [NSView] { view.addSubview(sub) }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            instancePicker.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            instancePicker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            instancePicker.widthAnchor.constraint(equalToConstant: 200),

            line.topAnchor.constraint(equalTo: instancePicker.bottomAnchor, constant: 10),
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            panel.view.topAnchor.constraint(equalTo: line.bottomAnchor),
            panel.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        reloadInstances()
    }

    /// Same callbacks as the former dashboard settings wiring.
    private func wirePanel() {
        panel.showsInstanceField = false
        panel.isColimaRunning = { if case .running = store.state.colima { return true } else { return false } }()
        panel.isLoginItemEnabled = (NSApp.delegate as? AppDelegate)?.isLoginItemEnabled() ?? false
        panel.onApplyConfig = { [weak store] in store?.restartColima() }
        panel.onResizeDisk = { [weak store] in store?.restartColima() }
        panel.onToggleLoginItem = { [weak self] in
            guard let self else { return }
            (NSApp.delegate as? AppDelegate)?.toggleLoginItem()
            if let enabled = (NSApp.delegate as? AppDelegate)?.isLoginItemEnabled() {
                self.panel.isLoginItemEnabled = enabled
            }
        }
        panel.onSetLanguage = { [weak self] _ in
            // Deferred: the control that triggered this is about to be torn down.
            DispatchQueue.main.async { self?.onLanguageChange() }
        }
    }

    private func reloadInstances() {
        let current = ColimaConfig.activeInstanceName
        instancePicker.removeAllItems()
        instancePicker.addItem(withTitle: current)
        store.manager.listInstances { [weak self] names in
            guard let self else { return }
            let list = names.contains(current) ? names : [current] + names
            self.instancePicker.removeAllItems()
            self.instancePicker.addItems(withTitles: list)
            self.instancePicker.selectItem(withTitle: ColimaConfig.activeInstanceName)
        }
    }

    @objc private func instanceSelected() {
        guard let name = instancePicker.titleOfSelectedItem else { return }
        store.switchInstance(to: name)
        resyncPanel()
    }

    func resyncPanel() {
        if case .running = store.state.colima { panel.isColimaRunning = true } else { panel.isColimaRunning = false }
        panel.syncControls()
    }
}
