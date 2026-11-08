import AppKit
import Combine
import ColimaBarCore

final class StatusBarController {
    private let manager: ColimaManager
    private let store: AppStore
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var lastState: ColimaAppState = .unknown

    // Status display items
    private var colimaStatusItem: NSMenuItem!
    private var resourcesItem: NSMenuItem!
    private var usageItem: NSMenuItem!
    private var lastErrorItem: NSMenuItem!

    // Action items
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var openPortainerItem: NSMenuItem!
    private var portainerWarningItem: NSMenuItem!
    private var installPortainerItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var quitItem: NSMenuItem!

    private var isColimaRunning = false
    private var containersItem: NSMenuItem!
    private var pruneItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var popover: NSPopover!
    private var containersPanelVC: ContainersPanelViewController!
    private var settingsPopover: NSPopover!
    private var settingsPanelVC: SettingsPanelViewController!
    private var previousContainerStates: [String: DockerContainer.ContainerState] = [:]
    private let logsWindowController = LogsWindowController()
    private var consecutiveHighCPU:   Int      = 0
    private var consecutiveHighRAM:   Int      = 0
    private var lastKnownInstances:   [String] = ["default"]
    private var instanceSubmenuItem:  NSMenuItem?

    init(store: AppStore) {
        self.store = store
        self.manager = store.manager
        setupStatusItem()
        store.$state
            .dropFirst()
            .sink { [weak self] state in self?.update(state: state) }
            .store(in: &cancellables)
        store.$lastError
            .sink { [weak self] message in
                if let message { self?.showLastError(message) } else { self?.clearLastError() }
            }
            .store(in: &cancellables)
        store.$updateVersion
            .compactMap { $0 }
            .sink { [weak self] version in self?.showUpdateAvailable(version: version) }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        statusItem.menu = menu
        updateIcon(colima: .unknown)
        setupContainersPopover()
        setupSettingsPopover()
    }

    private func setupContainersPopover() {
        containersPanelVC = ContainersPanelViewController()
        popover = NSPopover()
        popover.contentViewController = containersPanelVC
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 900, height: 560)

