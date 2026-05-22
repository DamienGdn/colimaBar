// Sources/ColimaBar/VolumeBrowserViewController.swift
import AppKit
import ColimaBarCore

final class VolumeBrowserViewController: NSViewController {
    private let execService = DockerExecService()

    // UI
    private let containerPicker = NSPopUpButton()
    private let backButton = NSButton(title: "←", target: nil, action: nil)
    private let pathLabel = NSTextField(labelWithString: "/")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let downloadButton = NSButton(title: "Download", target: nil, action: nil)
    private let uploadButton = NSButton(title: "Upload", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "Aucun conteneur en cours d'exécution")

    // State
    private var containers: [DockerContainer] = []
    private var pathStack: [String] = ["/"]
    private var entries: [FileEntry] = []

    private var currentContainer: DockerContainer? {
        let idx = containerPicker.indexOfSelectedItem
        guard idx >= 0 && idx < containers.count else { return nil }
        return containers[idx]
    }
    private var currentPath: String { pathStack.last ?? "/" }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    // MARK: - Public

    func updateContainers(_ all: [DockerContainer]) {
        containers = all.filter { $0.isRunning }
        let names = containers.map { $0.name }
        containerPicker.removeAllItems()
        containerPicker.addItems(withTitles: names.isEmpty ? ["—"] : names)
        emptyLabel.isHidden = !containers.isEmpty
        scrollView.isHidden = containers.isEmpty
        downloadButton.isEnabled = !containers.isEmpty
        uploadButton.isEnabled = !containers.isEmpty
        if !containers.isEmpty { reload() }
    }

    // MARK: - Private

    private func buildUI() {
        containerPicker.target = self
        containerPicker.action = #selector(containerChanged)
        containerPicker.translatesAutoresizingMaskIntoConstraints = false

        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.bezelStyle = .rounded
        backButton.isEnabled = false
        backButton.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        // Table
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Name"; nameCol.width = 280
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Size"; sizeCol.width = 80
        let permCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("perm"))
        permCol.title = "Permissions"; permCol.width = 120
        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(sizeCol)
        tableView.addTableColumn(permCol)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.target = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        downloadButton.bezelStyle = .rounded
        downloadButton.target = self
        downloadButton.action = #selector(downloadFile)
        downloadButton.isEnabled = false
        downloadButton.translatesAutoresizingMaskIntoConstraints = false

        uploadButton.bezelStyle = .rounded
        uploadButton.target = self
        uploadButton.action = #selector(uploadFile)
        uploadButton.isEnabled = false
        uploadButton.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let subviews: [NSView] = [containerPicker, backButton, pathLabel, scrollView, downloadButton, uploadButton, emptyLabel]
        for sub in subviews {
            view.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            containerPicker.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            containerPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            containerPicker.widthAnchor.constraint(equalToConstant: 200),

            backButton.centerYAnchor.constraint(equalTo: containerPicker.centerYAnchor),
            backButton.leadingAnchor.constraint(equalTo: containerPicker.trailingAnchor, constant: 8),
            backButton.widthAnchor.constraint(equalToConstant: 30),

            pathLabel.centerYAnchor.constraint(equalTo: containerPicker.centerYAnchor),
            pathLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: containerPicker.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: downloadButton.topAnchor, constant: -8),

            downloadButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            downloadButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            downloadButton.widthAnchor.constraint(equalToConstant: 100),

            uploadButton.centerYAnchor.constraint(equalTo: downloadButton.centerYAnchor),
            uploadButton.leadingAnchor.constraint(equalTo: downloadButton.trailingAnchor, constant: 8),
            uploadButton.widthAnchor.constraint(equalToConstant: 100),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func reload() {
        guard let container = currentContainer else { return }
        DispatchQueue.global().async {
            let result = try? self.execService.listFiles(container: container, path: self.currentPath)
            DispatchQueue.main.async {
                self.entries = result ?? []
                self.tableView.reloadData()
                self.pathLabel.stringValue = self.currentPath
                self.backButton.isEnabled = self.pathStack.count > 1
            }
        }
    }

    @objc private func containerChanged() { pathStack = ["/"]; reload() }

    @objc private func goBack() {
        guard pathStack.count > 1 else { return }
        pathStack.removeLast()
        reload()
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < entries.count else { return }
        let entry = entries[row]
        guard entry.isDirectory else { return }
        pathStack.append(currentPath == "/" ? "/\(entry.name)" : "\(currentPath)/\(entry.name)")
        reload()
    }

    @objc private func downloadFile() {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count, let container = currentContainer else { return }
        let entry = entries[row]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let remotePath = currentPath == "/" ? "/\(entry.name)" : "\(currentPath)/\(entry.name)"
        DispatchQueue.global().async {
            try? self.execService.copyFromContainer(container: container, remotePath: remotePath, localURL: url)
        }
    }

    @objc private func uploadFile() {
        guard let container = currentContainer else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let remotePath = currentPath == "/" ? "/\(url.lastPathComponent)" : "\(currentPath)/\(url.lastPathComponent)"
        DispatchQueue.global().async {
            try? self.execService.copyToContainer(container: container, localURL: url, remotePath: remotePath)
        }
    }
}

extension VolumeBrowserViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
}

extension VolumeBrowserViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let cell = NSTableCellView()
        let lbl = NSTextField(labelWithString: "")
        lbl.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            lbl.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            lbl.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        ])
        switch tableColumn?.identifier.rawValue {
        case "name":
            let icon = entry.isDirectory ? "📁 " : "📄 "
            lbl.stringValue = icon + entry.name
        case "size":
            lbl.stringValue = entry.isDirectory ? "—" : entry.size
        case "perm":
            lbl.stringValue = entry.permissions
            lbl.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        default: break
        }
        return cell
    }
}
