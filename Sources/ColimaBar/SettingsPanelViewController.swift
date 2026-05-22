import AppKit
import ColimaBarCore

final class SettingsPanelViewController: NSViewController {

    var onApplyConfig:     (() -> Void)?
    var onSetLanguage:     ((AppLanguage) -> Void)?
    var onToggleLoginItem: (() -> Void)?
    var onResizeDisk:      (() -> Void)?

    var isColimaRunning    = false
    var isLoginItemEnabled = false

    private var instanceField:  NSTextField!
    private var profileControl: NSSegmentedControl!
    private var cpuControl:     NSSegmentedControl!
    private var memControl:     NSSegmentedControl!
    private var diskControl:    NSSegmentedControl!
    private var langControl:    NSSegmentedControl!
    private var autoStartCheck: NSButton!
    private var loginCheck:     NSButton!
    private var pollingControl: NSSegmentedControl!
    private var compactCheck:   NSButton!
    private var resizeDiskBtn:  NSButton!

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 520))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        syncControls()
    }

    func syncControls() {
        guard isViewLoaded else { return }
        instanceField.stringValue = ColimaConfig.activeInstanceName

        let cpu  = ColimaConfig.desiredCPUs
        let mem  = ColimaConfig.desiredMemoryGB
        let disk = ColimaConfig.desiredDiskGB

        for (i, p) in ColimaProfile.presets.enumerated() {
            profileControl.setSelected(p.cpus == cpu && p.memoryGB == mem, forSegment: i)
        }
        for (i, v) in ColimaConfig.cpuOptions.enumerated()    { cpuControl.setSelected(v == cpu,  forSegment: i) }
        for (i, v) in ColimaConfig.memoryOptions.enumerated() { memControl.setSelected(v == mem,  forSegment: i) }
        for (i, v) in ColimaConfig.diskOptions.enumerated()   { diskControl.setSelected(v == disk, forSegment: i) }

        let langs: [AppLanguage] = [.system, .french, .english]
        for (i, l) in langs.enumerated() { langControl.setSelected(L.current == l, forSegment: i) }

        autoStartCheck.state = ColimaConfig.autoStartOnLaunch ? .on : .off
        loginCheck.state     = isLoginItemEnabled ? .on : .off

        let preset = ColimaConfig.pollingPreset
        for (i, p) in PollingPreset.allCases.enumerated() {
            pollingControl.setSelected(p == preset, forSegment: i)
        }
        compactCheck.state      = ColimaConfig.compactModeEnabled ? .on : .off
        resizeDiskBtn.isEnabled = isColimaRunning
    }

    // MARK: - UI

    private func buildUI() {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment   = .leading
        outer.spacing     = 10
        outer.edgeInsets  = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        outer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: view.topAnchor),
            outer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outer.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])

        // Instance
        outer.addArrangedSubview(header(L.t("Instance Colima", "Colima Instance")))
        instanceField = NSTextField()
        instanceField.placeholderString = "default"
        instanceField.controlSize       = .small
        instanceField.font              = .systemFont(ofSize: 12)
        instanceField.target            = self
        instanceField.action            = #selector(instanceChanged)
        instanceField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        outer.addArrangedSubview(instanceField)
        outer.addArrangedSubview(sep())

        // Profiles
        outer.addArrangedSubview(header(L.t("Profils", "Profiles")))
        let profileLabels = ColimaProfile.presets.map { p -> String in
            let n = L.effective == .french ? p.nameFR : p.name
            return "\(n)\n\(p.cpus)C/\(p.memoryGB)G"
        }
        profileControl = NSSegmentedControl(labels: profileLabels, trackingMode: .selectAny,
                                             target: self, action: #selector(profileChanged(_:)))
        profileControl.controlSize = .small
        outer.addArrangedSubview(profileControl)
        outer.addArrangedSubview(sep())

        // CPU / Memory / Disk
        outer.addArrangedSubview(header("CPUs"))
        cpuControl = seg(ColimaConfig.cpuOptions.map { "\($0)" }, #selector(cpuChanged(_:)))
        outer.addArrangedSubview(cpuControl)

        outer.addArrangedSubview(header(L.t("Mémoire", "Memory")))
        memControl = seg(ColimaConfig.memoryOptions.map { "\($0) GB" }, #selector(memChanged(_:)))
        outer.addArrangedSubview(memControl)

        outer.addArrangedSubview(header(L.t("Disque", "Disk")))
        diskControl = seg(ColimaConfig.diskOptions.map { "\($0) GB" }, #selector(diskChanged(_:)))
        outer.addArrangedSubview(diskControl)

        resizeDiskBtn = NSButton(
            title: L.t("Redimensionner le disque…", "Resize disk…"),
            target: self, action: #selector(resizeDiskTapped))
        resizeDiskBtn.bezelStyle  = .rounded
        resizeDiskBtn.controlSize = .small
        outer.addArrangedSubview(resizeDiskBtn)
        outer.addArrangedSubview(sep())

        // Language
        outer.addArrangedSubview(header(L.t("Langue", "Language")))
        langControl = seg([L.t("Système", "System"), "Français", "English"], #selector(langChanged(_:)))
        outer.addArrangedSubview(langControl)
        outer.addArrangedSubview(sep())

        outer.addArrangedSubview(header(L.t("Intervalle de polling", "Polling interval")))
        pollingControl = seg(PollingPreset.allCases.map { $0.label }, #selector(pollingChanged(_:)))
        outer.addArrangedSubview(pollingControl)
        outer.addArrangedSubview(sep())

        compactCheck = NSButton(
            checkboxWithTitle: L.t("Afficher le nombre de containers actifs", "Show running container count"),
            target: self, action: #selector(compactToggled))
        compactCheck.controlSize = .small
        outer.addArrangedSubview(compactCheck)

        // Toggles
        autoStartCheck = NSButton(
            checkboxWithTitle: L.t("Démarrer Colima au lancement de l'app", "Auto-start Colima on launch"),
            target: self, action: #selector(autoStartToggled))
        autoStartCheck.controlSize = .small
        outer.addArrangedSubview(autoStartCheck)

        loginCheck = NSButton(
            checkboxWithTitle: L.t("Lancer l'app au démarrage du Mac", "Launch app at login"),
            target: self, action: #selector(loginToggled))
        loginCheck.controlSize = .small
        outer.addArrangedSubview(loginCheck)
    }

    private func header(_ title: String) -> NSTextField {
        let tf = NSTextField(labelWithString: title)
        tf.font      = .boldSystemFont(ofSize: 11)
        tf.textColor = .secondaryLabelColor
        return tf
    }

    private func sep() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }

    private func seg(_ labels: [String], _ action: Selector) -> NSSegmentedControl {
        let c = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                                   target: self, action: action)
        c.controlSize = .small
        return c
    }

    // MARK: - Actions

    @objc private func instanceChanged() {
        let v = instanceField.stringValue.trimmingCharacters(in: .whitespaces)
        ColimaConfig.activeInstanceName = v.isEmpty ? "default" : v
    }

    @objc private func profileChanged(_ sender: NSSegmentedControl) {
        let idx = sender.selectedSegment
        guard idx >= 0, idx < ColimaProfile.presets.count else { return }
        for i in 0..<sender.segmentCount { sender.setSelected(i == idx, forSegment: i) }
        let p = ColimaProfile.presets[idx]
        ColimaConfig.desiredCPUs      = p.cpus
        ColimaConfig.desiredMemoryGB  = p.memoryGB
        for (i, v) in ColimaConfig.cpuOptions.enumerated()    { cpuControl.setSelected(v == p.cpus,      forSegment: i) }
        for (i, v) in ColimaConfig.memoryOptions.enumerated() { memControl.setSelected(v == p.memoryGB,  forSegment: i) }
        if isColimaRunning { onApplyConfig?() }
    }

    @objc private func cpuChanged(_ sender: NSSegmentedControl) {
        let cpu = ColimaConfig.cpuOptions[sender.selectedSegment]
        ColimaConfig.desiredCPUs = cpu
        syncProfileHighlight()
        if isColimaRunning { onApplyConfig?() }
    }

    @objc private func memChanged(_ sender: NSSegmentedControl) {
        let mem = ColimaConfig.memoryOptions[sender.selectedSegment]
        ColimaConfig.desiredMemoryGB = mem
        syncProfileHighlight()
        if isColimaRunning { onApplyConfig?() }
    }

    @objc private func diskChanged(_ sender: NSSegmentedControl) {
        ColimaConfig.desiredDiskGB = ColimaConfig.diskOptions[sender.selectedSegment]
        // Disk resize takes effect on next start only
    }

    @objc private func langChanged(_ sender: NSSegmentedControl) {
        let langs: [AppLanguage] = [.system, .french, .english]
        let lang = langs[sender.selectedSegment]
        L.current = lang
        onSetLanguage?(lang)
    }

    @objc private func autoStartToggled() {
        ColimaConfig.autoStartOnLaunch = autoStartCheck.state == .on
    }

    @objc private func loginToggled() {
        onToggleLoginItem?()
        loginCheck.state = isLoginItemEnabled ? .on : .off
    }

    @objc private func pollingChanged(_ sender: NSSegmentedControl) {
        ColimaConfig.pollingPreset = PollingPreset.allCases[sender.selectedSegment]
    }

    @objc private func compactToggled() {
        ColimaConfig.compactModeEnabled = compactCheck.state == .on
    }

    @objc private func resizeDiskTapped() {
        let alert = NSAlert()
        alert.messageText     = L.t("Redimensionner le disque", "Resize disk")
        alert.informativeText = L.t(
            "Le disque sera redimensionné à \(ColimaConfig.desiredDiskGB) GB. Colima va redémarrer (30–60 s).",
            "Disk will be resized to \(ColimaConfig.desiredDiskGB) GB. Colima will restart (30–60 s).")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.t("Redimensionner", "Resize"))
        alert.addButton(withTitle: L.t("Annuler", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onResizeDisk?()
    }

    private func syncProfileHighlight() {
        let cpu = ColimaConfig.desiredCPUs
        let mem = ColimaConfig.desiredMemoryGB
        for (i, p) in ColimaProfile.presets.enumerated() {
            profileControl.setSelected(p.cpus == cpu && p.memoryGB == mem, forSegment: i)
        }
    }
}
