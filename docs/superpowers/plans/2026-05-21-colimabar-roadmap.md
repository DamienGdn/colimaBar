# ColimaBar Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add health check column, clickable port URLs, CPU/RAM sparklines, image management tab, and volume management tab to ColimaBar's containers popover panel.

**Architecture:** Two-layer: `ColimaBarCore` (Foundation, testable — models + parsers + shell commands) and `ColimaBar` (AppKit UI). Core tasks come first, UI tasks follow. The containers panel gets a 3-tab bar (Containers / Images / Volumes); a `SparklineView` custom NSView stores/renders history.

**Tech Stack:** Swift 5.9, AppKit, Foundation, custom test runner (no XCTest), SPM, macOS 13+

---

## Task 1: DockerContainer — health check + host port numbers

**Files:**
- Modify: `Sources/ColimaBarCore/DockerContainer.swift`
- Modify: `Tests/ColimaBarTests/ColimaStateTests.swift`
- Modify: `Tests/ColimaBarTests/main.swift`

- [ ] **Step 1: Add `HealthStatus` enum and computed properties to `DockerContainer`**

In `Sources/ColimaBarCore/DockerContainer.swift`, replace the entire file with:

```swift
import Foundation

public struct DockerContainer: Equatable {
    public enum ContainerState: String, Equatable {
        case running, exited, paused, restarting, dead, created, removing
        case unknown
    }

    public enum HealthStatus: String, Equatable {
        case healthy, unhealthy, starting
    }

    public let id: String
    public let name: String
    public let state: ContainerState
    public let status: String
    public let image: String
    public let ports: String

    public var isRunning: Bool { state == .running }

    public var health: HealthStatus? {
        if status.contains("(healthy)")          { return .healthy }
        if status.contains("(unhealthy)")        { return .unhealthy }
        if status.contains("(health: starting)") { return .starting }
        return nil
    }

    // Extracts unique host port numbers: "0.0.0.0:8000->8000/tcp, :::9443->9443/tcp" → "8000, 9443"
    public var hostPorts: String {
        guard !ports.isEmpty else { return "" }
        var seen = Set<String>()
        let nums = ports.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { part -> String? in
                guard let arrow = part.range(of: "->"),
                      let colon = part[..<arrow.lowerBound].lastIndex(of: ":") else { return nil }
                return String(part[part.index(after: colon)..<arrow.lowerBound])
            }
            .filter { seen.insert($0).inserted }
        return nums.joined(separator: ", ")
    }

    // Extracts unique host port numbers as [Int]
    public var hostPortNumbers: [Int] {
        hostPorts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { Int($0) }
    }
}

struct DockerContainerJSON: Codable {
    let ID: String
    let Names: String
    let State: String
    let Status: String
    let Image: String
    let Ports: String?
}
```

- [ ] **Step 2: Add tests to `ColimaStateTests.swift`**

Append to `Tests/ColimaBarTests/ColimaStateTests.swift`:

```swift
// MARK: - DockerContainer health check tests

func test_health_healthy() {
    let c = DockerContainer(id: "x", name: "x", state: .running,
                            status: "Up 2 hours (healthy)", image: "nginx", ports: "")
    checkEqual(c.health, DockerContainer.HealthStatus.healthy, "status contains (healthy)")
}

func test_health_unhealthy() {
    let c = DockerContainer(id: "x", name: "x", state: .running,
                            status: "Up 1 hour (unhealthy)", image: "nginx", ports: "")
    checkEqual(c.health, DockerContainer.HealthStatus.unhealthy, "status contains (unhealthy)")
}

func test_health_starting() {
    let c = DockerContainer(id: "x", name: "x", state: .running,
                            status: "Up 5s (health: starting)", image: "nginx", ports: "")
    checkEqual(c.health, DockerContainer.HealthStatus.starting, "status contains (health: starting)")
}

func test_health_nil_no_healthcheck() {
    let c = DockerContainer(id: "x", name: "x", state: .running,
                            status: "Up 3 days", image: "nginx", ports: "")
    checkNil(c.health, "status without health → nil")
}

// MARK: - DockerContainer hostPortNumbers tests

func test_hostPortNumbers_single() {
    let c = DockerContainer(id: "x", name: "x", state: .running, status: "",
                            image: "", ports: "0.0.0.0:8080->8080/tcp")
    checkEqual(c.hostPortNumbers, [8080], "single port → [8080]")
}

func test_hostPortNumbers_multiple() {
    let c = DockerContainer(id: "x", name: "x", state: .running, status: "",
                            image: "", ports: "0.0.0.0:8000->8000/tcp, :::9443->9443/tcp")
    checkEqual(c.hostPortNumbers, [8000, 9443], "two ports → [8000, 9443]")
}

func test_hostPortNumbers_empty() {
    let c = DockerContainer(id: "x", name: "x", state: .running, status: "", image: "", ports: "")
    check(c.hostPortNumbers.isEmpty, "no ports → empty array")
}
```

