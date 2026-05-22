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
    private var projects: [ComposeProject] = []
    private var originalContent = ""
    private var isDirty = false {
        didSet { updateDirtyIndicator() }
    }

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

    func updateContainers(_ containers: [DockerContainer]) {
        if !isViewLoaded { _ = view }
        projects = DockerComposeService.listProjects(from: containers)
        projectPicker.removeAllItems()
        if projects.isEmpty {
            emptyLabel.isHidden = false
            scrollView.isHidden = true
            saveRestartButton.isEnabled = false
            dirtyIndicator.isHidden = true
            return
        }
        emptyLabel.isHidden = true
        scrollView.isHidden = false
        projectPicker.addItems(withTitles: projects.map { $0.name })
        loadSelectedProject()
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

    private func loadSelectedProject() {
        guard let project = selectedProject else { return }
        let content = (try? composeService.readComposeFile(at: project.configFile)) ?? ""
        originalContent = content
        textView.string = content
        isDirty = false
        saveRestartButton.isEnabled = true
    }

    private func updateDirtyIndicator() {
        dirtyIndicator.isHidden = !isDirty
    }

    @objc private func projectChanged() {
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "Changements non sauvegardés"
            alert.informativeText = "Changer de projet abandonnera les modifications en cours."
            alert.addButton(withTitle: "Continuer")
            alert.addButton(withTitle: "Annuler")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }
        loadSelectedProject()
    }

    @objc private func saveAndRestart() {
        guard let project = selectedProject else { return }
        let alert = NSAlert()
        alert.messageText = "Save & Restart"
        alert.informativeText = "Enregistrer le fichier et relancer '\(project.name)' avec docker compose up -d --build ?"
        alert.addButton(withTitle: "Confirmer")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        saveRestartButton.isEnabled = false
        let content = textView.string
        DispatchQueue.global().async {
            do {
                try self.composeService.saveAndRestart(content: content, project: project)
                DispatchQueue.main.async {
                    self.originalContent = content
                    self.isDirty = false
                    self.saveRestartButton.isEnabled = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.saveRestartButton.isEnabled = true
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
