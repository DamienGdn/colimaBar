import AppKit
import ColimaBarCore

final class ContainersPanelViewController: NSViewController {

    // MARK: - Callbacks

    var onStart:      ((String) -> Void)?
    var onStop:       ((String) -> Void)?
    var onRestart:    ((String) -> Void)?
    var onLogs:       ((String) -> Void)?
    var onShell:      ((String) -> Void)?
    var onFetchImages: ((@escaping ([DockerImage]) -> Void) -> Void)?
    var onDeleteImage: ((String, @escaping (Result<Void, Error>) -> Void) -> Void)?
    var onPullImage:   ((String, @escaping (Result<Void, Error>) -> Void) -> Void)?
    var onFetchVolumes: ((@escaping ([DockerVolume]) -> Void) -> Void)?
    var onPruneVolumes: ((@escaping (Result<String, Error>) -> Void) -> Void)?

    // MARK: - Tab

    private var tabControl:            NSSegmentedControl!
    private var containersContentView: NSView!
    private var imagesContentView:     NSView!
    private var volumesContentView:    NSView!

    // MARK: - Containers tab

    private var statsLabel:       NSTextField!
    private var searchField:      NSSearchField!
    private var filterControl:    NSSegmentedControl!
    private var scrollView:       NSScrollView!
    private var tableView:        NSTableView!
    private var startBtn:         NSButton!
    private var stopBtn:          NSButton!
    private var restartBtn:       NSButton!
    private var logsBtn:          NSButton!
    private var shellBtn:         NSButton!

    // Sparkline zone
    private var sparklineZone:                NSView!
    private var sparklineNameLbl:             NSTextField!
    private var cpuSparkline:                 SparklineView!
    private var cpuValueLbl:                  NSTextField!
    private var ramSparkline:                 SparklineView!
    private var ramValueLbl:                  NSTextField!
    private var sparklineZoneHeightConstraint: NSLayoutConstraint!

    private var allContainers:   [DockerContainer] = []
    private var displayed:       [DockerContainer] = []
    private var usage:           ResourceUsage?
    private var containerStats:  [String: ResourceUsage] = [:]
    private var searchText       = ""
    private var currentSortDesc: NSSortDescriptor? = nil

    private var cpuHistory: [String: [Double]] = [:]
    private var ramHistory: [String: [Double]] = [:]
    private let historyLimit = 20

    // MARK: - Images tab

    private var imagesTableView:   NSTableView!
    private var imagesScrollView:  NSScrollView!
    private var pullField:         NSTextField!
    private var pullBtn:           NSButton!
    private var deleteImageBtn:    NSButton!
    private var imageStatusLbl:    NSTextField!
    private var pullSpinner:       NSProgressIndicator!
    private var allImages:         [DockerImage] = []

    // MARK: - Volumes tab