- [ ] **Step 3: Register tests in `main.swift`**

Add after the last `test_` call in `Tests/ColimaBarTests/main.swift`:

```swift
test_health_healthy()
test_health_unhealthy()
test_health_starting()
test_health_nil_no_healthcheck()
test_hostPortNumbers_single()
test_hostPortNumbers_multiple()
test_hostPortNumbers_empty()
```

- [ ] **Step 4: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all previous tests pass + 7 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ColimaBarCore/DockerContainer.swift Tests/ColimaBarTests/ColimaStateTests.swift Tests/ColimaBarTests/main.swift
git commit -m "feat(core): add HealthStatus enum and hostPortNumbers to DockerContainer"
```

---

## Task 2: DockerImage — struct + parser + tests

**Files:**
- Create: `Sources/ColimaBarCore/DockerImage.swift`
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`
- Modify: `Tests/ColimaBarTests/ColimaStateTests.swift`
- Modify: `Tests/ColimaBarTests/main.swift`

- [ ] **Step 1: Create `DockerImage.swift`**

```swift
import Foundation

public struct DockerImage: Equatable {
    public let id: String
    public let repository: String
    public let tag: String
    public let size: String       // e.g. "142MB"
    public let created: String    // e.g. "3 weeks ago"
}

struct DockerImageJSON: Codable {
    let ID: String
    let Repository: String
    let Tag: String
    let Size: String
    let CreatedSince: String
}
```

- [ ] **Step 2: Add `parseDockerImages` to `ColimaManager.swift`**

In the `// MARK: - Static parsers` section of `Sources/ColimaBarCore/ColimaManager.swift`, add after `parseContainerStats`:

```swift
// Parses `docker images --format '{{json .}}'` NDJSON output.
public static func parseDockerImages(_ output: String) -> [DockerImage] {
    output.components(separatedBy: .newlines)
        .filter { !$0.isEmpty }
        .compactMap { line in
            guard let data = line.data(using: .utf8),
                  let j = try? JSONDecoder().decode(DockerImageJSON.self, from: data)
            else { return nil }
            return DockerImage(id: j.ID, repository: j.Repository, tag: j.Tag,
                               size: j.Size, created: j.CreatedSince)
        }
}
```

- [ ] **Step 3: Add tests to `ColimaStateTests.swift`**

```swift
// MARK: - parseDockerImages tests

private let imageOneLine = """
{"ID":"sha256:abc123","Repository":"nginx","Tag":"latest","Size":"142MB","CreatedSince":"3 weeks ago"}
"""
private let imageTwoLines = """
{"ID":"sha256:abc123","Repository":"nginx","Tag":"latest","Size":"142MB","CreatedSince":"3 weeks ago"}
{"ID":"sha256:def456","Repository":"postgres","Tag":"15","Size":"379MB","CreatedSince":"2 months ago"}
"""

func test_parseDockerImages_singleLine() {
    let images = ColimaManager.parseDockerImages(imageOneLine)
    check(images.count == 1, "1 image parsed")
    checkEqual(images[0].repository, "nginx", "repository = nginx")
    checkEqual(images[0].tag, "latest", "tag = latest")
    checkEqual(images[0].size, "142MB", "size = 142MB")
    checkEqual(images[0].created, "3 weeks ago", "created = 3 weeks ago")
    checkEqual(images[0].id, "sha256:abc123", "id correct")
}

func test_parseDockerImages_multiLine() {
    let images = ColimaManager.parseDockerImages(imageTwoLines)
    check(images.count == 2, "2 images parsed")
    checkEqual(images[1].repository, "postgres", "second repo = postgres")
}

func test_parseDockerImages_empty() {
    check(ColimaManager.parseDockerImages("").isEmpty, "empty → empty array")
    check(ColimaManager.parseDockerImages("not json").isEmpty, "invalid → empty array")
}
```

