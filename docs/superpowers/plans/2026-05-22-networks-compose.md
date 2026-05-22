# Networks & Compose Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Networks tab (list + prune) and Compose tab (containers grouped by project) to the panel popover.

**Architecture:** DockerNetwork model + parser in ColimaBarCore; DockerContainer gets labels + composeProject; ContainersPanelViewController gets 2 new tabs; StatusBarController wires callbacks.

**Tech Stack:** Swift 5.9, AppKit, Foundation, SPM, macOS 13+

---

## Task 1: DockerNetwork — struct + parser + tests

**Files:**
- Create: `Sources/ColimaBarCore/DockerNetwork.swift`
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`
- Modify: `Tests/ColimaBarTests/ColimaStateTests.swift`
- Modify: `Tests/ColimaBarTests/main.swift`

- [ ] **Step 1: Create `DockerNetwork.swift`**

```swift
import Foundation

public struct DockerNetwork: Equatable {
    public let id: String
    public let name: String
    public let driver: String
    public let scope: String
}

struct DockerNetworkJSON: Codable {
    let ID: String
    let Name: String
    let Driver: String
    let Scope: String
}
```

- [ ] **Step 2: Add `parseDockerNetworks` to ColimaManager static parsers**

After `parseInstanceNames`:

```swift
// Parses `docker network ls --format '{{json .}}'` NDJSON output.
public static func parseDockerNetworks(_ output: String) -> [DockerNetwork] {
    output.components(separatedBy: .newlines)
        .filter { !$0.isEmpty }
        .compactMap { line in
            guard let data = line.data(using: .utf8),
                  let n = try? JSONDecoder().decode(DockerNetworkJSON.self, from: data)
            else { return nil }
            return DockerNetwork(id: n.ID, name: n.Name, driver: n.Driver, scope: n.Scope)
        }
}
```

- [ ] **Step 3: Add tests**

Append to `Tests/ColimaBarTests/ColimaStateTests.swift`:

```swift
// MARK: - parseDockerNetworks tests

private let networkTwoLines = """
{"ID":"abc123","Name":"bridge","Driver":"bridge","Scope":"local"}
{"ID":"def456","Name":"myapp_default","Driver":"bridge","Scope":"local"}
"""

func test_parseDockerNetworks_multiple() {
    let nets = ColimaManager.parseDockerNetworks(networkTwoLines)
    check(nets.count == 2, "2 networks")
    checkEqual(nets[0].name, "bridge", "first = bridge")
    checkEqual(nets[0].driver, "bridge", "driver = bridge")
    checkEqual(nets[1].name, "myapp_default", "second name")
    checkEqual(nets[0].scope, "local", "scope = local")
}

func test_parseDockerNetworks_empty() {
    check(ColimaManager.parseDockerNetworks("").isEmpty, "empty → empty array")
    check(ColimaManager.parseDockerNetworks("not json").isEmpty, "invalid → empty array")
}
```

- [ ] **Step 4: Register in `main.swift`**

```swift
test_parseDockerNetworks_multiple()
test_parseDockerNetworks_empty()
```

- [ ] **Step 5: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all 87 tests pass (85 + 2 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBarCore/DockerNetwork.swift Sources/ColimaBarCore/ColimaManager.swift Tests/ColimaBarTests/ColimaStateTests.swift Tests/ColimaBarTests/main.swift
git commit -m "feat(core): add DockerNetwork struct and parseDockerNetworks parser"
```

---

## Task 2: fetchNetworks + pruneNetworks actions

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`

- [ ] **Step 1: Add `fetchNetworks` and `pruneNetworks`**

In `// MARK: - Actions`, after `listInstances`:

```swift
public func fetchNetworks(completion: @escaping ([DockerNetwork]) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = self.shell.run(self.dockerPath, args: ["network", "ls", "--format", "{{json .}}"])
        let networks = result.exitCode == 0 ? Self.parseDockerNetworks(result.output) : []
        DispatchQueue.main.async { completion(networks) }
    }
}

public func pruneNetworks(completion: @escaping (Result<String, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = self.shell.run(self.dockerPath, args: ["network", "prune", "-f"])
        if result.exitCode == 0 {
            DispatchQueue.main.async { completion(.success(result.output)) }
        } else {
            let msg = result.error.isEmpty ? "docker network prune failed" : result.error
            DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

- [ ] **Step 3: Commit**

```bash
git add Sources/ColimaBarCore/ColimaManager.swift
git commit -m "feat(core): add fetchNetworks and pruneNetworks to ColimaManager"
```

---

## Task 3: DockerContainer — labels + composeProject + tests

**Files:**
- Modify: `Sources/ColimaBarCore/DockerContainer.swift`
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`
- Modify: `Tests/ColimaBarTests/ColimaStateTests.swift`
- Modify: `Tests/ColimaBarTests/main.swift`