        containersPanelVC.onStart = { [weak self] name in
            self?.manager.startContainer(name) { [weak self] result in
                if case .failure(let e) = result { self?.showLastError(e.localizedDescription) }
            }
        }
        containersPanelVC.onStop = { [weak self] name in
            self?.manager.stopContainer(name) { [weak self] result in
                if case .failure(let e) = result { self?.showLastError(e.localizedDescription) }
            }
        }
        containersPanelVC.onRestart = { [weak self] name in
            self?.manager.stopContainer(name) { [weak self] result in
                guard let self else { return }
                if case .failure(let e) = result { self.showLastError(e.localizedDescription); return }
                self.manager.startContainer(name) { [weak self] result in
                    if case .failure(let e) = result { self?.showLastError(e.localizedDescription) }
                }
            }
        }
        containersPanelVC.onLogs = { [weak self] name in
            self?.openLogsTerminal(containerName: name)
        }
        containersPanelVC.onShell = { name, command in
            TerminalLauncher.openShell(container: name, command: command)
        }
        containersPanelVC.onFetchImages = { [weak self] completion in
            self?.manager.fetchImages(completion: completion)
        }
        containersPanelVC.onDeleteImage = { [weak self] id, completion in
            self?.manager.deleteImage(id, completion: completion)
        }
        containersPanelVC.onPullImage = { [weak self] name, completion in
            self?.manager.pullImage(name, completion: completion)
        }
        containersPanelVC.onFetchVolumes = { [weak self] completion in
            self?.manager.fetchVolumes(completion: completion)
        }
        containersPanelVC.onPruneVolumes = { [weak self] completion in
            self?.manager.pruneVolumes(completion: completion)
        }
        containersPanelVC.onFetchNetworks = { [weak self] completion in
            self?.manager.fetchNetworks(completion: completion)
        }
        containersPanelVC.onPruneNetworks = { [weak self] completion in
            self?.manager.pruneNetworks(completion: completion)
        }
        containersPanelVC.onSetRestartPolicy = { [weak self] policy, name, completion in
            self?.manager.setRestartPolicy(policy, container: name, completion: completion)
        }
        containersPanelVC.onInspect = { name in
            TerminalLauncher.run("docker inspect \(name)")
        }
        containersPanelVC.onFetchEnvVars = { [weak self] name, completion in
            self?.manager.fetchEnvVars(container: name, completion: completion)
        }
    }

    private func setupSettingsPopover() {
        settingsPanelVC = SettingsPanelViewController()
        settingsPanelVC.isColimaRunning    = isColimaRunning
        settingsPanelVC.isLoginItemEnabled = (NSApp.delegate as? AppDelegate)?.isLoginItemEnabled() ?? false
        settingsPopover = NSPopover()
        settingsPopover.contentViewController = settingsPanelVC
        settingsPopover.behavior = .transient
        settingsPopover.animates = true
        settingsPopover.contentSize = NSSize(width: 420, height: 520)

        settingsPanelVC.onApplyConfig = { [weak self] in self?.restartWithNewConfig() }
        settingsPanelVC.onResizeDisk = { [weak self] in
            self?.restartWithNewConfig()
        }
        settingsPanelVC.onToggleLoginItem = { [weak self] in
            (NSApp.delegate as? AppDelegate)?.toggleLoginItem()
            if let enabled = (NSApp.delegate as? AppDelegate)?.isLoginItemEnabled() {
                self?.settingsPanelVC.isLoginItemEnabled = enabled
            }
        }
        settingsPanelVC.onSetLanguage = { [weak self] _ in
            guard let self else { return }
            let state = self.lastState
            self.buildMenu()
            self.statusItem.menu = self.menu
            self.update(state: state)
            self.setupSettingsPopover()   // rebuild with new language
        }
    }

    private func buildMenu() {
        menu = NSMenu()

        // Status lines
        colimaStatusItem = NSMenuItem(title: "Colima : …", action: nil, keyEquivalent: "")
        colimaStatusItem.isEnabled = false
        menu.addItem(colimaStatusItem)

        resourcesItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        resourcesItem.isEnabled = false
        resourcesItem.isHidden = true
        resourcesItem.withSymbol("cpu")
        menu.addItem(resourcesItem)

        usageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        usageItem.isEnabled = false
        usageItem.isHidden = true
        usageItem.withSymbol("chart.bar")
        menu.addItem(usageItem)

        lastErrorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lastErrorItem.isEnabled = false
        lastErrorItem.isHidden = true
        lastErrorItem.withSymbol("exclamationmark.triangle")
        menu.addItem(lastErrorItem)

        menu.addItem(NSMenuItem.separator())

        // Colima actions
        startItem = NSMenuItem(
            title: L.t("Démarrer Colima", "Start Colima"),
            action: #selector(startColima), keyEquivalent: "")
        startItem.target = self
        startItem.withSymbol("play.fill")
        menu.addItem(startItem)

        stopItem = NSMenuItem(
            title: L.t("Arrêter Colima", "Stop Colima"),
            action: #selector(stopColima), keyEquivalent: "")
        stopItem.target = self
        stopItem.withSymbol("stop.fill")
        menu.addItem(stopItem)

        let dashboardItem = NSMenuItem(
            title: L.t("Ouvrir le Dashboard", "Open Dashboard"),
            action: #selector(openDashboard),
            keyEquivalent: "d")
        dashboardItem.target = self
        dashboardItem.withSymbol("rectangle.grid.2x2")
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem.separator())

        // Portainer
        portainerWarningItem = NSMenuItem(
            title: L.t("Portainer non installé", "Portainer not installed"),
            action: nil, keyEquivalent: "")
        portainerWarningItem.withSymbol("exclamationmark.triangle")
        portainerWarningItem.isEnabled = false
        portainerWarningItem.isHidden = true
        menu.addItem(portainerWarningItem)

        installPortainerItem = NSMenuItem(
            title: L.t("Installer Portainer…", "Install Portainer…"),
            action: #selector(installPortainer), keyEquivalent: "")
        installPortainerItem.target = self
        installPortainerItem.withSymbol("arrow.down.circle")
        installPortainerItem.isHidden = true
        menu.addItem(installPortainerItem)

        openPortainerItem = NSMenuItem(
            title: L.t("Ouvrir Portainer", "Open Portainer"),
            action: #selector(openPortainer), keyEquivalent: "")
        openPortainerItem.target = self
        openPortainerItem.withSymbol("safari")
        openPortainerItem.isHidden = true
        menu.addItem(openPortainerItem)

        menu.addItem(NSMenuItem.separator())

        containersItem = NSMenuItem(
            title: L.t("Containers", "Containers"),
            action: #selector(openContainersPanel),
            keyEquivalent: "")
        containersItem.target = self
        containersItem.withSymbol("shippingbox")
        containersItem.isHidden = true
        menu.addItem(containersItem)

        pruneItem = NSMenuItem(
            title: L.t("Vider Docker…", "Prune Docker…"),
            action: #selector(pruneDocker),
            keyEquivalent: "")
        pruneItem.target = self
        pruneItem.withSymbol("trash")
        pruneItem.isHidden = true
        menu.addItem(pruneItem)

        updateItem = NSMenuItem(title: "", action: #selector(upgradeColima), keyEquivalent: "")
        updateItem.target = self
        updateItem.withSymbol("arrow.triangle.2.circlepath")
        updateItem.isHidden = true
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let instanceItem = NSMenuItem(title: L.t("Instance", "Instance"), action: nil, keyEquivalent: "")
        instanceItem.submenu = NSMenu()
        instanceItem.withSymbol("square.stack.3d.up")
        instanceSubmenuItem  = instanceItem
        menu.addItem(instanceItem)

        let settingsItem = NSMenuItem(
            title: L.t("Paramètres…", "Settings…"),
            action: #selector(openSettingsPanel),
            keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.withSymbol("gearshape")
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: L.t("À propos de ColimaBar", "About ColimaBar"),
            action: #selector(showAbout),
            keyEquivalent: "")
        aboutItem.target = self
        aboutItem.withSymbol("info.circle")
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        quitItem = NSMenuItem(
            title: L.t("Quitter", "Quit"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.withSymbol("power")
        menu.addItem(quitItem)
    }

    // MARK: - State updates

    func update(state: ColimaAppState) {
        if case .running = state.colima, case .running = lastState.colima {
            detectContainerCrashes(prev: lastState.containers, new: state.containers)
        }
        lastState = state
        updateIcon(colima: state.colima)
        updateMenuItems(state: state)
        settingsPanelVC?.isColimaRunning = isColimaRunning

        // Resource alerts — fire notification after 2 consecutive cycles above threshold
        if let u = state.usage {
            if u.cpuPercent > 80 {
                consecutiveHighCPU += 1
                if consecutiveHighCPU == 2 {
                    let msg = L.t("CPU élevé : \(String(format: "%.0f%%", u.cpuPercent))",
                                  "High CPU: \(String(format: "%.0f%%", u.cpuPercent))")
                    (NSApp.delegate as? AppDelegate)?.showError(msg)
                    consecutiveHighCPU = 0
                }
            } else { consecutiveHighCPU = 0 }

            if u.memUsedPercent > 90 {
                consecutiveHighRAM += 1
                if consecutiveHighRAM == 2 {
                    let msg = L.t("RAM élevée : \(String(format: "%.0f%%", u.memUsedPercent))",
                                  "High RAM: \(String(format: "%.0f%%", u.memUsedPercent))")
                    (NSApp.delegate as? AppDelegate)?.showError(msg)
                    consecutiveHighRAM = 0
                }
            } else { consecutiveHighRAM = 0 }
        }

        // Refresh instance list cache when running
        if case .running = state.colima {
            manager.listInstances { [weak self] names in
                self?.lastKnownInstances = names
                self?.rebuildInstanceSubmenu()
            }
        }
    }

    private func updateIcon(colima: ColimaRunningState) {
        guard let button = statusItem.button else { return }
        let badgeColor: NSColor?
        switch colima {
        case .running:           badgeColor = Theme.Status.running
        case .transitioning:     badgeColor = Theme.Status.transitioning
        case .stopped, .unknown: badgeColor = nil   // dimmed glyph, no badge
        }
        button.image = colimaIcon(badgeColor: badgeColor)
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

    /// Menu bar icon: the llama glyph tinted with the menu bar label color,
    /// dimmed when Colima is stopped, with a colored status badge otherwise.
    private func colimaIcon(badgeColor: NSColor?) -> NSImage {
        let base = NSImage(named: "colimabar")
            ?? NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Colima Desktop")!
        let size = NSSize(width: 22, height: 22)
        let result = NSImage(size: size, flipped: false) { rect in
            // Glyph in labelColor (adapts to dark/light menu bar)
            base.draw(in: rect, from: .zero, operation: .sourceOver,
                      fraction: badgeColor == nil ? 0.55 : 1.0)
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

    func updateMenuItems(state: ColimaAppState) {
        let running: Bool
        switch state.colima {
        case .running:  running = true
        default:        running = false
        }

        let transitioning: Bool
        if case .transitioning(let msg) = state.colima {
            colimaStatusItem.title = "Colima : \(msg)"
            colimaStatusItem.image = Theme.statusDot(Theme.Status.transitioning)
            transitioning = true
        } else {
            colimaStatusItem.title = running
                ? L.t("Colima : En cours d'exécution", "Colima: Running")
                : L.t("Colima : Arrêté", "Colima: Stopped")
            colimaStatusItem.image = Theme.statusDot(running ? Theme.Status.running : .tertiaryLabelColor)
            transitioning = false
        }

        if let cpus = state.cpus, let mem = state.memoryGB {
            let label = L.t("Mémoire allouée", "Allocated memory")
            resourcesItem.title = String(format: "CPUs: %d  ·  \(label): %.0f GB", cpus, mem)
            resourcesItem.isHidden = false
        } else {
            resourcesItem.isHidden = true
        }

        if let u = state.usage {
            usageItem.title = String(format: "CPU: %.1f%%  ·  RAM: %@ / %.1f GB (%.0f%%)",
                                     u.cpuPercent, u.memUsedFormatted, u.memTotalGiB, u.memUsedPercent)
            usageItem.isHidden = false
        } else {
            usageItem.isHidden = true
        }

        startItem.isEnabled = !running && !transitioning
        stopItem.isEnabled = running && !transitioning

        openPortainerItem.isHidden = !running || !state.portainerExists
        portainerWarningItem.isHidden = !running || state.portainerExists
        installPortainerItem.isHidden = !running || state.portainerExists

        isColimaRunning = running
        pruneItem.isHidden = !running

        updateContainersItem(state.containers)
    }

    private func updateContainersItem(_ containers: [DockerContainer]) {
        guard !containers.isEmpty else {
            containersItem.isHidden = true
            return
        }
        let running = containers.filter { $0.isRunning }.count
        containersItem.title = "\(running)/\(containers.count) \(L.t("containers", "containers"))…"
        containersItem.isHidden = false
        if popover?.isShown == true {
            containersPanelVC.update(containers: containers, usage: lastState.usage,
                                     containerStats: lastState.containerStats,
                                     restartPolicies: lastState.restartPolicies)
        }
    }

    private func rebuildInstanceSubmenu() {
        guard let submenu = instanceSubmenuItem?.submenu else { return }
        submenu.removeAllItems()
        let current = ColimaConfig.activeInstanceName
        for name in lastKnownInstances {
            let item = NSMenuItem(title: name, action: #selector(switchInstance(_:)), keyEquivalent: "")
            item.target = self
            item.state  = name == current ? .on : .off
            submenu.addItem(item)
        }
    }

    @objc private func switchInstance(_ sender: NSMenuItem) {
        store.switchInstance(to: sender.title)
    }

    func showLastError(_ message: String) {
        lastErrorItem.title = String(message.prefix(80))
        lastErrorItem.isHidden = false
    }

    func clearLastError() {
        lastErrorItem.isHidden = true
    }

    // MARK: - Actions

    @objc private func openDashboard() {
        (NSApp.delegate as? AppDelegate)?.dashboardWindowController.showDashboard()
    }

    @objc private func startColima() { store.startColima() }

    @objc private func stopColima() { store.stopColima() }

    @objc private func showAbout() { (NSApp.delegate as? AppDelegate)?.showAbout() }

    @objc private func openPortainer() { store.openPortainer() }

    @objc private func installPortainer() {
        installPortainerItem.isEnabled = false
        store.installPortainer { [weak self] in self?.installPortainerItem.isEnabled = true }
    }

    @objc private func openSettingsPanel() {
        guard let button = statusItem.button else { return }
        settingsPanelVC.isColimaRunning    = isColimaRunning
        settingsPanelVC.isLoginItemEnabled = (NSApp.delegate as? AppDelegate)?.isLoginItemEnabled() ?? false
        settingsPanelVC.syncControls()
        if settingsPopover.isShown {
            settingsPopover.close()
        } else {
            settingsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func pruneDocker() {
        let alert = NSAlert()
        alert.messageText     = L.t("Vider Docker", "Prune Docker")
        alert.informativeText = L.t(
            "Supprime les images, containers arrêtés et volumes non utilisés. Irréversible.",
            "Removes stopped containers, unused images and volumes. Cannot be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.t("Vider", "Prune"))
        alert.addButton(withTitle: L.t("Annuler", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        pruneItem.isEnabled = false
        store.pruneDocker { [weak self] in self?.pruneItem.isEnabled = true }
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

    private func restartWithNewConfig() { store.restartColima() }

    @objc private func openContainersPanel() {
        guard let button = statusItem.button else { return }
        containersPanelVC.update(containers: lastState.containers, usage: lastState.usage,
                                 containerStats: lastState.containerStats,
                                 restartPolicies: lastState.restartPolicies)
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func openLogsTerminal(containerName name: String) {
        logsWindowController.show(containerName: name, dockerPath: "/opt/homebrew/bin/docker")
    }

    func showUpdateAvailable(version: String) {
        updateItem.title = L.t(
            "Mise à jour Colima \(version) disponible",
            "Colima \(version) update available")
        updateItem.isHidden = false
    }

    @objc private func upgradeColima() { store.upgradeColima() }
}