- [ ] **Step 4: Register tests in `main.swift`**

```swift
test_parseDockerImages_singleLine()
test_parseDockerImages_multiLine()
test_parseDockerImages_empty()
```

- [ ] **Step 5: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBarCore/DockerImage.swift Sources/ColimaBarCore/ColimaManager.swift Tests/ColimaBarTests/ColimaStateTests.swift Tests/ColimaBarTests/main.swift
git commit -m "feat(core): add DockerImage struct and parseDockerImages parser"
```

---

## Task 3: ColimaManager — image actions

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`

- [ ] **Step 1: Add `fetchImages`, `deleteImage`, `pullImage` to `ColimaManager`**

In the `// MARK: - Actions` section of `ColimaManager.swift`, add after `pruneDocker`:

```swift
public func fetchImages(completion: @escaping ([DockerImage]) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = self.shell.run(self.dockerPath, args: ["images", "--format", "{{json .}}"])
        let images = result.exitCode == 0 ? Self.parseDockerImages(result.output) : []
        DispatchQueue.main.async { completion(images) }
    }
}

public func deleteImage(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = self.shell.run(self.dockerPath, args: ["rmi", id])
        if result.exitCode == 0 {
            DispatchQueue.main.async { completion(.success(())) }
        } else {
            let msg = result.error.isEmpty ? "docker rmi \(id) failed" : result.error
            DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
        }
    }
}

public func pullImage(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = self.shell.run(self.dockerPath, args: ["pull", name])
        if result.exitCode == 0 {
            DispatchQueue.main.async { completion(.success(())) }
        } else {
            let msg = result.error.isEmpty ? "docker pull \(name) failed" : result.error
            DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ColimaBarCore/ColimaManager.swift
git commit -m "feat(core): add fetchImages, deleteImage, pullImage to ColimaManager"
```

---

## Task 4: DockerVolume — struct + parser + tests

**Files:**
- Create: `Sources/ColimaBarCore/DockerVolume.swift`
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`
- Modify: `Tests/ColimaBarTests/ColimaStateTests.swift`
- Modify: `Tests/ColimaBarTests/main.swift`

- [ ] **Step 1: Create `DockerVolume.swift`**

```swift
import Foundation

public struct DockerVolume: Equatable {
    public let name: String
    public let driver: String
    public let size: String    // e.g. "1.2GB" or "N/A"
}

struct DockerVolumeLSJSON: Codable {
    let Name: String
    let Driver: String
}
```

- [ ] **Step 2: Add `parseDockerVolumes` to `ColimaManager.swift`**

In the `// MARK: - Static parsers` section, add after `parseDockerImages`:

```swift
// Parses `docker volume ls --format '{{json .}}'` (lsOutput) for name+driver,
// cross-references `docker system df -v` (dfOutput) for sizes.
public static func parseDockerVolumes(_ lsOutput: String, _ dfOutput: String) -> [DockerVolume] {
    // Parse volume ls → name + driver
    var volumes: [(name: String, driver: String)] = []
    for line in lsOutput.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
        guard let data = line.data(using: .utf8),
              let v = try? JSONDecoder().decode(DockerVolumeLSJSON.self, from: data)
        else { continue }
        volumes.append((name: v.Name, driver: v.Driver))
    }

    // Parse df output for sizes: find "VOLUME NAME" header, then read name+size per line
    var sizes: [String: String] = [:]
    var inVolumeSection = false
    for line in dfOutput.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("VOLUME NAME") { inVolumeSection = true; continue }
        guard inVolumeSection, !trimmed.isEmpty else { continue }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count >= 3, let name = parts.first, let size = parts.last {
            sizes[String(name)] = String(size)
        }
    }

    return volumes.map { v in
        DockerVolume(name: v.name, driver: v.driver, size: sizes[v.name] ?? "N/A")
    }
}
```