    private var volumesTableView:  NSTableView!
    private var volumesScrollView: NSScrollView!
    private var pruneVolumesBtn:   NSButton!
    private var volumeStatusLbl:   NSTextField!
    private var allVolumes:        [DockerVolume] = []

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        applyFilter()
    }

    func update(containers: [DockerContainer], usage: ResourceUsage?,
                containerStats: [String: ResourceUsage] = [:]) {
        updateHistoryBuffers(containers: containers, stats: containerStats)
        allContainers       = containers
        self.usage          = usage
        self.containerStats = containerStats
        guard isViewLoaded else { return }
        applyFilter()
        refreshStats()
    }

    // MARK: - Build UI

    private func buildUI() {
        // Tab control
        tabControl = NSSegmentedControl(
            labels: [L.t("Containers", "Containers"),
                     L.t("Images", "Images"),
                     L.t("Volumes", "Volumes")],
            trackingMode: .selectOne,
            target: self, action: #selector(tabChanged))
        tabControl.selectedSegment = 0
        tabControl.controlSize = .regular
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabControl)

        // Content areas
        containersContentView = NSView()
        containersContentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containersContentView)

        imagesContentView = NSView()
        imagesContentView.translatesAutoresizingMaskIntoConstraints = false
        imagesContentView.isHidden = true
        view.addSubview(imagesContentView)

        volumesContentView = NSView()
        volumesContentView.translatesAutoresizingMaskIntoConstraints = false
        volumesContentView.isHidden = true
        view.addSubview(volumesContentView)

        NSLayoutConstraint.activate([
            tabControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            tabControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            containersContentView.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 4),
            containersContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containersContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containersContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            imagesContentView.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 4),
            imagesContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imagesContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imagesContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            volumesContentView.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 4),
            volumesContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            volumesContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            volumesContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        buildContainersUI()
        buildImagesUI()
        buildVolumesUI()
    }

    @objc private func tabChanged() {
        containersContentView.isHidden = tabControl.selectedSegment != 0
        imagesContentView.isHidden     = tabControl.selectedSegment != 1
        volumesContentView.isHidden    = tabControl.selectedSegment != 2
        if tabControl.selectedSegment == 1 { refreshImages() }
        if tabControl.selectedSegment == 2 { refreshVolumes() }
    }

    // MARK: - Containers UI

    private func buildContainersUI() {
        // Row 1: stats + filter
        statsLabel = NSTextField(labelWithString: "")
        statsLabel.font      = .systemFont(ofSize: 11)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        containersContentView.addSubview(statsLabel)

        filterControl = NSSegmentedControl(
            labels: [L.t("Tous", "All"), L.t("Actifs", "Running")],
            trackingMode: .selectOne,
            target: self, action: #selector(filterChanged))
        filterControl.selectedSegment = ColimaConfig.showAllContainers ? 0 : 1
        filterControl.controlSize     = .small
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        containersContentView.addSubview(filterControl)

        // Row 2: search
        searchField = NSSearchField()
        searchField.placeholderString = L.t("Rechercher un container…", "Search containers…")
        searchField.controlSize       = .small
        searchField.target            = self
        searchField.action            = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        containersContentView.addSubview(searchField)

        // Table
        tableView = NSTableView()
        tableView.style      = .plain
        tableView.rowHeight  = 22
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()

        for (id, title, width) in [
            ("state",  "",                               22.0),
            ("health", "",                               22.0),
            ("name",   L.t("Nom", "Name"),             160.0),
            ("image",  L.t("Image", "Image"),           150.0),
            ("status", L.t("Statut", "Status"),          90.0),
            ("ports",  L.t("Ports", "Ports"),           100.0),
            ("cpu",    "CPU %",                          65.0),
            ("ram",    "RAM",                           130.0),
        ] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title    = title
            col.width    = width
            col.minWidth = 20
            switch id {
            case "name":  col.sortDescriptorPrototype = NSSortDescriptor(key: "name",  ascending: true)
            case "ports": col.sortDescriptorPrototype = NSSortDescriptor(key: "ports", ascending: true)
            case "cpu":   col.sortDescriptorPrototype = NSSortDescriptor(key: "cpu",   ascending: false)
            case "ram":   col.sortDescriptorPrototype = NSSortDescriptor(key: "ram",   ascending: false)
            default: break
            }
            tableView.addTableColumn(col)
        }

        scrollView = NSScrollView()
        scrollView.documentView          = tableView
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.borderType            = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containersContentView.addSubview(scrollView)

        // Sparkline zone
        sparklineZone = NSView()
        sparklineZone.translatesAutoresizingMaskIntoConstraints = false
        containersContentView.addSubview(sparklineZone)

        sparklineNameLbl = NSTextField(labelWithString: "")
        sparklineNameLbl.font      = .boldSystemFont(ofSize: 12)
        sparklineNameLbl.textColor = .labelColor
        sparklineNameLbl.translatesAutoresizingMaskIntoConstraints = false
        sparklineZone.addSubview(sparklineNameLbl)

        cpuSparkline = SparklineView()
        cpuSparkline.color = .systemGreen
        cpuSparkline.translatesAutoresizingMaskIntoConstraints = false
        sparklineZone.addSubview(cpuSparkline)

        cpuValueLbl = NSTextField(labelWithString: "")
        cpuValueLbl.font      = .systemFont(ofSize: 11)
        cpuValueLbl.textColor = .secondaryLabelColor
        cpuValueLbl.alignment = .right
        cpuValueLbl.translatesAutoresizingMaskIntoConstraints = false
        sparklineZone.addSubview(cpuValueLbl)

        ramSparkline = SparklineView()
        ramSparkline.color = .systemBlue
        ramSparkline.translatesAutoresizingMaskIntoConstraints = false
        sparklineZone.addSubview(ramSparkline)

        ramValueLbl = NSTextField(labelWithString: "")
        ramValueLbl.font      = .systemFont(ofSize: 11)
        ramValueLbl.textColor = .secondaryLabelColor
        ramValueLbl.alignment = .right
        ramValueLbl.translatesAutoresizingMaskIntoConstraints = false
        sparklineZone.addSubview(ramValueLbl)

        NSLayoutConstraint.activate([
            sparklineNameLbl.topAnchor.constraint(equalTo: sparklineZone.topAnchor, constant: 4),
            sparklineNameLbl.leadingAnchor.constraint(equalTo: sparklineZone.leadingAnchor, constant: 12),
            sparklineNameLbl.trailingAnchor.constraint(lessThanOrEqualTo: sparklineZone.trailingAnchor, constant: -12),

            cpuSparkline.topAnchor.constraint(equalTo: sparklineNameLbl.bottomAnchor, constant: 2),
            cpuSparkline.leadingAnchor.constraint(equalTo: sparklineZone.leadingAnchor, constant: 12),
            cpuSparkline.trailingAnchor.constraint(equalTo: cpuValueLbl.leadingAnchor, constant: -8),
            cpuSparkline.heightAnchor.constraint(equalToConstant: 24),

            cpuValueLbl.centerYAnchor.constraint(equalTo: cpuSparkline.centerYAnchor),
            cpuValueLbl.trailingAnchor.constraint(equalTo: sparklineZone.trailingAnchor, constant: -12),
            cpuValueLbl.widthAnchor.constraint(equalToConstant: 90),

            ramSparkline.topAnchor.constraint(equalTo: cpuSparkline.bottomAnchor, constant: 4),
            ramSparkline.leadingAnchor.constraint(equalTo: sparklineZone.leadingAnchor, constant: 12),
            ramSparkline.trailingAnchor.constraint(equalTo: ramValueLbl.leadingAnchor, constant: -8),
            ramSparkline.heightAnchor.constraint(equalToConstant: 24),

            ramValueLbl.centerYAnchor.constraint(equalTo: ramSparkline.centerYAnchor),
            ramValueLbl.trailingAnchor.constraint(equalTo: sparklineZone.trailingAnchor, constant: -12),
            ramValueLbl.widthAnchor.constraint(equalToConstant: 90),
        ])

        // Action buttons
        startBtn   = makeBtn(L.t("▶ Démarrer", "▶ Start"),   #selector(startAction))
        stopBtn    = makeBtn(L.t("■ Arrêter",  "■ Stop"),     #selector(stopAction))
        restartBtn = makeBtn(L.t("↺ Restart",  "↺ Restart"), #selector(restartAction))
        logsBtn    = makeBtn(L.t("Logs", "Logs"),             #selector(logsAction))
        shellBtn   = makeBtn(L.t("Shell", "Shell"),           #selector(shellAction))

        let btnStack = NSStackView(views: [startBtn, stopBtn, restartBtn, logsBtn, shellBtn])
        btnStack.orientation  = .horizontal
        btnStack.spacing      = 5
        btnStack.distribution = .fillEqually
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        containersContentView.addSubview(btnStack)

        sparklineZoneHeightConstraint = sparklineZone.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            statsLabel.topAnchor.constraint(equalTo: containersContentView.topAnchor, constant: 10),
            statsLabel.leadingAnchor.constraint(equalTo: containersContentView.leadingAnchor, constant: 12),
            statsLabel.trailingAnchor.constraint(lessThanOrEqualTo: filterControl.leadingAnchor, constant: -8),
            statsLabel.centerYAnchor.constraint(equalTo: filterControl.centerYAnchor),
            filterControl.topAnchor.constraint(equalTo: containersContentView.topAnchor, constant: 8),
            filterControl.trailingAnchor.constraint(equalTo: containersContentView.trailingAnchor, constant: -12),

            searchField.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: containersContentView.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: containersContentView.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: containersContentView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: containersContentView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: sparklineZone.topAnchor, constant: -4),

            sparklineZone.leadingAnchor.constraint(equalTo: containersContentView.leadingAnchor),
            sparklineZone.trailingAnchor.constraint(equalTo: containersContentView.trailingAnchor),
            sparklineZone.bottomAnchor.constraint(equalTo: btnStack.topAnchor, constant: -4),
            sparklineZoneHeightConstraint,

            btnStack.leadingAnchor.constraint(equalTo: containersContentView.leadingAnchor, constant: 8),
            btnStack.trailingAnchor.constraint(equalTo: containersContentView.trailingAnchor, constant: -8),
            btnStack.bottomAnchor.constraint(equalTo: containersContentView.bottomAnchor, constant: -10),
            btnStack.heightAnchor.constraint(equalToConstant: 24),
        ])

        refreshStats()
        updateButtons()
    }

    // MARK: - Images UI

    private func buildImagesUI() {
        imagesTableView = NSTableView()
        imagesTableView.style      = .plain
        imagesTableView.rowHeight  = 22
        imagesTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        imagesTableView.delegate   = self
        imagesTableView.dataSource = self
        imagesTableView.headerView = NSTableHeaderView()

        for (id, title, width) in [
            ("repo",    L.t("Dépôt", "Repository"), 220.0),
            ("tag",     "Tag",                        80.0),
            ("imgsize", L.t("Taille", "Size"),        80.0),
            ("created", L.t("Créée", "Created"),     120.0),
        ] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title; col.width = width; col.minWidth = 20
            if id == "repo"    { col.sortDescriptorPrototype = NSSortDescriptor(key: "repo",    ascending: true) }
            if id == "imgsize" { col.sortDescriptorPrototype = NSSortDescriptor(key: "imgsize", ascending: false) }
            imagesTableView.addTableColumn(col)
        }

        imagesScrollView = NSScrollView()
        imagesScrollView.documentView          = imagesTableView
        imagesScrollView.hasVerticalScroller   = true
        imagesScrollView.hasHorizontalScroller = false
        imagesScrollView.autohidesScrollers    = true
        imagesScrollView.borderType            = .bezelBorder
        imagesScrollView.translatesAutoresizingMaskIntoConstraints = false
        imagesContentView.addSubview(imagesScrollView)

        pullField = NSTextField()
        pullField.placeholderString = "nginx:latest"
        pullField.controlSize       = .small

        pullBtn        = makeBtn(L.t("Pull", "Pull"),           #selector(pullAction))
        deleteImageBtn = makeBtn(L.t("Supprimer", "Delete"),    #selector(deleteImageAction))
        deleteImageBtn.isEnabled = false

        pullSpinner = NSProgressIndicator()
        pullSpinner.style       = .spinning
        pullSpinner.controlSize = .small
        pullSpinner.isHidden    = true
        pullSpinner.translatesAutoresizingMaskIntoConstraints = false
        imagesContentView.addSubview(pullSpinner)

        imageStatusLbl = NSTextField(labelWithString: "")
        imageStatusLbl.font          = .systemFont(ofSize: 11)
        imageStatusLbl.textColor     = .secondaryLabelColor
        imageStatusLbl.lineBreakMode = .byTruncatingTail
        imageStatusLbl.translatesAutoresizingMaskIntoConstraints = false
        imagesContentView.addSubview(imageStatusLbl)

        let imgBtnStack = NSStackView(views: [pullField, pullBtn, deleteImageBtn])
        imgBtnStack.orientation  = .horizontal
        imgBtnStack.spacing      = 6
        imgBtnStack.translatesAutoresizingMaskIntoConstraints = false
        imagesContentView.addSubview(imgBtnStack)

        NSLayoutConstraint.activate([
            imagesScrollView.topAnchor.constraint(equalTo: imagesContentView.topAnchor, constant: 6),
            imagesScrollView.leadingAnchor.constraint(equalTo: imagesContentView.leadingAnchor, constant: 8),
            imagesScrollView.trailingAnchor.constraint(equalTo: imagesContentView.trailingAnchor, constant: -8),
            imagesScrollView.bottomAnchor.constraint(equalTo: imgBtnStack.topAnchor, constant: -6),

            imgBtnStack.leadingAnchor.constraint(equalTo: imagesContentView.leadingAnchor, constant: 8),
            imgBtnStack.trailingAnchor.constraint(lessThanOrEqualTo: pullSpinner.leadingAnchor, constant: -6),
            imgBtnStack.bottomAnchor.constraint(equalTo: imageStatusLbl.topAnchor, constant: -4),
            imgBtnStack.heightAnchor.constraint(equalToConstant: 24),
            pullField.widthAnchor.constraint(equalToConstant: 160),

            pullSpinner.centerYAnchor.constraint(equalTo: imgBtnStack.centerYAnchor),
            pullSpinner.trailingAnchor.constraint(equalTo: imagesContentView.trailingAnchor, constant: -12),

            imageStatusLbl.leadingAnchor.constraint(equalTo: imagesContentView.leadingAnchor, constant: 12),
            imageStatusLbl.trailingAnchor.constraint(equalTo: imagesContentView.trailingAnchor, constant: -12),
            imageStatusLbl.bottomAnchor.constraint(equalTo: imagesContentView.bottomAnchor, constant: -10),
            imageStatusLbl.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    // MARK: - Volumes UI

    private func buildVolumesUI() {
        volumesTableView = NSTableView()
        volumesTableView.style      = .plain
        volumesTableView.rowHeight  = 22
        volumesTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        volumesTableView.delegate   = self
        volumesTableView.dataSource = self
        volumesTableView.headerView = NSTableHeaderView()

        for (id, title, width) in [
            ("volname",   L.t("Nom", "Name"),     300.0),
            ("voldriver", L.t("Driver", "Driver"),  90.0),
            ("volsize",   L.t("Taille", "Size"),    90.0),
        ] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title; col.width = width; col.minWidth = 20
            volumesTableView.addTableColumn(col)
        }

        volumesScrollView = NSScrollView()
        volumesScrollView.documentView          = volumesTableView
        volumesScrollView.hasVerticalScroller   = true
        volumesScrollView.hasHorizontalScroller = false
        volumesScrollView.autohidesScrollers    = true
        volumesScrollView.borderType            = .bezelBorder
        volumesScrollView.translatesAutoresizingMaskIntoConstraints = false
        volumesContentView.addSubview(volumesScrollView)

        pruneVolumesBtn = makeBtn(L.t("🗑 Vider les volumes…", "🗑 Prune volumes…"),
                                  #selector(pruneVolumesAction))
        pruneVolumesBtn.translatesAutoresizingMaskIntoConstraints = false
        volumesContentView.addSubview(pruneVolumesBtn)

        volumeStatusLbl = NSTextField(labelWithString: "")
        volumeStatusLbl.font          = .systemFont(ofSize: 11)
        volumeStatusLbl.textColor     = .secondaryLabelColor
        volumeStatusLbl.lineBreakMode = .byTruncatingTail
        volumeStatusLbl.translatesAutoresizingMaskIntoConstraints = false
        volumesContentView.addSubview(volumeStatusLbl)

        NSLayoutConstraint.activate([
            volumesScrollView.topAnchor.constraint(equalTo: volumesContentView.topAnchor, constant: 6),
            volumesScrollView.leadingAnchor.constraint(equalTo: volumesContentView.leadingAnchor, constant: 8),
            volumesScrollView.trailingAnchor.constraint(equalTo: volumesContentView.trailingAnchor, constant: -8),
            volumesScrollView.bottomAnchor.constraint(equalTo: pruneVolumesBtn.topAnchor, constant: -6),

            pruneVolumesBtn.leadingAnchor.constraint(equalTo: volumesContentView.leadingAnchor, constant: 8),
            pruneVolumesBtn.bottomAnchor.constraint(equalTo: volumeStatusLbl.topAnchor, constant: -4),

            volumeStatusLbl.leadingAnchor.constraint(equalTo: volumesContentView.leadingAnchor, constant: 12),
            volumeStatusLbl.trailingAnchor.constraint(equalTo: volumesContentView.trailingAnchor, constant: -12),
            volumeStatusLbl.bottomAnchor.constraint(equalTo: volumesContentView.bottomAnchor, constant: -10),
            volumeStatusLbl.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func makeBtn(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle  = .rounded
        b.controlSize = .small
        return b
    }

    // MARK: - Containers data

    private func applyFilter() {
        let selectedName = selected()?.name
        let base = ColimaConfig.showAllContainers ? allContainers : allContainers.filter { $0.isRunning }
        displayed = searchText.isEmpty
            ? base
            : base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        if let sd = currentSortDesc { sortDisplayed(by: sd) }
        tableView?.reloadData()
        if let name = selectedName,
           let idx = displayed.firstIndex(where: { $0.name == name }) {
            tableView?.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
        updateButtons()
        refreshSparklines()
    }

    private func sortDisplayed(by sd: NSSortDescriptor) {
        displayed.sort { a, b in
            let asc = sd.ascending
            switch sd.key {
            case "name":  return asc ? a.name < b.name : a.name > b.name
            case "ports": return asc ? a.hostPorts < b.hostPorts : a.hostPorts > b.hostPorts
            case "cpu":
                let ca = containerStats[a.name]?.cpuPercent ?? 0
                let cb = containerStats[b.name]?.cpuPercent ?? 0
                return asc ? ca < cb : ca > cb
            case "ram":
                let ra = containerStats[a.name]?.memUsedMiB ?? 0
                let rb = containerStats[b.name]?.memUsedMiB ?? 0
                return asc ? ra < rb : ra > rb
            default: return false
            }
        }
    }

    private func refreshStats() {
        if let u = usage {
            statsLabel.stringValue = String(
                format: "CPU %.1f%%  RAM %@ / %.1f GB (%.0f%%)",
                u.cpuPercent, u.memUsedFormatted, u.memTotalGiB, u.memUsedPercent)
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

    // MARK: - Sparklines

    private func updateHistoryBuffers(containers: [DockerContainer],
                                      stats: [String: ResourceUsage]) {
        for c in containers where c.isRunning {
            guard let s = stats[c.name] else { continue }
            var cpuBuf = cpuHistory[c.name, default: []]
            cpuBuf.append(s.cpuPercent)
            if cpuBuf.count > historyLimit { cpuBuf.removeFirst(cpuBuf.count - historyLimit) }
            cpuHistory[c.name] = cpuBuf

            var ramBuf = ramHistory[c.name, default: []]
            ramBuf.append(s.memUsedMiB)
            if ramBuf.count > historyLimit { ramBuf.removeFirst(ramBuf.count - historyLimit) }
            ramHistory[c.name] = ramBuf
        }
        let names = Set(containers.map { $0.name })
        cpuHistory = cpuHistory.filter { names.contains($0.key) }
        ramHistory = ramHistory.filter { names.contains($0.key) }
    }

    private func refreshSparklines() {
        guard isViewLoaded, let zone = sparklineZone else { return }
        guard let c = selected(), c.isRunning else {
            sparklineZoneHeightConstraint.constant = 0
            zone.isHidden = true
            return
        }
        zone.isHidden = false
        sparklineZoneHeightConstraint.constant = 80
        sparklineNameLbl.stringValue = c.name
        cpuSparkline.values = cpuHistory[c.name] ?? []
        ramSparkline.values = ramHistory[c.name] ?? []
        if let s = containerStats[c.name] {
            cpuValueLbl.stringValue = String(format: "CPU %.1f%%", s.cpuPercent)
            ramValueLbl.stringValue = "RAM \(s.memUsedFormatted)"
        } else {
            cpuValueLbl.stringValue = "CPU …"
            ramValueLbl.stringValue = "RAM …"
        }
    }

    // MARK: - Images data

    private func refreshImages() {
        imageStatusLbl?.stringValue = L.t("Chargement…", "Loading…")
        onFetchImages? { [weak self] images in
            self?.allImages = images
            self?.imagesTableView?.reloadData()
            self?.imageStatusLbl?.stringValue = ""
            self?.deleteImageBtn?.isEnabled = false
        }
    }

    // MARK: - Volumes data

    private func refreshVolumes() {
        volumeStatusLbl?.stringValue = L.t("Chargement…", "Loading…")
        onFetchVolumes? { [weak self] volumes in
            self?.allVolumes = volumes
            self?.volumesTableView?.reloadData()
            self?.volumeStatusLbl?.stringValue = ""
        }
    }

    // MARK: - Containers actions

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

    // MARK: - Images actions

    @objc private func pullAction() {
        let name = pullField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard let onPullImage else {
            return
        }
        pullBtn.isEnabled = false
        pullSpinner.isHidden = false
        pullSpinner.startAnimation(nil)
        imageStatusLbl.stringValue = L.t("Pull en cours…", "Pulling…")
        onPullImage(name) { [weak self] result in
            self?.pullBtn.isEnabled = true
            self?.pullSpinner.stopAnimation(nil)
            self?.pullSpinner.isHidden = true
            switch result {
            case .success:
                self?.imageStatusLbl.stringValue = L.t("✓ Pull terminé", "✓ Pull complete")
                self?.pullField.stringValue = ""
                self?.refreshImages()
            case .failure(let e):
                self?.imageStatusLbl.stringValue = "✗ \(e.localizedDescription)"
            }
        }
    }

    @objc private func deleteImageAction() {
        let row = imagesTableView.selectedRow
        guard row >= 0 && row < allImages.count else { return }
        let img = allImages[row]

        let alert = NSAlert()
        alert.messageText     = L.t("Supprimer l'image", "Delete image")
        alert.informativeText = "\(img.repository):\(img.tag)"
        alert.alertStyle      = .warning
        alert.addButton(withTitle: L.t("Supprimer", "Delete"))
        alert.addButton(withTitle: L.t("Annuler", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        deleteImageBtn.isEnabled = false
        onDeleteImage?(img.id) { [weak self] result in
            switch result {
            case .success:
                self?.imageStatusLbl.stringValue = L.t("✓ Image supprimée", "✓ Image deleted")
                self?.refreshImages()
            case .failure(let e):
                self?.imageStatusLbl.stringValue = "✗ \(e.localizedDescription)"
                self?.deleteImageBtn.isEnabled = true
            }
        }
    }

    // MARK: - Volumes actions

    @objc private func pruneVolumesAction() {
        let alert = NSAlert()
        alert.messageText     = L.t("Vider les volumes", "Prune volumes")
        alert.informativeText = L.t(
            "Supprime tous les volumes non utilisés. Irréversible.",
            "Removes all unused volumes. Cannot be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.t("Vider", "Prune"))
        alert.addButton(withTitle: L.t("Annuler", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        pruneVolumesBtn.isEnabled = false
        onPruneVolumes? { [weak self] result in
            self?.pruneVolumesBtn.isEnabled = true
            switch result {
            case .success(let output):
                let lines = output.components(separatedBy: .newlines).filter { $0.hasPrefix("Total") }
                self?.volumeStatusLbl.stringValue = lines.first ?? L.t("✓ Volumes purgés", "✓ Volumes pruned")
                self?.refreshVolumes()
            case .failure(let e):
                self?.volumeStatusLbl.stringValue = "✗ \(e.localizedDescription)"
            }
        }
    }
}

// MARK: - Row view

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

// MARK: - PortsCell

final class PortsCell: NSTableCellView {
    private var stack = NSStackView()
    private var ports: [Int] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.orientation  = .horizontal
        stack.spacing      = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(portNumbers: [Int]) {
        ports = portNumbers
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard !portNumbers.isEmpty else {
            let lbl = NSTextField(labelWithString: "–")
            lbl.font      = .systemFont(ofSize: 12)
            lbl.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(lbl)
            return
        }
        for (i, port) in portNumbers.enumerated() {
            let btn = NSButton()
            btn.isBordered    = false
            btn.bezelStyle    = .rounded
            btn.tag           = i
            btn.target        = self
            btn.action        = #selector(portTapped(_:))
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.controlAccentColor,
                .font:            NSFont.systemFont(ofSize: 12),
                .underlineStyle:  NSUnderlineStyle.single.rawValue,
            ]
            btn.attributedTitle = NSAttributedString(string: "\(port)", attributes: attrs)
            stack.addArrangedSubview(btn)
        }
    }

    @objc private func portTapped(_ sender: NSButton) {
        guard sender.tag < ports.count else { return }
        let port = ports[sender.tag]
        NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!)
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension ContainersPanelViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == self.tableView    { return displayed.count }
        if tableView == imagesTableView   { return allImages.count }
        if tableView == volumesTableView  { return allVolumes.count }
        return 0
    }

    func tableView(_ tableView: NSTableView,
                   rowViewForRow row: Int) -> NSTableRowView? {
        guard tableView == self.tableView else { return nil }
        let rv = ContainerRowView()
        rv.isRunning = row < displayed.count && displayed[row].isRunning
        return rv
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? ""

        // Images table
        if tableView == imagesTableView {
            let cid = NSUserInterfaceItemIdentifier("img-\(id)")
            let cell = (tableView.makeView(withIdentifier: cid, owner: self) as? NSTableCellView)
                ?? makeTextCell(id: cid)
            guard row < allImages.count else { return cell }
            let img = allImages[row]
            switch id {
            case "repo":    cell.textField?.stringValue = img.repository
            case "tag":     cell.textField?.stringValue = img.tag
            case "imgsize": cell.textField?.stringValue = img.size
            case "created": cell.textField?.stringValue = img.created
            default: break
            }
            cell.textField?.textColor = .labelColor
            return cell
        }

        // Volumes table
        if tableView == volumesTableView {
            let cid = NSUserInterfaceItemIdentifier("vol-\(id)")
            let cell = (tableView.makeView(withIdentifier: cid, owner: self) as? NSTableCellView)
                ?? makeTextCell(id: cid)
            guard row < allVolumes.count else { return cell }
            let vol = allVolumes[row]
            switch id {
            case "volname":   cell.textField?.stringValue = vol.name
            case "voldriver": cell.textField?.stringValue = vol.driver
            case "volsize":   cell.textField?.stringValue = vol.size
            default: break
            }
            cell.textField?.textColor = .secondaryLabelColor
            return cell
        }

        // Containers table
        guard row < displayed.count else { return nil }
        let c = displayed[row]

        if id == "ports" {
            let portsCid = NSUserInterfaceItemIdentifier("cell-ports")
            let portsCell = (tableView.makeView(withIdentifier: portsCid, owner: self) as? PortsCell)
                ?? PortsCell()
            portsCell.identifier = portsCid
            portsCell.configure(portNumbers: c.hostPortNumbers)
            return portsCell
        }

        let cid  = NSUserInterfaceItemIdentifier("cell-\(id)")
        let cell = (tableView.makeView(withIdentifier: cid, owner: self) as? NSTableCellView)
            ?? makeTextCell(id: cid)

        switch id {
        case "state":
            cell.textField?.stringValue = c.isRunning ? "▶" : "■"
            cell.textField?.textColor   = c.isRunning ? .systemGreen : .tertiaryLabelColor
        case "health":
            switch c.health {
            case .healthy:   cell.textField?.stringValue = "●"; cell.textField?.textColor = .systemGreen
            case .unhealthy: cell.textField?.stringValue = "●"; cell.textField?.textColor = .systemRed
            case .starting:  cell.textField?.stringValue = "●"; cell.textField?.textColor = .systemYellow
            case nil:        cell.textField?.stringValue = ""; cell.textField?.textColor = .clear
            }
        case "name":
            cell.textField?.stringValue = c.name
            cell.textField?.textColor   = .labelColor
        case "image":
            cell.textField?.stringValue = c.image
            cell.textField?.textColor   = .secondaryLabelColor
        case "status":
            cell.textField?.stringValue = c.status
            cell.textField?.textColor   = .secondaryLabelColor
        case "cpu":
            if let s = containerStats[c.name], c.isRunning {
                cell.textField?.stringValue = String(format: "%.1f%%", s.cpuPercent)
                cell.textField?.textColor   = s.cpuPercent > 80 ? .systemOrange : .secondaryLabelColor
            } else {
                cell.textField?.stringValue = c.isRunning ? "…" : "–"
                cell.textField?.textColor   = .tertiaryLabelColor
            }
        case "ram":
            if let s = containerStats[c.name], c.isRunning {
                cell.textField?.stringValue = "\(s.memUsedFormatted) / \(String(format: "%.1f GB", s.memTotalGiB)) (\(String(format: "%.0f%%", s.memUsedPercent)))"
                cell.textField?.textColor   = .secondaryLabelColor
            } else {
                cell.textField?.stringValue = c.isRunning ? "…" : "–"
                cell.textField?.textColor   = .tertiaryLabelColor
            }
        default: break
        }
        return cell
    }

    private func makeTextCell(id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
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
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        if tv == tableView {
            updateButtons()
            refreshSparklines()
        }
        if tv == imagesTableView {
            deleteImageBtn?.isEnabled = imagesTableView.selectedRow >= 0
        }
    }

    func tableView(_ tableView: NSTableView,
                   sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard tableView == self.tableView,
              let sd = tableView.sortDescriptors.first else { return }
        currentSortDesc = sd
        sortDisplayed(by: sd)
        tableView.reloadData()
        updateButtons()
    }
}
