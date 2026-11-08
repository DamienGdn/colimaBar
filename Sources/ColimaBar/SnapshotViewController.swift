// Sources/ColimaBar/SnapshotViewController.swift
import AppKit
import ColimaBarCore

final class SnapshotViewController: NSViewController {
    private let snapshotService = SnapshotService()

    // UI
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var card: ThemedView!
    private let createButton = NSButton(title: L.t("Créer snapshot", "Create snapshot"), target: nil, action: nil)
    private let restoreButton = NSButton(title: L.t("Restaurer", "Restore"), target: nil, action: nil)
    private let deleteButton = NSButton(title: L.t("Supprimer", "Delete"), target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: L.t("Aucun snapshot — cliquez « Créer snapshot » pour sauvegarder l'état actuel de la VM", "No snapshot — click “Create snapshot” to save the current VM state"))

    // State
    private var snapshots: [ColimaSnapshot] = []

    private var selectedSnapshot: ColimaSnapshot? {
        let row = tableView.selectedRow
        guard row >= 0 && row < snapshots.count else { return nil }
        return snapshots[row]
    }

    override func loadView() { view = ThemedView(fill: Theme.Tokens.bg) }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reload()
    }

    // MARK: - Private

    private func buildUI() {
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = L.t("Nom", "Name"); nameCol.width = 260
        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateCol.title = "Date"; dateCol.width = 160
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = L.t("Taille", "Size"); sizeCol.width = 80
        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(dateCol)
        tableView.addTableColumn(sizeCol)
        tableView.delegate = self
        tableView.dataSource = self
        Theme.styleTable(tableView)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        card = Theme.card(wrapping: scrollView)

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

        statusLabel.textColor = Theme.Tokens.text2
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = Theme.Tokens.text3
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byWordWrapping
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        for sub in [card, createButton, restoreButton, deleteButton, progressIndicator, statusLabel, emptyLabel] as [NSView] {
            view.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: createButton.topAnchor, constant: -8),

            createButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            createButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            createButton.widthAnchor.constraint(equalToConstant: 150),

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

            emptyLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: card.widthAnchor, constant: -40),
        ])
    }

    private func reload() {
        snapshots = snapshotService.listSnapshots()
        tableView.reloadData()
        emptyLabel.isHidden = !snapshots.isEmpty
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
        alert.messageText = L.t("Créer un snapshot", "Create a snapshot")
        alert.informativeText = L.t("Colima sera arrêté puis redémarré. Donnez un nom au snapshot :", "Colima will be stopped then restarted. Name the snapshot:")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = "backup"
        alert.accessoryView = field
        alert.addButton(withTitle: L.t("Créer", "Create"))
        alert.addButton(withTitle: L.t("Annuler", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        setLoading(true, status: L.t("Arrêt de Colima…", "Stopping Colima…"))
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
        alert.messageText = L.t("Restaurer le snapshot", "Restore the snapshot")
        alert.informativeText = L.t("Colima sera arrêté et redémarré avec le snapshot '\(snap.name)'. Cette opération écrasera l'état actuel. Continuer ?", "Colima will be stopped and restarted with snapshot '\(snap.name)'. This overwrites the current state. Continue?")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.t("Restaurer", "Restore"))
        alert.addButton(withTitle: L.t("Annuler", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setLoading(true, status: L.t("Restauration en cours…", "Restoring…"))
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
        alert.messageText = L.t("Supprimer le snapshot", "Delete the snapshot")
        alert.informativeText = L.t("'\(snap.name)' sera supprimé définitivement.", "'\(snap.name)' will be permanently deleted.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.t("Supprimer", "Delete"))
        alert.addButton(withTitle: L.t("Annuler", "Cancel"))
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
        alert.messageText = L.t("Erreur", "Error")
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
        Theme.style(lbl, color: Theme.Tokens.text2)
        switch tableColumn?.identifier.rawValue {
        case "name":
            lbl.stringValue = snap.name
            Theme.style(lbl, color: Theme.Tokens.text, font: .systemFont(ofSize: 12, weight: .medium))
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
