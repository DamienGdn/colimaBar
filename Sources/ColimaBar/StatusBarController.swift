import AppKit
import ColimaBarCore

final class StatusBarController {
    private let manager: ColimaManager
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

    init(manager: ColimaManager) {
        self.manager = manager
        setupStatusItem()
        manager.onStateChange = { [weak self] state in
            self?.update(state: state)
        }
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
        popover.contentSize = NSSize(width: 600, height: 500)

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
        containersPanelVC.onShell = { [weak self] name in
            self?.openShellTerminal(containerName: name)
        }
        containersPanelVC.onFetchStats = { [weak self] name, completion in
            self?.manager.fetchContainerStats(name: name, completion: completion)
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
        settingsPopover.contentSize = NSSize(width: 420, height: 420)

        settingsPanelVC.onApplyConfig = { [weak self] in self?.restartWithNewConfig() }
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
        menu.addItem(resourcesItem)

        usageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        usageItem.isEnabled = false
        usageItem.isHidden = true
        menu.addItem(usageItem)

        lastErrorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lastErrorItem.isEnabled = false
        lastErrorItem.isHidden = true
        menu.addItem(lastErrorItem)

        menu.addItem(NSMenuItem.separator())

        // Colima actions
        startItem = NSMenuItem(
            title: L.t("▶ Démarrer Colima", "▶ Start Colima"),
            action: #selector(startColima), keyEquivalent: "")
        startItem.target = self
        menu.addItem(startItem)

        stopItem = NSMenuItem(
            title: L.t("■ Arrêter Colima", "■ Stop Colima"),
            action: #selector(stopColima), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        // Portainer
        portainerWarningItem = NSMenuItem(
            title: L.t("⚠ Portainer non installé", "⚠ Portainer not installed"),
            action: nil, keyEquivalent: "")
        portainerWarningItem.isEnabled = false
        portainerWarningItem.isHidden = true
        menu.addItem(portainerWarningItem)

        installPortainerItem = NSMenuItem(
            title: L.t("Installer Portainer…", "Install Portainer…"),
            action: #selector(installPortainer), keyEquivalent: "")
        installPortainerItem.target = self
        installPortainerItem.isHidden = true
        menu.addItem(installPortainerItem)

        openPortainerItem = NSMenuItem(
            title: L.t("Ouvrir Portainer", "Open Portainer"),
            action: #selector(openPortainer), keyEquivalent: "")
        openPortainerItem.target = self
        openPortainerItem.isHidden = true
        menu.addItem(openPortainerItem)

        menu.addItem(NSMenuItem.separator())

        containersItem = NSMenuItem(
            title: L.t("Containers", "Containers"),
            action: #selector(openContainersPanel),
            keyEquivalent: "")
        containersItem.target = self
        containersItem.isHidden = true
        menu.addItem(containersItem)

        pruneItem = NSMenuItem(
            title: L.t("🗑 Vider Docker…", "🗑 Prune Docker…"),
            action: #selector(pruneDocker),
            keyEquivalent: "")
        pruneItem.target = self
        pruneItem.isHidden = true
        menu.addItem(pruneItem)

        updateItem = NSMenuItem(title: "", action: #selector(upgradeColima), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "⚙ \(L.t("Paramètres", "Settings")) →",
            action: #selector(openSettingsPanel),
            keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        quitItem = NSMenuItem(
            title: L.t("Quitter", "Quit"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
    }

    private func updateIcon(colima: ColimaRunningState) {
        guard let button = statusItem.button else { return }
        let bubbleColor: NSColor
        switch colima {
        case .running:             bubbleColor = .systemGreen
        case .stopped, .unknown:   bubbleColor = .white
        case .transitioning:       bubbleColor = .systemOrange
        }
        button.image = colimaIcon(bubbleColor: bubbleColor)
    }

    private func colimaIcon(bubbleColor: NSColor) -> NSImage {
        let base = NSImage(named: "colimabar")
            ?? NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "ColimaBar")!
        let size = NSSize(width: 22, height: 22)
        let result = NSImage(size: size, flipped: false) { rect in
            // Llama in neutral labelColor (adapts dark/light menu bar)
            let llamaRect = rect
            base.draw(in: llamaRect)
            NSColor.labelColor.set()
            llamaRect.fill(using: .sourceAtop)

            // Status bubble — bottom-right corner
            let d: CGFloat = 7
            let bubble = NSRect(x: rect.width - d - 1, y: 1, width: d, height: d)

            // White border for contrast on any background
            NSColor.white.set()
            NSBezierPath(ovalIn: bubble.insetBy(dx: -1.5, dy: -1.5)).fill()

            // Colored fill
            bubbleColor.set()
            NSBezierPath(ovalIn: bubble).fill()

            return true
        }
        result.isTemplate = false
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
            transitioning = true
        } else {
            colimaStatusItem.title = running
                ? "● \(L.t("Colima : En cours d'exécution", "Colima: Running"))"
                : "○ \(L.t("Colima : Arrêté", "Colima: Stopped"))"
            transitioning = false
        }

        if let cpus = state.cpus, let mem = state.memoryGB {
            let label = L.t("Mémoire allouée", "Allocated memory")
            resourcesItem.title = String(format: "   CPUs: %d  |  \(label): %.0f GB", cpus, mem)
            resourcesItem.isHidden = false
        } else {
            resourcesItem.isHidden = true
        }

        if let u = state.usage {
            usageItem.title = String(format: "   CPU: %.1f%%  |  RAM: %@ / %.1f GB",
                                     u.cpuPercent, u.memUsedFormatted, u.memTotalGiB)
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
        containersItem.title = "\(running)/\(containers.count) \(L.t("containers", "containers")) →"
        containersItem.isHidden = false
        if popover?.isShown == true {
            containersPanelVC.update(containers: containers, usage: lastState.usage)
        }
    }

    func showLastError(_ message: String) {
        lastErrorItem.title = "⚠ \(message.prefix(80))"
        lastErrorItem.isHidden = false
    }

    func clearLastError() {
        lastErrorItem.isHidden = true
    }

    // MARK: - Actions

    @objc private func startColima() {
        (NSApp.delegate as? AppDelegate)?.showSuccess(L.t("Démarrage de Colima…", "Starting Colima…"))
        manager.startColima(onTransition: { [weak self] state in
            self?.update(state: state)
        }, completion: { [weak self] result in
            guard let self else { return }
            let appDelegate = NSApp.delegate as? AppDelegate
            switch result {
            case .success(let state):
                self.update(state: state)
                self.clearLastError()
                let duration = Int(state.startDuration ?? 0)
                let running = state.containers.filter { $0.isRunning }.count
                let msg = L.t(
                    "Colima démarré en \(duration)s — \(running) container(s) actif(s)",
                    "Colima started in \(duration)s — \(running) container(s) running"
                )
                appDelegate?.showSuccess(msg)
                if state.portainerExists {
                    NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
                }
            case .failure(let error):
                appDelegate?.showError(error.localizedDescription)
                self.showLastError(error.localizedDescription)
                self.update(state: .unknown)
            }
        })
    }

    @objc private func stopColima() {
        (NSApp.delegate as? AppDelegate)?.showSuccess(L.t("Arrêt de Colima…", "Stopping Colima…"))
        manager.stopColima(onTransition: { [weak self] state in
            self?.update(state: state)
        }, completion: { [weak self] result in
            let appDelegate = NSApp.delegate as? AppDelegate
            switch result {
            case .success(let state):
                self?.update(state: state)
                self?.clearLastError()
                appDelegate?.showSuccess(L.t("Colima arrêté", "Colima stopped"))
            case .failure(let error):
                appDelegate?.showError(error.localizedDescription)
                self?.showLastError(error.localizedDescription)
            }
        })
    }

    @objc private func openPortainer() {
        NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
    }

    @objc private func installPortainer() {
        installPortainerItem.isEnabled = false
        manager.installPortainer { [weak self] result in
            self?.installPortainerItem.isEnabled = true
            switch result {
            case .success: NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
            case .failure(let error):
                (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
                self?.showLastError(error.localizedDescription)
            }
        }
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
        manager.pruneDocker { [weak self] result in
            self?.pruneItem.isEnabled = true
            let appDelegate = NSApp.delegate as? AppDelegate
            switch result {
            case .success:
                appDelegate?.showSuccess(L.t("Docker purgé avec succès", "Docker pruned successfully"))
            case .failure(let error):
                appDelegate?.showError(error.localizedDescription)
            }
        }
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

    private func restartWithNewConfig() {
        manager.stopColima(onTransition: { [weak self] state in
            self?.update(state: state)
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.manager.startColima(onTransition: { [weak self] state in
                    self?.update(state: state)
                }, completion: { [weak self] result in
                    switch result {
                    case .success(let state):
                        self?.update(state: state)
                        if state.portainerExists {
                            NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
                        }
                    case .failure(let error):
                        (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
                    }
                })
            case .failure(let error):
                (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
            }
        })
    }

    @objc private func openContainersPanel() {
        guard let button = statusItem.button else { return }
        containersPanelVC.update(containers: lastState.containers, usage: lastState.usage)
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func openLogsTerminal(containerName name: String) {
        runInTerminal("docker logs -f \(name)")
    }

    private func openShellTerminal(containerName name: String) {
        runInTerminal("docker exec -it \(name) sh")
    }

    private func runInTerminal(_ command: String) {
        let script = "tell application \"Terminal\" to do script \"\(command)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    func showUpdateAvailable(version: String) {
        updateItem.title = L.t(
            "🔄 Mise à jour Colima \(version) disponible",
            "🔄 Colima \(version) update available")
        updateItem.isHidden = false
    }

    @objc private func upgradeColima() {
        let script = "tell application \"Terminal\" to do script \"brew upgrade colima\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