- [ ] **Step 3: Add tests to `ColimaStateTests.swift`**

```swift
// MARK: - parseDockerVolumes tests

private let volumeLsOutput = """
{"Driver":"local","Name":"portainer_data"}
{"Driver":"local","Name":"my-vol"}
"""

private let volumeDfOutput = """
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Local Volumes   2         1         43MB      0B (0%)

Local Volumes space usage:

VOLUME NAME             LINKS     SIZE
portainer_data          1         42.54MB
my-vol                  0         1.23GB
"""

func test_parseDockerVolumes_countAndNames() {
    let vols = ColimaManager.parseDockerVolumes(volumeLsOutput, volumeDfOutput)
    check(vols.count == 2, "2 volumes")
    checkEqual(vols[0].name, "portainer_data", "first volume name")
    checkEqual(vols[1].name, "my-vol", "second volume name")
}

func test_parseDockerVolumes_driverAndSize() {
    let vols = ColimaManager.parseDockerVolumes(volumeLsOutput, volumeDfOutput)
    checkEqual(vols[0].driver, "local", "driver = local")
    checkEqual(vols[0].size, "42.54MB", "size from df output")
    checkEqual(vols[1].size, "1.23GB", "second volume size")
}

func test_parseDockerVolumes_sizeNA_whenDfMissing() {
    let vols = ColimaManager.parseDockerVolumes(volumeLsOutput, "")
    checkEqual(vols[0].size, "N/A", "size = N/A when df output empty")
}

func test_parseDockerVolumes_empty() {
    check(ColimaManager.parseDockerVolumes("", "").isEmpty, "empty ls → empty array")
}
```

- [ ] **Step 4: Register tests in `main.swift`**

```swift
test_parseDockerVolumes_countAndNames()
test_parseDockerVolumes_driverAndSize()
test_parseDockerVolumes_sizeNA_whenDfMissing()
test_parseDockerVolumes_empty()
```

- [ ] **Step 5: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBarCore/DockerVolume.swift Sources/ColimaBarCore/ColimaManager.swift Tests/ColimaBarTests/ColimaStateTests.swift Tests/ColimaBarTests/main.swift
git commit -m "feat(core): add DockerVolume struct and parseDockerVolumes parser"
```

---

## Task 5: ColimaManager — volume actions

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`

- [ ] **Step 1: Add `fetchVolumes` and `pruneVolumes` to `ColimaManager`**

In the `// MARK: - Actions` section, add after `pullImage`:

```swift
public func fetchVolumes(completion: @escaping ([DockerVolume]) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let lsResult = self.shell.run(self.dockerPath, args: ["volume", "ls", "--format", "{{json .}}"])
        let dfResult = self.shell.run(self.dockerPath, args: ["system", "df", "-v"])
        let volumes = Self.parseDockerVolumes(lsResult.output, dfResult.output)
        DispatchQueue.main.async { completion(volumes) }
    }
}

public func pruneVolumes(completion: @escaping (Result<String, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = self.shell.run(self.dockerPath, args: ["volume", "prune", "-f"])
        if result.exitCode == 0 {
            DispatchQueue.main.async { completion(.success(result.output)) }
        } else {
            let msg = result.error.isEmpty ? "docker volume prune failed" : result.error
            DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/ColimaBarCore/ColimaManager.swift
git commit -m "feat(core): add fetchVolumes and pruneVolumes to ColimaManager"
```

---

## Task 6: SparklineView — new file

**Files:**
- Create: `Sources/ColimaBar/SparklineView.swift`

- [ ] **Step 1: Create `SparklineView.swift`**