- [ ] **Step 1: Add `labels` field and `composeProject` to `DockerContainer`**

Replace the entire `Sources/ColimaBarCore/DockerContainer.swift`:

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
    public let labels: String   // raw comma-separated "key=value" label string

    public init(id: String, name: String, state: ContainerState,
                status: String, image: String, ports: String, labels: String = "") {
        self.id     = id
        self.name   = name
        self.state  = state
        self.status = status
        self.image  = image
        self.ports  = ports
        self.labels = labels
    }

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

    // Extracts Docker Compose project name from labels (com.docker.compose.project=<name>)
    public var composeProject: String? {
        let prefix = "com.docker.compose.project="
        guard let kv = labels.components(separatedBy: ",").first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let v = String(kv.dropFirst(prefix.count))
        return v.isEmpty ? nil : v
    }
}

struct DockerContainerJSON: Codable {
    let ID: String
    let Names: String
    let State: String
    let Status: String
    let Image: String
    let Ports: String?
    let Labels: String?   // "key=value,key=value,..."
}
```

- [ ] **Step 2: Update `parseDockerContainers` in ColimaManager to pass labels**

In `parseDockerContainers`, update the `DockerContainer(...)` call:

```swift
return DockerContainer(
    id: c.ID,
    name: name,
    state: DockerContainer.ContainerState(rawValue: c.State) ?? .unknown,
    status: c.Status,
    image: c.Image,
    ports: c.Ports ?? "",
    labels: c.Labels ?? ""
)
```

- [ ] **Step 3: Add tests**

Append to `Tests/ColimaBarTests/ColimaStateTests.swift`:

```swift
// MARK: - DockerContainer composeProject tests

func test_composeProject_found() {
    let c = DockerContainer(id: "x", name: "myapp-web-1", state: .running, status: "Up",
                            image: "nginx", ports: "",
                            labels: "com.docker.compose.project=myapp,com.docker.compose.service=web")
    checkEqual(c.composeProject, "myapp", "composeProject = myapp")
}

func test_composeProject_nil_noLabel() {
    let c = DockerContainer(id: "x", name: "portainer", state: .running, status: "Up",
                            image: "portainer/portainer-ce", ports: "", labels: "")
    checkNil(c.composeProject, "no compose label → nil")
}

func test_composeProject_nil_otherLabels() {
    let c = DockerContainer(id: "x", name: "x", state: .running, status: "",
                            image: "", ports: "",
                            labels: "maintainer=nginx,version=1.0")
    checkNil(c.composeProject, "other labels but no compose project → nil")
}
```

- [ ] **Step 4: Register in `main.swift`**

```swift
test_composeProject_found()
test_composeProject_nil_noLabel()
test_composeProject_nil_otherLabels()
```

- [ ] **Step 5: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all 90 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBarCore/DockerContainer.swift Sources/ColimaBarCore/ColimaManager.swift Tests/ColimaBarTests/ColimaStateTests.swift Tests/ColimaBarTests/main.swift
git commit -m "feat(core): add labels + composeProject to DockerContainer"
```

---

## Task 4: ContainersPanelViewController — Networks + Compose tabs

**Files:**
- Modify: `Sources/ColimaBar/ContainersPanelViewController.swift`

This task adds 2 new tabs to the existing 3-tab panel. The tab segmented control changes from 3 to 5 segments. Two new content views are added.

- [ ] **Step 1: Add new callbacks and instance vars**

In `// MARK: - Callbacks`, add:

```swift
var onFetchNetworks: ((@escaping ([DockerNetwork]) -> Void) -> Void)?
var onPruneNetworks: ((@escaping (Result<String, Error>) -> Void) -> Void)?
```

In the properties block, add after `allVolumes`:

```swift
// Networks tab
private var networksTableView:  NSTableView!
private var networksScrollView: NSScrollView!
private var pruneNetworksBtn:   NSButton!
private var networkStatusLbl:   NSTextField!
private var allNetworks:        [DockerNetwork] = []

// Compose tab
private var composeTableView:   NSTableView!
private var composeScrollView:  NSScrollView!
private var composeContentView: NSView!
private var networksContentView: NSView!
```

