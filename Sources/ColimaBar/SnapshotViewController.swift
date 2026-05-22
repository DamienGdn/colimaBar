// Sources/ColimaBar/SnapshotViewController.swift
import AppKit
import ColimaBarCore

final class SnapshotViewController: NSViewController {
    private let snapshotService = SnapshotService()

    // UI
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let createButton = NSButton(title: "Créer snapshot", target: nil, action: nil)
    private let restoreButton = NSButton(title: "Restaurer", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Supprimer", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")

    // State
    private var snapshots: [ColimaSnapshot] = []

    private var selectedSnapshot: ColimaSnapshot? {
        let row = tableView.selectedRow
        guard row >= 0 && row < snapshots.count else { return nil }
        return snapshots[row]
    }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reload()
    }

    // MARK: - Private

    private func buildUI() {
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Nom"; nameCol.width = 260
        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateCol.title = "Date"; dateCol.width = 160
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Taille"; sizeCol.width = 80
        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(dateCol)
        tableView.addTableColumn(sizeCol)
        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        createButton.bezelStyle = .rounded
        createButton.target = self
        createButton.action = #selector(createSnapshot)
        createButton.translatesAutoresizingMaskIntoConstraints = false

        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreSnapshot)
        restoreButton.isEnabled = false
        restoreButton.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteSnapshot)
        deleteButton.isEnabled = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.style = .spinning
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        for sub in [scrollView, createButton, restoreButton, deleteButton, progressIndicator, statusLabel] as [NSView] {
            view.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: createButton.topAnchor, constant: -8),

            createButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            createButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            createButton.widthAnchor.constraint(equalToConstant: 130),

            restoreButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
            restoreButton.leadingAnchor.constraint(equalTo: createButton.trailingAnchor, constant: 8),
            restoreButton.widthAnchor.constraint(equalToConstant: 90),

            deleteButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: restoreButton.trailingAnchor, constant: 8),
            deleteButton.widthAnchor.constraint(equalToConstant: 90),

            progressIndicator.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
            progressIndicator.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 12),
            progressIndicator.widthAnchor.constraint(equalToConstant: 16),
            progressIndicator.heightAnchor.constraint(equalToConstant: 16),

            statusLabel.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    private func reload() {
        snapshots = snapshotService.listSnapshots()
        tableView.reloadData()
        updateButtonStates()
    }

    private func updateButtonStates() {
        let hasSelection = tableView.selectedRow >= 0
        restoreButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
    }

    private func setLoading(_ on: Bool, status: String = "") {
        progressIndicator.isHidden = !on
        if on { progressIndicator.startAnimation(nil) } else { progressIndicator.stopAnimation(nil) }
        statusLabel.stringValue = status
        createButton.isEnabled = !on
        restoreButton.isEnabled = !on
        deleteButton.isEnabled = !on
    }

    @objc private func createSnapshot() {
        let alert = NSAlert()
        alert.messageText = "Créer un snapshot"
        alert.informativeText = "Colima sera arrêté puis redémarré. Donnez un nom au snapshot :"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = "backup"
        alert.accessoryView = field
        alert.addButton(withTitle: "Créer")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        setLoading(true, status: "Arrêt de Colima…")
        DispatchQueue.global().async {
            do {
                try self.snapshotService.createSnapshot(name: name)
                DispatchQueue.main.async {
                    self.setLoading(false)
                    self.reload()
                }
            } catch {
                DispatchQueue.main.async {
                    self.setLoading(false)
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func restoreSnapshot() {
        guard let snap = selectedSnapshot else { return }
        let alert = NSAlert()
        alert.messageText = "Restaurer le snapshot"
        alert.informativeText = "Colima sera arrêté et redémarré avec le snapshot '\(snap.name)'. Cette opération écrasera l'état actuel. Continuer ?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restaurer")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setLoading(true, status: "Restauration en cours…")
        DispatchQueue.global().async {
            do {
                try self.snapshotService.restoreSnapshot(snap)
                DispatchQueue.main.async {
                    self.setLoading(false)
                    self.reload()
                }
            } catch {
                DispatchQueue.main.async {
                    self.setLoading(false)
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func deleteSnapshot() {
        guard let snap = selectedSnapshot else { return }
        let alert = NSAlert()
        alert.messageText = "Supprimer le snapshot"
        alert.informativeText = "'\(snap.name)' sera supprimé définitivement."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Supprimer")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try snapshotService.deleteSnapshot(snap)
            reload()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Erreur"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}

extension SnapshotViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { snapshots.count }
}

extension SnapshotViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let snap = snapshots[row]
        let cell = NSTableCellView()
        let lbl = NSTextField(labelWithString: "")
        lbl.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            lbl.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            lbl.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        ])
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        switch tableColumn?.identifier.rawValue {
        case "name": lbl.stringValue = snap.name
        case "date": lbl.stringValue = df.string(from: snap.date)
        case "size": lbl.stringValue = snap.formattedSize
        default: break
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }
}
