import AppKit
import ColimaBarCore

final class ContainersPanelViewController: NSViewController {

    var onStart:      ((String) -> Void)?
    var onStop:       ((String) -> Void)?
    var onRestart:    ((String) -> Void)?
    var onLogs:       ((String) -> Void)?
    var onShell:      ((String) -> Void)?
    var onFetchStats: ((String, @escaping (ResourceUsage?) -> Void) -> Void)?

    private var statsLabel:       NSTextField!
    private var searchField:      NSSearchField!
    private var filterControl:    NSSegmentedControl!
    private var scrollView:       NSScrollView!
    private var tableView:        NSTableView!
    private var containerStatLbl: NSTextField!
    private var startBtn:         NSButton!
    private var stopBtn:          NSButton!
    private var restartBtn:       NSButton!
    private var logsBtn:          NSButton!
    private var shellBtn:         NSButton!

    private var allContainers: [DockerContainer] = []
    private var displayed:     [DockerContainer] = []
    private var usage:         ResourceUsage?
    private var searchText     = ""

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        applyFilter()
    }

    func update(containers: [DockerContainer], usage: ResourceUsage?) {
        allContainers = containers
        self.usage    = usage
        guard isViewLoaded else { return }
        applyFilter()
        refreshStats()
    }

    // MARK: - UI

    private func buildUI() {
        // ── Row 1: stats + filter ──────────────────────────────────────
        statsLabel = NSTextField(labelWithString: "")
        statsLabel.font      = .systemFont(ofSize: 11)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsLabel)

        filterControl = NSSegmentedControl(
            labels: [L.t("Tous", "All"), L.t("Actifs", "Running")],
            trackingMode: .selectOne,
            target: self, action: #selector(filterChanged))
        filterControl.selectedSegment = ColimaConfig.showAllContainers ? 0 : 1
        filterControl.controlSize     = .small
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterControl)

        // ── Row 2: search ──────────────────────────────────────────────
        searchField = NSSearchField()
        searchField.placeholderString = L.t("Rechercher un container…", "Search containers…")
        searchField.controlSize       = .small
        searchField.target            = self
        searchField.action            = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)

        // ── Table ──────────────────────────────────────────────────────
        tableView = NSTableView()
        tableView.style      = .plain
        tableView.rowHeight  = 22
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()

        for (id, title, width) in [
            ("state",  "",                              22.0),
            ("name",   L.t("Nom", "Name"),             160.0),
            ("image",  L.t("Image", "Image"),          160.0),
            ("status", L.t("Statut", "Status"),        100.0),
            ("ports",  L.t("Ports", "Ports"),          130.0),
        ] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title    = title
            col.width    = width
            col.minWidth = 20
            tableView.addTableColumn(col)
        }

        scrollView = NSScrollView()
        scrollView.documentView          = tableView
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.borderType            = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // ── Per-container stats ────────────────────────────────────────
        containerStatLbl = NSTextField(labelWithString: "")
        containerStatLbl.font      = .systemFont(ofSize: 11)
        containerStatLbl.textColor = .secondaryLabelColor
        containerStatLbl.alignment = .right
        containerStatLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerStatLbl)

        // ── Action buttons ────────────────────────────────────────────
        startBtn   = makeBtn(L.t("▶ Démarrer", "▶ Start"),       #selector(startAction))
        stopBtn    = makeBtn(L.t("■ Arrêter",  "■ Stop"),         #selector(stopAction))
        restartBtn = makeBtn(L.t("↺ Restart",  "↺ Restart"),     #selector(restartAction))
        logsBtn    = makeBtn(L.t("Logs", "Logs"),                 #selector(logsAction))
        shellBtn   = makeBtn(L.t("Shell", "Shell"),               #selector(shellAction))

        let btnStack = NSStackView(views: [startBtn, stopBtn, restartBtn, logsBtn, shellBtn])
        btnStack.orientation  = .horizontal
        btnStack.spacing      = 5
        btnStack.distribution = .fillEqually
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btnStack)

        // ── Constraints ───────────────────────────────────────────────
        NSLayoutConstraint.activate([
            // row 1
            statsLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            statsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statsLabel.trailingAnchor.constraint(lessThanOrEqualTo: filterControl.leadingAnchor, constant: -8),
            statsLabel.centerYAnchor.constraint(equalTo: filterControl.centerYAnchor),
            filterControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            filterControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            // row 2
            searchField.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            // table
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: containerStatLbl.topAnchor, constant: -4),

            // per-container stats
            containerStatLbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            containerStatLbl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            containerStatLbl.bottomAnchor.constraint(equalTo: btnStack.topAnchor, constant: -4),
            containerStatLbl.heightAnchor.constraint(equalToConstant: 16),

            // buttons
            btnStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            btnStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            btnStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            btnStack.heightAnchor.constraint(equalToConstant: 24),
        ])

        refreshStats()
        updateButtons()
    }

    private func makeBtn(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle  = .rounded
        b.controlSize = .small
        return b
    }

    // MARK: - Data

    private func applyFilter() {
        let base = ColimaConfig.showAllContainers ? allContainers : allContainers.filter { $0.isRunning }
        displayed = searchText.isEmpty
            ? base
            : base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        tableView?.reloadData()
        updateButtons()
        containerStatLbl?.stringValue = ""
    }

    private func refreshStats() {
        if let u = usage {
            statsLabel.stringValue = String(
                format: "CPU %.1f%%  RAM %@ / %.1f GB",
                u.cpuPercent, u.memUsedFormatted, u.memTotalGiB)
        } else {
            let running = allContainers.filter { $0.isRunning }.count
            statsLabel.stringValue = "\(running)/\(allContainers.count) containers"
        }
    }

    private func updateButtons() {
        let row = tableView?.selectedRow ?? -1
        let c   = (row >= 0 && row < displayed.count) ? displayed[row] : nil
        startBtn.isEnabled   = c != nil && !c!.isRunning
        stopBtn.isEnabled    = c?.isRunning == true
        restartBtn.isEnabled = c?.isRunning == true
        logsBtn.isEnabled    = c != nil
        shellBtn.isEnabled   = c?.isRunning == true
    }

    private func selected() -> DockerContainer? {
        let r = tableView.selectedRow
        return (r >= 0 && r < displayed.count) ? displayed[r] : nil
    }

    private func fetchSelectedStats() {
        guard let c = selected(), c.isRunning else {
            containerStatLbl.stringValue = ""
            return
        }
        containerStatLbl.stringValue = "…"
        let name = c.name
        onFetchStats?(name) { [weak self] usage in
            guard let self, self.selected()?.name == name else { return }
            if let u = usage {
                self.containerStatLbl.stringValue = String(
                    format: "CPU %.1f%%  RAM %@", u.cpuPercent, u.memUsedFormatted)
            } else {
                self.containerStatLbl.stringValue = ""
            }
        }
    }

    // MARK: - Actions

    @objc private func filterChanged() {
        ColimaConfig.showAllContainers = filterControl.selectedSegment == 0
        applyFilter()
    }

    @objc private func searchChanged() {
        searchText = searchField.stringValue
        applyFilter()
    }

    @objc private func startAction()   { guard let c = selected() else { return }; onStart?(c.name) }
    @objc private func stopAction()    { guard let c = selected() else { return }; onStop?(c.name) }
    @objc private func restartAction() { guard let c = selected() else { return }; onRestart?(c.name) }
    @objc private func logsAction()    { guard let c = selected() else { return }; onLogs?(c.name) }
    @objc private func shellAction()   { guard let c = selected() else { return }; onShell?(c.name) }
}

// MARK: - Row view (colored background)

private final class ContainerRowView: NSTableRowView {
    var isRunning = false
    override func drawBackground(in dirtyRect: NSRect) {
        (isRunning
            ? NSColor.systemGreen.withAlphaComponent(0.08)
            : NSColor.clear
        ).setFill()
        dirtyRect.fill()
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension ContainersPanelViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { displayed.count }

    func tableView(_ tableView: NSTableView,
                   rowViewForRow row: Int) -> NSTableRowView? {
        let rv = ContainerRowView()
        rv.isRunning = row < displayed.count && displayed[row].isRunning
        return rv
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let id  = tableColumn?.identifier.rawValue ?? ""
        let c   = displayed[row]
        let cid = NSUserInterfaceItemIdentifier("cell-\(id)")

        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cid, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cid
            let tf = NSTextField(labelWithString: "")
            tf.font          = .systemFont(ofSize: 12)
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        switch id {
        case "state":
            cell.textField?.stringValue = c.isRunning ? "▶" : "■"
            cell.textField?.textColor   = c.isRunning ? .systemGreen : .tertiaryLabelColor
        case "name":
            cell.textField?.stringValue = c.name
            cell.textField?.textColor   = .labelColor
        case "image":
            cell.textField?.stringValue = c.image
            cell.textField?.textColor   = .secondaryLabelColor
        case "status":
            cell.textField?.stringValue = c.status
            cell.textField?.textColor   = .secondaryLabelColor
        case "ports":
            let p = c.hostPorts
            cell.textField?.stringValue = p
            cell.textField?.textColor   = p.isEmpty ? .tertiaryLabelColor : .secondaryLabelColor
        default: break
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        fetchSelectedStats()
    }
}