- [ ] **Step 2: Update tab segmented control from 3 to 5 segments**

In `buildUI()`, replace the tabControl creation:

```swift
tabControl = NSSegmentedControl(
    labels: [L.t("Containers", "Containers"),
             L.t("Images", "Images"),
             L.t("Volumes", "Volumes"),
             L.t("Networks", "Networks"),
             L.t("Compose", "Compose")],
    trackingMode: .selectOne,
    target: self, action: #selector(tabChanged))
tabControl.selectedSegment = 0
tabControl.controlSize = .regular
tabControl.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(tabControl)
```

Add `networksContentView` and `composeContentView` alongside the existing 3 content views:

```swift
networksContentView = NSView()
networksContentView.translatesAutoresizingMaskIntoConstraints = false
networksContentView.isHidden = true
view.addSubview(networksContentView)

composeContentView = NSView()
composeContentView.translatesAutoresizingMaskIntoConstraints = false
composeContentView.isHidden = true
view.addSubview(composeContentView)
```

Add their constraints (same as the other 3 content views — fill below tab control):

```swift
networksContentView.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 4),
networksContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
networksContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
networksContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

composeContentView.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 4),
composeContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
composeContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
composeContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
```

Then call `buildNetworksUI()` and `buildComposeUI()` alongside the existing builders:

```swift
buildContainersUI()
buildImagesUI()
buildVolumesUI()
buildNetworksUI()
buildComposeUI()
```

- [ ] **Step 3: Update `tabChanged()` for 5 tabs**

Replace the existing `tabChanged()`:

```swift
@objc private func tabChanged() {
    containersContentView.isHidden = tabControl.selectedSegment != 0
    imagesContentView.isHidden     = tabControl.selectedSegment != 1
    volumesContentView.isHidden    = tabControl.selectedSegment != 2
    networksContentView.isHidden   = tabControl.selectedSegment != 3
    composeContentView.isHidden    = tabControl.selectedSegment != 4
    if tabControl.selectedSegment == 1 { refreshImages() }
    if tabControl.selectedSegment == 2 { refreshVolumes() }
    if tabControl.selectedSegment == 3 { refreshNetworks() }
    if tabControl.selectedSegment == 4 { refreshCompose() }
}
```

- [ ] **Step 4: Add `buildNetworksUI()` private method**

```swift
private func buildNetworksUI() {
    networksTableView = NSTableView()
    networksTableView.style      = .plain
    networksTableView.rowHeight  = 22
    networksTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    networksTableView.delegate   = self
    networksTableView.dataSource = self
    networksTableView.headerView = NSTableHeaderView()

    for (id, title, width) in [
        ("netname",   L.t("Nom", "Name"),       220.0),
        ("netdriver", L.t("Driver", "Driver"),    80.0),
        ("netscope",  L.t("Scope", "Scope"),      70.0),
    ] as [(String, String, CGFloat)] {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        col.title = title; col.width = width; col.minWidth = 20
        networksTableView.addTableColumn(col)
    }

    networksScrollView = NSScrollView()
    networksScrollView.documentView          = networksTableView
    networksScrollView.hasVerticalScroller   = true
    networksScrollView.autohidesScrollers    = true
    networksScrollView.borderType            = .bezelBorder
    networksScrollView.translatesAutoresizingMaskIntoConstraints = false
    networksContentView.addSubview(networksScrollView)

    pruneNetworksBtn = makeBtn(L.t("🗑 Prune réseaux…", "🗑 Prune networks…"),
                               #selector(pruneNetworksAction))
    pruneNetworksBtn.translatesAutoresizingMaskIntoConstraints = false
    networksContentView.addSubview(pruneNetworksBtn)

    networkStatusLbl = NSTextField(labelWithString: "")
    networkStatusLbl.font          = .systemFont(ofSize: 11)
    networkStatusLbl.textColor     = .secondaryLabelColor
    networkStatusLbl.lineBreakMode = .byTruncatingTail
    networkStatusLbl.translatesAutoresizingMaskIntoConstraints = false
    networksContentView.addSubview(networkStatusLbl)

    NSLayoutConstraint.activate([
        networksScrollView.topAnchor.constraint(equalTo: networksContentView.topAnchor, constant: 6),
        networksScrollView.leadingAnchor.constraint(equalTo: networksContentView.leadingAnchor, constant: 8),
        networksScrollView.trailingAnchor.constraint(equalTo: networksContentView.trailingAnchor, constant: -8),
        networksScrollView.bottomAnchor.constraint(equalTo: pruneNetworksBtn.topAnchor, constant: -6),

        pruneNetworksBtn.leadingAnchor.constraint(equalTo: networksContentView.leadingAnchor, constant: 8),
        pruneNetworksBtn.bottomAnchor.constraint(equalTo: networkStatusLbl.topAnchor, constant: -4),

        networkStatusLbl.leadingAnchor.constraint(equalTo: networksContentView.leadingAnchor, constant: 12),
        networkStatusLbl.trailingAnchor.constraint(equalTo: networksContentView.trailingAnchor, constant: -12),
        networkStatusLbl.bottomAnchor.constraint(equalTo: networksContentView.bottomAnchor, constant: -10),
        networkStatusLbl.heightAnchor.constraint(equalToConstant: 16),
    ])
}
```

