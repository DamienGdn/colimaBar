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

    // Config submenu
    private var cpuMenuItems: [NSMenuItem] = []
    private var memMenuItems: [NSMenuItem] = []
    private var langMenuItems: [AppLanguage: NSMenuItem] = [:]
    private var profileMenuItems: [NSMenuItem] = []
    private var isColimaRunning = false
    private var containersItem: NSMenuItem!
    private var containersMenu: NSMenu!
    private var updateItem: NSMenuItem!

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
    }

    private func buildMenu() {
        cpuMenuItems = []
        memMenuItems = []
        langMenuItems = [:]
        profileMenuItems = []
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

        containersMenu = NSMenu()
        containersItem = NSMenuItem(title: L.t("Containers", "Containers"), action: nil, keyEquivalent: "")
        containersItem.submenu = containersMenu
        containersItem.isHidden = true
        menu.addItem(containersItem)

        updateItem = NSMenuItem(title: "", action: #selector(upgradeColima), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // ⚙ Configuration submenu
        let configItem = NSMenuItem(title: "⚙ \(L.t("Configuration", "Configuration"))", action: nil, keyEquivalent: "")
        let configMenu = NSMenu()

        let cpuHeader = NSMenuItem(title: "CPUs", action: nil, keyEquivalent: "")
        cpuHeader.isEnabled = false
        configMenu.addItem(cpuHeader)

        for cpu in ColimaConfig.cpuOptions {
            let item = NSMenuItem(
                title: "\(cpu) CPU\(cpu > 1 ? "s" : "")",
                action: #selector(setCPU(_:)), keyEquivalent: "")
            item.tag = cpu
            item.target = self
            configMenu.addItem(item)
            cpuMenuItems.append(item)
        }

        configMenu.addItem(NSMenuItem.separator())

        let memHeader = NSMenuItem(title: L.t("Mémoire", "Memory"), action: nil, keyEquivalent: "")
        memHeader.isEnabled = false
        configMenu.addItem(memHeader)

        for gb in ColimaConfig.memoryOptions {
            let item = NSMenuItem(title: "\(gb) GB", action: #selector(setMemory(_:)), keyEquivalent: "")
            item.tag = gb
            item.target = self
            configMenu.addItem(item)
            memMenuItems.append(item)
        }

        configMenu.addItem(NSMenuItem.separator())

        let langHeader = NSMenuItem(title: L.t("Langue", "Language"), action: nil, keyEquivalent: "")
        langHeader.isEnabled = false
        configMenu.addItem(langHeader)

        let langOptions: [(AppLanguage, String)] = [
            (.system,  L.t("Système (auto)", "System (auto)")),
            (.french,  "Français"),
            (.english, "English"),
        ]
        for (lang, title) in langOptions {
            let item = NSMenuItem(title: title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang.rawValue
            item.state = L.current == lang ? .on : .off
            item.target = self
            configMenu.addItem(item)
            langMenuItems[lang] = item
        }

        configMenu.addItem(NSMenuItem.separator())

        let profileHeader = NSMenuItem(title: L.t("Profils", "Profiles"), action: nil, keyEquivalent: "")
        profileHeader.isEnabled = false
        configMenu.addItem(profileHeader)

        for profile in ColimaProfile.presets {
            let displayName = L.effective == .french ? profile.nameFR : profile.name
            let item = NSMenuItem(
                title: "\(displayName) — \(profile.cpus) CPU / \(profile.memoryGB) GB",
                action: #selector(applyProfile(_:)),
                keyEquivalent: "")
            item.representedObject = profile.name
            item.target = self
            configMenu.addItem(item)
            profileMenuItems.append(item)
        }

        configItem.submenu = configMenu
        menu.addItem(configItem)

        // Login at startup
        loginItem = NSMenuItem(
            title: L.t("Lancer au démarrage", "Launch at login"),
            action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        quitItem = NSMenuItem(
            title: L.t("Quitter", "Quit"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - State updates

    func update(state: ColimaAppState) {
        lastState = state
        updateIcon(colima: state.colima)
        updateMenuItems(state: state)
    }

    private func updateIcon(colima: ColimaRunningState) {
        guard let button = statusItem.button else { return }
        let color: NSColor
        switch colima {
        case .running:             color = .systemGreen
        case .stopped, .unknown:   color = .labelColor
        case .transitioning:       color = .systemYellow
        }
        button.image = colimaIcon(tinted: color)
    }

    private func colimaIcon(tinted color: NSColor) -> NSImage {
        let base = NSImage(named: "colimabar")
            ?? NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "ColimaBar")!
        let size = base.size
        let result = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
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

        if let appDelegate = NSApp.delegate as? AppDelegate {
            loginItem.state = appDelegate.isLoginItemEnabled() ? .on : .off
        }

        let currentCPU = state.cpus ?? ColimaConfig.desiredCPUs
        let currentMem = state.memoryGB.map { Int($0.rounded()) } ?? ColimaConfig.desiredMemoryGB
        for item in cpuMenuItems { item.state = item.tag == currentCPU ? .on : .off }
        for item in memMenuItems { item.state = item.tag == currentMem ? .on : .off }

        let activeCPU = state.cpus ?? ColimaConfig.desiredCPUs
        let activeMem = state.memoryGB.map { Int($0.rounded()) } ?? ColimaConfig.desiredMemoryGB
        for item in profileMenuItems {
            guard let name = item.representedObject as? String,
                  let profile = ColimaProfile.presets.first(where: { $0.name == name }) else { continue }
            item.state = (profile.cpus == activeCPU && profile.memoryGB == activeMem) ? .on : .off
        }

        updateContainersSubmenu(state.containers)
    }

    private func updateContainersSubmenu(_ containers: [DockerContainer]) {
        containersMenu.removeAllItems()
        guard !containers.isEmpty else {
            containersItem.isHidden = true
            return
        }

        let runningCount = containers.filter { $0.isRunning }.count
        containersItem.title = "\(runningCount)/\(containers.count) \(L.t("containers", "containers"))"
        containersItem.isHidden = false

        for container in containers {
            let stateIcon = container.isRunning ? "▶" : "■"
            let row = NSMenuItem(
                title: "\(stateIcon) \(container.name)",
                action: nil, keyEquivalent: "")

            let sub = NSMenu()

            if container.isRunning {
                let stopItem = NSMenuItem(
                    title: L.t("Arrêter", "Stop"),
                    action: #selector(stopContainerAction(_:)),
                    keyEquivalent: "")
                stopItem.representedObject = container.name
                stopItem.target = self
                sub.addItem(stopItem)
            } else {
                let startItem = NSMenuItem(
                    title: L.t("Démarrer", "Start"),
                    action: #selector(startContainerAction(_:)),
                    keyEquivalent: "")
                startItem.representedObject = container.name
                startItem.target = self
                sub.addItem(startItem)
            }

            let logsItem = NSMenuItem(
                title: L.t("Voir les logs", "View logs"),
                action: #selector(openContainerLogs(_:)),
                keyEquivalent: "")
            logsItem.representedObject = container.name
            logsItem.target = self
            sub.addItem(logsItem)

            row.submenu = sub
            containersMenu.addItem(row)
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

    @objc private func toggleLoginItem() {
        (NSApp.delegate as? AppDelegate)?.toggleLoginItem()
        if let appDelegate = NSApp.delegate as? AppDelegate {
            loginItem.state = appDelegate.isLoginItemEnabled() ? .on : .off
        }
    }

    @objc private func setCPU(_ sender: NSMenuItem) {
        let cpus = sender.tag
        ColimaConfig.desiredCPUs = cpus
        for item in cpuMenuItems { item.state = item.tag == cpus ? .on : .off }
        if isColimaRunning { restartWithNewConfig() }
    }

    @objc private func setMemory(_ sender: NSMenuItem) {
        let gb = sender.tag
        ColimaConfig.desiredMemoryGB = gb
        for item in memMenuItems { item.state = item.tag == gb ? .on : .off }
        if isColimaRunning { restartWithNewConfig() }
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        let raw = sender.representedObject as? String ?? "system"
        L.current = AppLanguage(rawValue: raw) ?? .system
        let state = lastState
        buildMenu()
        statusItem.menu = menu
        update(state: state)
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

    @objc private func startContainerAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        manager.startContainer(name) { [weak self] result in
            if case .failure(let error) = result {
                self?.showLastError(error.localizedDescription)
            }
        }
    }

    @objc private func stopContainerAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        manager.stopContainer(name) { [weak self] result in
            if case .failure(let error) = result {
                self?.showLastError(error.localizedDescription)
            }
        }
    }

    @objc private func openContainerLogs(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let script = "tell application \"Terminal\" to do script \"docker logs -f \(name)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    @objc private func applyProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let profile = ColimaProfile.presets.first(where: { $0.name == name }) else { return }
        ColimaConfig.desiredCPUs = profile.cpus
        ColimaConfig.desiredMemoryGB = profile.memoryGB
        for item in cpuMenuItems { item.state = item.tag == profile.cpus ? .on : .off }
        for item in memMenuItems { item.state = item.tag == profile.memoryGB ? .on : .off }
        for item in profileMenuItems {
            item.state = (item.representedObject as? String) == name ? .on : .off
        }
        if isColimaRunning { restartWithNewConfig() }
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