```swift
import AppKit

final class SparklineView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var color: NSColor = .systemBlue

    override func draw(_ dirtyRect: NSRect) {
        guard values.count >= 2 else { return }
        let maxVal = values.max() ?? 1.0
        guard maxVal > 0 else { return }

        let w = bounds.width
        let h = bounds.height
        let step = w / CGFloat(values.count - 1)

        func point(at i: Int) -> CGPoint {
            CGPoint(x: CGFloat(i) * step, y: CGFloat(values[i] / maxVal) * h)
        }

        // Filled area
        let area = NSBezierPath()
        area.move(to: CGPoint(x: 0, y: 0))
        for i in values.indices { area.line(to: point(at: i)) }
        area.line(to: CGPoint(x: w, y: 0))
        area.close()
        color.withAlphaComponent(0.25).setFill()
        area.fill()

        // Line
        let line = NSBezierPath()
        line.move(to: point(at: 0))
        for i in 1..<values.count { line.line(to: point(at: i)) }
        line.lineWidth = 1.5
        color.setStroke()
        line.stroke()
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/ColimaBar/SparklineView.swift
git commit -m "feat(ui): add SparklineView NSView for area chart rendering"
```

---

## Task 7: ContainersPanelViewController — tab infrastructure + health column

**Files:**
- Modify: `Sources/ColimaBar/ContainersPanelViewController.swift`
- Modify: `Sources/ColimaBar/StatusBarController.swift`

This task replaces `buildUI()` with a tab-aware structure and adds the health column. Replace the entire `ContainersPanelViewController.swift` with the following:

- [ ] **Step 1: Replace `ContainersPanelViewController.swift`**

```swift
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

    private var tabControl:           NSSegmentedControl!
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
    private var sparklineZone:           NSView!
    private var sparklineNameLbl:        NSTextField!
    private var cpuSparkline:            SparklineView!
    private var cpuValueLbl:             NSTextField!
    private var ramSparkline:            SparklineView!
    private var ramValueLbl:             NSTextField!
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
            ("tag",     "Tag",                       80.0),
            ("imgsize", L.t("Taille", "Size"),       80.0),
            ("created", L.t("Créée", "Created"),    120.0),
        ] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title; col.width = width; col.minWidth = 20
            if id == "repo"    { col.sortDescriptorPrototype = NSSortDescriptor(key: "repo", ascending: true) }
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

        pullBtn = makeBtn(L.t("Pull", "Pull"), #selector(pullAction))
        deleteImageBtn = makeBtn(L.t("Supprimer", "Delete"), #selector(deleteImageAction))
        deleteImageBtn.isEnabled = false

        pullSpinner = NSProgressIndicator()
        pullSpinner.style           = .spinning
        pullSpinner.controlSize     = .small
        pullSpinner.isHidden        = true
        pullSpinner.translatesAutoresizingMaskIntoConstraints = false
        imagesContentView.addSubview(pullSpinner)

        imageStatusLbl = NSTextField(labelWithString: "")
        imageStatusLbl.font      = .systemFont(ofSize: 11)
        imageStatusLbl.textColor = .secondaryLabelColor
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

        volumeStatusLbl = NSTextField(labelWithString: "")
        volumeStatusLbl.font      = .systemFont(ofSize: 11)
        volumeStatusLbl.textColor = .secondaryLabelColor
        volumeStatusLbl.lineBreakMode = .byTruncatingTail
        volumeStatusLbl.translatesAutoresizingMaskIntoConstraints = false
        volumesContentView.addSubview(volumeStatusLbl)

        pruneVolumesBtn.translatesAutoresizingMaskIntoConstraints = false
        volumesContentView.addSubview(pruneVolumesBtn)

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
        let base = ColimaConfig.showAllContainers ? allContainers : allContainers.filter { $0.isRunning }
        displayed = searchText.isEmpty
            ? base
            : base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        if let sd = currentSortDesc { sortDisplayed(by: sd) }
        tableView?.reloadData()
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
        }
    }

    // MARK: - Images data

    func refreshImages() {
        imageStatusLbl?.stringValue = L.t("Chargement…", "Loading…")
        onFetchImages? { [weak self] images in
            self?.allImages = images
            self?.imagesTableView?.reloadData()
            self?.imageStatusLbl?.stringValue = ""
            self?.deleteImageBtn?.isEnabled = false
        }
    }

    // MARK: - Volumes data

    func refreshVolumes() {
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
        pullBtn.isEnabled = false
        pullSpinner.isHidden = false
        pullSpinner.startAnimation(nil)
        imageStatusLbl.stringValue = L.t("Pull en cours…", "Pulling…")
        onPullImage?(name) { [weak self] result in
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
```

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: build succeeds. If there are compile errors, fix them before continuing.