- [ ] **Step 5: Add `buildComposeUI()` private method**

```swift
private func buildComposeUI() {
    composeTableView = NSTableView()
    composeTableView.style      = .plain
    composeTableView.rowHeight  = 22
    composeTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    composeTableView.delegate   = self
    composeTableView.dataSource = self
    composeTableView.headerView = NSTableHeaderView()

    for (id, title, width) in [
        ("cproject", L.t("Projet", "Project"),          240.0),
        ("ccount",   L.t("Containers", "Containers"),    80.0),
        ("cstatus",  L.t("Statut", "Status"),           160.0),
    ] as [(String, String, CGFloat)] {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        col.title = title; col.width = width; col.minWidth = 20
        composeTableView.addTableColumn(col)
    }

    composeScrollView = NSScrollView()
    composeScrollView.documentView          = composeTableView
    composeScrollView.hasVerticalScroller   = true
    composeScrollView.autohidesScrollers    = true
    composeScrollView.borderType            = .bezelBorder
    composeScrollView.translatesAutoresizingMaskIntoConstraints = false
    composeContentView.addSubview(composeScrollView)

    NSLayoutConstraint.activate([
        composeScrollView.topAnchor.constraint(equalTo: composeContentView.topAnchor, constant: 6),
        composeScrollView.leadingAnchor.constraint(equalTo: composeContentView.leadingAnchor, constant: 8),
        composeScrollView.trailingAnchor.constraint(equalTo: composeContentView.trailingAnchor, constant: -8),
        composeScrollView.bottomAnchor.constraint(equalTo: composeContentView.bottomAnchor, constant: -10),
    ])
}
```

- [ ] **Step 6: Add data + action methods for Networks and Compose**

```swift
// Networks data
private func refreshNetworks() {
    networkStatusLbl?.stringValue = L.t("Chargement…", "Loading…")
    onFetchNetworks? { [weak self] networks in
        self?.allNetworks = networks
        self?.networksTableView?.reloadData()
        self?.networkStatusLbl?.stringValue = ""
    }
}

// Compose data — derived from allContainers, no fetch needed
private func refreshCompose() {
    composeTableView?.reloadData()
}

// Compose rows: (projectName, containers)
private var composeProjects: [(name: String, containers: [DockerContainer])] {
    var dict: [String: [DockerContainer]] = [:]
    for c in allContainers {
        guard let project = c.composeProject else { continue }
        dict[project, default: []].append(c)
    }
    return dict.map { (name: $0.key, containers: $0.value) }
               .sorted { $0.name < $1.name }
}

// Networks action
@objc private func pruneNetworksAction() {
    let alert = NSAlert()
    alert.messageText     = L.t("Purger les réseaux", "Prune networks")
    alert.informativeText = L.t(
        "Supprime tous les réseaux non utilisés. Irréversible.",
        "Removes all unused networks. Cannot be undone.")
    alert.alertStyle = .warning
    alert.addButton(withTitle: L.t("Purger", "Prune"))
    alert.addButton(withTitle: L.t("Annuler", "Cancel"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    pruneNetworksBtn.isEnabled = false
    onPruneNetworks? { [weak self] result in
        self?.pruneNetworksBtn.isEnabled = true
        switch result {
        case .success(let output):
            let lines = output.components(separatedBy: .newlines).filter { $0.hasPrefix("Total") }
            self?.networkStatusLbl.stringValue = lines.first ?? L.t("✓ Réseaux purgés", "✓ Networks pruned")
            self?.refreshNetworks()
        case .failure(let e):
            self?.networkStatusLbl.stringValue = "✗ \(e.localizedDescription)"
        }
    }
}
```

