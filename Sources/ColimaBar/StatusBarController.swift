import AppKit
import ColimaBarCore

final class StatusBarController {
    private let manager: ColimaManager
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // Status display items
    private var colimaStatusItem: NSMenuItem!
    private var resourcesItem: NSMenuItem!

    // Action items
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var openPortainerItem: NSMenuItem!
    private var portainerWarningItem: NSMenuItem!
    private var installPortainerItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    // Config submenu properties (populated in Task 8)
    private var cpuMenuItems: [NSMenuItem] = []
    private var memMenuItems: [NSMenuItem] = []
    private var isColimaRunning = false

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
        menu = NSMenu()

        colimaStatusItem = NSMenuItem(title: "Colima : …", action: nil, keyEquivalent: "")
        colimaStatusItem.isEnabled = false
        menu.addItem(colimaStatusItem)

        resourcesItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        resourcesItem.isEnabled = false
        resourcesItem.isHidden = true
        menu.addItem(resourcesItem)

        menu.addItem(NSMenuItem.separator())

        startItem = NSMenuItem(title: "▶ Démarrer Colima", action: #selector(startColima), keyEquivalent: "")
        startItem.target = self
        menu.addItem(startItem)

        stopItem = NSMenuItem(title: "■ Arrêter Colima", action: #selector(stopColima), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        portainerWarningItem = NSMenuItem(title: "⚠ Portainer non installé", action: nil, keyEquivalent: "")
        portainerWarningItem.isEnabled = false
        portainerWarningItem.isHidden = true
        menu.addItem(portainerWarningItem)

        installPortainerItem = NSMenuItem(title: "Installer Portainer…", action: #selector(installPortainer), keyEquivalent: "")
        installPortainerItem.target = self
        installPortainerItem.isHidden = true
        menu.addItem(installPortainerItem)

        openPortainerItem = NSMenuItem(title: "Ouvrir Portainer", action: #selector(openPortainer), keyEquivalent: "")
        openPortainerItem.target = self
        openPortainerItem.isHidden = true
        menu.addItem(openPortainerItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem.separator())

        let configItem = NSMenuItem(title: "⚙ Configuration", action: nil, keyEquivalent: "")
        let configMenu = NSMenu()

        let cpuHeader = NSMenuItem(title: "CPUs", action: nil, keyEquivalent: "")
        cpuHeader.isEnabled = false
        configMenu.addItem(cpuHeader)

        for cpu in ColimaConfig.cpuOptions {
            let item = NSMenuItem(
                title: "\(cpu) CPU\(cpu > 1 ? "s" : "")",
                action: #selector(setCPU(_:)),
                keyEquivalent: ""
            )
            item.tag = cpu
            item.target = self
            configMenu.addItem(item)
            cpuMenuItems.append(item)
        }

        configMenu.addItem(NSMenuItem.separator())

        let memHeader = NSMenuItem(title: "Mémoire", action: nil, keyEquivalent: "")
        memHeader.isEnabled = false
        configMenu.addItem(memHeader)

        for gb in ColimaConfig.memoryOptions {
            let item = NSMenuItem(
                title: "\(gb) GB",
                action: #selector(setMemory(_:)),
                keyEquivalent: ""
            )
            item.tag = gb
            item.target = self
            configMenu.addItem(item)
            memMenuItems.append(item)
        }

        configItem.submenu = configMenu
        menu.addItem(configItem)

        loginItem = NSMenuItem(title: "Lancer au démarrage", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - State updates

    func update(state: ColimaAppState) {
        updateIcon(colima: state.colima)
        updateMenuItems(state: state)
    }

    private func updateIcon(colima: ColimaRunningState) {
        guard let button = statusItem.button else { return }
        let color: NSColor
        switch colima {
        case .running:                  color = .systemGreen
        case .stopped, .unknown:        color = .secondaryLabelColor
        case .transitioning:            color = .systemYellow
        }
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        if let base = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "ColimaBar"),
           let colored = base.withSymbolConfiguration(config) {
            colored.isTemplate = false
            button.image = colored
        }
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
            colimaStatusItem.title = running ? "● Colima : En cours d'exécution" : "○ Colima : Arrêté"
            transitioning = false
        }

        if let cpus = state.cpus, let mem = state.memoryGB {
            resourcesItem.title = String(format: "   CPUs: %d  |  Mémoire: %.0f GB", cpus, mem)
            resourcesItem.isHidden = false
        } else {
            resourcesItem.isHidden = true
        }

        startItem.isEnabled = !running && !transitioning
        stopItem.isEnabled = running && !transitioning

        openPortainerItem.isHidden = !running || !state.portainerExists
        portainerWarningItem.isHidden = !running || state.portainerExists
        installPortainerItem.isHidden = !running || state.portainerExists

        isColimaRunning = running

        // Update login item checkmark
        if let appDelegate = NSApp.delegate as? AppDelegate {
            loginItem.state = appDelegate.isLoginItemEnabled() ? .on : .off
        }

        // Config submenu checkmarks updated in Task 8
        let currentCPU = state.cpus ?? ColimaConfig.desiredCPUs
        let currentMem = state.memoryGB.map { Int($0.rounded()) } ?? ColimaConfig.desiredMemoryGB
        for item in cpuMenuItems { item.state = item.tag == currentCPU ? .on : .off }
        for item in memMenuItems { item.state = item.tag == currentMem ? .on : .off }
    }

    // MARK: - Actions

    @objc private func startColima() {
        manager.startColima(onTransition: { [weak self] state in
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
                self?.update(state: .unknown)
            }
        })
    }

    @objc private func stopColima() {
        manager.stopColima(onTransition: { [weak self] state in
            self?.update(state: state)
        }, completion: { [weak self] result in
            switch result {
            case .success(let state):
                self?.update(state: state)
            case .failure(let error):
                (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
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
            case .success:
                NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
            case .failure(let error):
                (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
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
}