- [ ] **Step 3: Update `StatusBarController.swift` — remove `onFetchStats`, add new callbacks, update popover size**

In `Sources/ColimaBar/StatusBarController.swift`:

a) Change `popover.contentSize` in `setupContainersPopover()`:
```swift
// Before:
popover.contentSize = NSSize(width: 900, height: 500)
// After:
popover.contentSize = NSSize(width: 900, height: 560)
```

b) Remove the `onFetchStats` wiring block entirely:
```swift
// Remove this block:
containersPanelVC.onFetchStats = { [weak self] name, completion in
    self?.manager.fetchContainerStats(name: name, completion: completion)
}
```

c) Add new callbacks after `containersPanelVC.onShell`:
```swift
containersPanelVC.onFetchImages = { [weak self] completion in
    self?.manager.fetchImages(completion: completion)
}
containersPanelVC.onDeleteImage = { [weak self] id, completion in
    self?.manager.deleteImage(id, completion: completion)
}
containersPanelVC.onPullImage = { [weak self] name, completion in
    self?.manager.pullImage(name, completion: completion)
}
containersPanelVC.onFetchVolumes = { [weak self] completion in
    self?.manager.fetchVolumes(completion: completion)
}
containersPanelVC.onPruneVolumes = { [weak self] completion in
    self?.manager.pruneVolumes(completion: completion)
}
```

- [ ] **Step 4: Build**

```bash
swift build
```

Expected: build succeeds with no errors.

- [ ] **Step 5: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all tests pass (no regressions).

- [ ] **Step 6: Install and verify visually**

```bash
make install && open /Applications/ColimaBar.app
```

Verify:
- Panel has "Containers / Images / Volumes" tab bar at top
- Containers tab shows all previous columns + new "health" dot column after state column
- Clicking Images tab shows image table + pull field + delete button
- Clicking Volumes tab shows volume table + prune button
- Select a running container → sparkline zone appears below table with CPU + RAM graphs
- Click a port number → browser opens http://localhost:PORT
- Containers with health checks show colored dot (green/red/yellow)

- [ ] **Step 7: Commit**

```bash
git add Sources/ColimaBar/ContainersPanelViewController.swift Sources/ColimaBar/StatusBarController.swift
git commit -m "feat(ui): add tabs (Containers/Images/Volumes), health column, PortsCell, sparklines"
```

---

## Task 8: Final — README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Move roadmap items to Features in README**

In `README.md`, add these lines to the Features section (after "Real-time aggregate CPU & RAM"):

```markdown
- **Health check status** — `●` colored indicator (green/yellow/red) per container showing health check state
- **Clickable port URLs** — each port number in the panel is a link, click opens `http://localhost:PORT` in browser
- **CPU/RAM sparklines** — mini area chart history (up to 20 points) shown in detail zone when a container is selected
- **Image management** — "Images" tab: list all images with size and date, pull new images, delete existing ones
- **Volume management** — "Volumes" tab: list all volumes with size, prune unused volumes
```

Replace the Roadmap section:

```markdown
## Roadmap

No planned features at this time.
```

- [ ] **Step 2: Update the Usage table**

Add these rows to the `## Usage` table:

```markdown
| View images | Panel → Images tab |
| Pull an image | Panel → Images tab → type name → Pull |
| Delete an image | Panel → Images tab → select → Delete |
| View volumes | Panel → Volumes tab |
| Prune volumes | Panel → Volumes tab → 🗑 Prune volumes… |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README for v1.7.0 — health, ports, sparklines, images, volumes"
```

---

## Self-review notes

- All 5 spec features covered: health ✓, ports ✓, sparklines ✓, images ✓, volumes ✓
- `onFetchStats` removed from both VC and StatusBarController — no dangling references
- `parseDockerVolumes` labeled params `(_ lsOutput:, _ dfOutput:)` — consistent with existing unlabeled convention
- `DockerVolumeLSJSON` is internal to `DockerVolume.swift` (no `public`) — not exposed from ColimaBarCore
- `DockerImageJSON` same: internal, not public
- Images/Volumes tabs load data lazily on tab switch via `refreshImages()`/`refreshVolumes()`
- History buffers self-clean on each `update()` call — no leak on container removal