- [ ] **Step 7: Update `numberOfRows` and `tableView(_:viewFor:row:)` for the 2 new tables**

In `numberOfRows(in:)`, add:

```swift
if tableView == networksTableView  { return allNetworks.count }
if tableView == composeTableView   { return composeProjects.count }
```

In `tableView(_:viewFor:row:)`, add two new sections before the containers table section:

```swift
// Networks table
if tableView == networksTableView {
    let cid = NSUserInterfaceItemIdentifier("net-\(id)")
    let cell = (tableView.makeView(withIdentifier: cid, owner: self) as? NSTableCellView)
        ?? makeTextCell(id: cid)
    guard row < allNetworks.count else { return cell }
    let net = allNetworks[row]
    switch id {
    case "netname":   cell.textField?.stringValue = net.name;   cell.textField?.textColor = .labelColor
    case "netdriver": cell.textField?.stringValue = net.driver; cell.textField?.textColor = .secondaryLabelColor
    case "netscope":  cell.textField?.stringValue = net.scope;  cell.textField?.textColor = .secondaryLabelColor
    default: break
    }
    return cell
}

// Compose table
if tableView == composeTableView {
    let cid = NSUserInterfaceItemIdentifier("comp-\(id)")
    let cell = (tableView.makeView(withIdentifier: cid, owner: self) as? NSTableCellView)
        ?? makeTextCell(id: cid)
    let projects = composeProjects
    guard row < projects.count else { return cell }
    let proj = projects[row]
    let running = proj.containers.filter { $0.isRunning }.count
    let total   = proj.containers.count
    switch id {
    case "cproject":
        cell.textField?.stringValue = proj.name
        cell.textField?.textColor   = .labelColor
    case "ccount":
        cell.textField?.stringValue = "\(total)"
        cell.textField?.textColor   = .secondaryLabelColor
    case "cstatus":
        if running == total {
            cell.textField?.stringValue = "✅ All running"
            cell.textField?.textColor   = .systemGreen
        } else if running == 0 {
            cell.textField?.stringValue = "⛔ Stopped"
            cell.textField?.textColor   = .tertiaryLabelColor
        } else {
            cell.textField?.stringValue = "⚠ \(running)/\(total) running"
            cell.textField?.textColor   = .systemOrange
        }
    default: break
    }
    return cell
}
```

- [ ] **Step 8: Also call `refreshCompose()` from `update()` if compose tab is visible**

At the end of `update(containers:usage:containerStats:restartPolicies:)`:

```swift
if tabControl?.selectedSegment == 4 { refreshCompose() }
```

- [ ] **Step 9: Build**

```bash
swift build
```

- [ ] **Step 10: Commit**

```bash
git add Sources/ColimaBar/ContainersPanelViewController.swift
git commit -m "feat(ui): add Networks and Compose tabs to containers panel"
```

---

## Task 5: StatusBarController — wire network callbacks

**Files:**
- Modify: `Sources/ColimaBar/StatusBarController.swift`

- [ ] **Step 1: Wire `onFetchNetworks` and `onPruneNetworks`**

In `setupContainersPopover()`, after `onPruneVolumes`:

```swift
containersPanelVC.onFetchNetworks = { [weak self] completion in
    self?.manager.fetchNetworks(completion: completion)
}
containersPanelVC.onPruneNetworks = { [weak self] completion in
    self?.manager.pruneNetworks(completion: completion)
}
```

- [ ] **Step 2: Build + run tests + install**

```bash
swift build
swift run ColimaBarTests   # expect 90 tests pass
make install && open /Applications/ColimaBar.app
```

Verify:
- Panel has 5 tabs: Containers | Images | Volumes | Networks | Compose
- Networks tab shows Docker networks list + Prune button
- Compose tab shows projects grouped (only visible when running containers have compose labels)

- [ ] **Step 3: Commit**

```bash
git add Sources/ColimaBar/StatusBarController.swift
git commit -m "feat(ui): wire onFetchNetworks + onPruneNetworks in StatusBarController"
```
