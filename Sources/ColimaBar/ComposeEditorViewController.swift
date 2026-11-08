// Sources/ColimaBar/ComposeEditorViewController.swift
import AppKit
import ColimaBarCore

final class ComposeEditorViewController: NSViewController {
    private let composeService = DockerComposeService()

    // UI
    private let projectPicker = NSPopUpButton()
    private let scrollView = NSScrollView()
    private var textView: NSTextView!
    private let saveRestartButton = NSButton(title: "Save & Restart", target: nil, action: nil)
    private let dirtyIndicator = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "Aucun projet Docker Compose détecté")

    // State
    /// Projects found in the last poll; nil until the first one (so an empty list still shows the empty state).
    private var available: [ComposeProject]?
    /// Picker entries (available projects, plus the loaded one while it has unsaved edits).
    private var projects: [ComposeProject] = []
    private var originalContent = ""
    /// Project whose file is currently in the text view.
    private var loadedProject: ComposeProject? {
        didSet { if loadedProject != oldValue { onLoadedProjectChange?(loadedProject?.name) } }
    }
    private var saving = false {
        didSet { saveRestartButton.isEnabled = !saving && loadedProject != nil }
    }
    private var isDirty = false {
        didSet { updateDirtyIndicator() }
    }

    /// Called when the project shown in the editor changes (picker, poll, showProject).
    var onLoadedProjectChange: ((String?) -> Void)?
    var loadedProjectName: String? { loadedProject?.name }

    private var selectedProject: ComposeProject? {
        let idx = projectPicker.indexOfSelectedItem
        guard idx >= 0 && idx < projects.count else { return nil }
        return projects[idx]
    }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    // MARK: - Public

    /// Called on every poll: only acts when the project list changed. Keeps the loaded project,
    /// and keeps unsaved edits even if their project disappears (see `ComposeEditorPlan`).
    func updateContainers(_ containers: [DockerContainer]) {
        if !isViewLoaded { _ = view }
        let newAvailable = DockerComposeService.listProjects(from: containers).sorted { $0.name < $1.name }
        guard newAvailable != available else { return }
        available = newAvailable
        reconcile()
    }

    /// Selects a project by name, asking before dropping unsaved edits.
    /// Returns whether that project is now the one in the editor.
    @discardableResult
    func showProject(named name: String) -> Bool {
        if !isViewLoaded { _ = view }
        if loadedProject?.name == name { return true }
        guard let idx = projects.firstIndex(where: { $0.name == name }) else { return false }
        if isDirty && !confirmDiscard() { return false }
        projectPicker.selectItem(at: idx)
        loadSelectedProject()
        reconcile()
        return true
    }

    // MARK: - Private

    private func buildUI() {
        projectPicker.target = self
        projectPicker.action = #selector(projectChanged)
        projectPicker.translatesAutoresizingMaskIntoConstraints = false

        let tv = NSTextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.delegate = self
        tv.translatesAutoresizingMaskIntoConstraints = false
        textView = tv

        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        saveRestartButton.bezelStyle = .rounded
        saveRestartButton.target = self
        saveRestartButton.action = #selector(saveAndRestart)
        saveRestartButton.isEnabled = false
        saveRestartButton.translatesAutoresizingMaskIntoConstraints = false

        dirtyIndicator.stringValue = "● Modified"
        dirtyIndicator.textColor = .systemOrange
        dirtyIndicator.font = .systemFont(ofSize: 12)
        dirtyIndicator.isHidden = true
        dirtyIndicator.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        for sub in [projectPicker, scrollView, saveRestartButton, dirtyIndicator, emptyLabel] as [NSView] {
            view.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            projectPicker.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            projectPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            projectPicker.widthAnchor.constraint(equalToConstant: 200),

            dirtyIndicator.centerYAnchor.constraint(equalTo: projectPicker.centerYAnchor),
            dirtyIndicator.leadingAnchor.constraint(equalTo: projectPicker.trailingAnchor, constant: 12),

            scrollView.topAnchor.constraint(equalTo: projectPicker.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: saveRestartButton.topAnchor, constant: -8),

            saveRestartButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            saveRestartButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            saveRestartButton.widthAnchor.constraint(equalToConstant: 140),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func reconcile() {
        let plan = ComposeEditorPlan.reconcile(available: available ?? [], loaded: loadedProject, dirty: isDirty)
        projects = plan.entries
        projectPicker.removeAllItems()
        projectPicker.addItems(withTitles: projects.map { p in
            (available ?? []).contains(p) ? p.name : "\(p.name) (\(L.t("détaché", "detached")))"
        })
        guard let selection = plan.selection, let idx = projects.firstIndex(of: selection) else {
            loadedProject = nil
            emptyLabel.isHidden = false
            scrollView.isHidden = true
            saveRestartButton.isEnabled = false
            dirtyIndicator.isHidden = true
            return
        }
        emptyLabel.isHidden = true
        scrollView.isHidden = false
        saveRestartButton.isEnabled = !saving
        updateDirtyIndicator()
        projectPicker.selectItem(at: idx)
        if plan.reload { loadSelectedProject() }
    }

    private func loadSelectedProject() {
        guard let project = selectedProject else { return }
        loadedProject = project
        let content = (try? composeService.readComposeFile(at: project.configFile)) ?? ""
        originalContent = content
        textView.string = content
        isDirty = false
        saveRestartButton.isEnabled = true
    }

    private func updateDirtyIndicator() {
        dirtyIndicator.isHidden = !isDirty
    }

    private func confirmDiscard() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Changements non sauvegardés"
        alert.informativeText = "Changer de projet abandonnera les modifications en cours."
        alert.addButton(withTitle: "Continuer")
        alert.addButton(withTitle: "Annuler")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func projectChanged() {
        if isDirty && !confirmDiscard() {
            // Keep the picker on the project whose edits are still in the editor.
            if let loadedProject, let idx = projects.firstIndex(of: loadedProject) {
                projectPicker.selectItem(at: idx)
            }
            return
        }
        loadSelectedProject()
        reconcile()   // drops a detached entry whose edits were just discarded
    }

    @objc private func saveAndRestart() {
        guard let project = loadedProject else { return }
        let alert = NSAlert()
        alert.messageText = "Save & Restart"
        alert.informativeText = "Enregistrer le fichier et relancer '\(project.name)' avec docker compose up -d --build ?"
        alert.addButton(withTitle: "Confirmer")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        saving = true
        let content = textView.string
        DispatchQueue.global().async {
            do {
                try self.composeService.saveAndRestart(content: content, project: project)
                DispatchQueue.main.async {
                    self.saving = false
                    // The user may have switched project or kept typing meanwhile.
                    guard self.loadedProject == project else { return }
                    self.originalContent = content
                    self.isDirty = self.textView.string != content
                }
            } catch {
                DispatchQueue.main.async {
                    self.saving = false
                    let err = NSAlert()
                    err.messageText = "Erreur"
                    err.informativeText = error.localizedDescription
                    err.runModal()
                }
            }
        }
    }
}

extension ComposeEditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        isDirty = textView.string != originalContent
    }
}
