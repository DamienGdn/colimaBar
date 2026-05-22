# Panel Containers Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add context menu, env vars popover, restart policy column, quick image filter, and custom exec dialog to the containers panel.

**Architecture:** Core layer (ColimaBarCore) gets new parsers + actions; UI layer (ColimaBar) gets new AppKit components. No new files except `EnvVarsViewController.swift`. All existing patterns followed: async actions on userInitiated queue, completions on main.

**Tech Stack:** Swift 5.9, AppKit, Foundation, custom test runner (no XCTest), SPM, macOS 13+

---

## Task 1: ColimaAppState + parseRestartPolicies + tests

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaState.swift`
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`
- Modify: `Tests/ColimaBarTests/ColimaStateTests.swift`
- Modify: `Tests/ColimaBarTests/main.swift`

- [ ] **Step 1: Add `restartPolicies` field to `ColimaAppState`**

In `Sources/ColimaBarCore/ColimaState.swift`, update `ColimaAppState`:

```swift
public struct ColimaAppState: Equatable {
    public let colima: ColimaRunningState
    public let cpus: Int?
    public let memoryGB: Double?
    public let portainerExists: Bool
    public let usage: ResourceUsage?
    public let containerStats: [String: ResourceUsage]
    public let containers: [DockerContainer]
    public let startDuration: TimeInterval?
    public let restartPolicies: [String: String]   // containerName → policyName

    public init(
        colima: ColimaRunningState,
        cpus: Int? = nil,
        memoryGB: Double? = nil,
        portainerExists: Bool = false,
        usage: ResourceUsage? = nil,
        containerStats: [String: ResourceUsage] = [:],
        containers: [DockerContainer] = [],
        startDuration: TimeInterval? = nil,
        restartPolicies: [String: String] = [:]
    ) {
        self.colima = colima
        self.cpus = cpus
        self.memoryGB = memoryGB
        self.portainerExists = portainerExists
        self.usage = usage
        self.containerStats = containerStats
        self.containers = containers
        self.startDuration = startDuration
        self.restartPolicies = restartPolicies
    }

    public static let unknown = ColimaAppState(colima: .unknown)
}
```

- [ ] **Step 2: Add `parseRestartPolicies` static method to `ColimaManager.swift`**

In the `// MARK: - Static parsers` section of `Sources/ColimaBarCore/ColimaManager.swift`, add after `parseDockerVolumes`:

```swift
// Parses `docker inspect --format '{{slice .Name 1}}\t{{.HostConfig.RestartPolicy.Name}}' <ids...>`
public static func parseRestartPolicies(_ output: String) -> [String: String] {
    var result: [String: String] = [:]
    for line in output.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 2 else { continue }
        let name   = parts[0].trimmingCharacters(in: .whitespaces)
        let policy = parts[1].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { continue }
        result[name] = policy
    }
    return result
}
```

- [ ] **Step 3: Write tests in `ColimaStateTests.swift`**

Append:

```swift
// MARK: - parseRestartPolicies tests

func test_parseRestartPolicies_multiple() {
    let output = "portainer\talways\nmy-app\tno\nnginx\ton-failure"
    let policies = ColimaManager.parseRestartPolicies(output)
    check(policies.count == 3, "3 policies parsed")
    checkEqual(policies["portainer"], "always", "portainer = always")
    checkEqual(policies["my-app"], "no", "my-app = no")
    checkEqual(policies["nginx"], "on-failure", "nginx = on-failure")
}

func test_parseRestartPolicies_empty() {
    check(ColimaManager.parseRestartPolicies("").isEmpty, "empty → empty dict")
}

func test_parseRestartPolicies_emptyPolicy() {
    let output = "my-container\t"
    let policies = ColimaManager.parseRestartPolicies(output)
    checkEqual(policies["my-container"], "", "empty policy stored as empty string")
}
```

- [ ] **Step 4: Register tests in `main.swift`**

Add after last test call:

```swift
test_parseRestartPolicies_multiple()
test_parseRestartPolicies_empty()
test_parseRestartPolicies_emptyPolicy()
```

- [ ] **Step 5: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all 82 tests pass (79 existing + 3 new).

- [ ] **Step 6: Build**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/ColimaBarCore/ColimaState.swift Sources/ColimaBarCore/ColimaManager.swift Tests/ColimaBarTests/ColimaStateTests.swift Tests/ColimaBarTests/main.swift
git commit -m "feat(core): add restartPolicies to ColimaAppState + parseRestartPolicies parser"
```

---

## Task 2: fetchStateSync — restart policies + setRestartPolicy action

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`

- [ ] **Step 1: Update `fetchStateSync` to fetch restart policies**

In `fetchStateSync()`, after the line `containers = Self.parseDockerContainers(containerResult.output)`, add:

```swift
var restartPolicies: [String: String] = [:]
if !containers.isEmpty {
    var inspectArgs = ["inspect", "--format",
                       "{{slice .Name 1}}\t{{.HostConfig.RestartPolicy.Name}}"]
    inspectArgs.append(contentsOf: containers.map { $0.id })
    let inspectResult = shell.run(dockerPath, args: inspectArgs)
    restartPolicies = Self.parseRestartPolicies(inspectResult.output)
}
```

Then update the `return ColimaAppState(...)` call to include `restartPolicies`:

```swift
return ColimaAppState(
    colima: isRunning ? .running : .stopped,
    cpus: entry.cpus,
    memoryGB: memoryGB,
    portainerExists: portainerExists,
    usage: usage,
    containerStats: containerStats,
    containers: containers,
    restartPolicies: restartPolicies
)
```

- [ ] **Step 2: Add `setRestartPolicy` action**

In the `// MARK: - Actions` section, after `pruneVolumes`:

```swift
public func setRestartPolicy(_ policy: String, container: String,
                             completion: @escaping (Result<Void, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = self.shell.run(self.dockerPath,
                                   args: ["update", "--restart=\(policy)", container])
        if result.exitCode == 0 {
            DispatchQueue.main.async { completion(.success(())) }
        } else {
            let msg = result.error.isEmpty
                ? "docker update --restart=\(policy) \(container) failed"
                : result.error
            DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 4: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ColimaBarCore/ColimaManager.swift
git commit -m "feat(core): fetch restart policies in polling cycle + setRestartPolicy action"
```

---

## Task 3: fetchEnvVars action

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`

- [ ] **Step 1: Add `fetchEnvVars` to ColimaManager**

In the `// MARK: - Actions` section, after `setRestartPolicy`:

```swift
public func fetchEnvVars(container: String, completion: @escaping ([String]) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = self.shell.run(self.dockerPath, args: [
            "inspect", "--format", "{{json .Config.Env}}", container
        ])
        guard result.exitCode == 0,
              let data = result.output
                  .trimmingCharacters(in: .whitespacesAndNewlines)
                  .data(using: .utf8),
              let envArray = try? JSONDecoder().decode([String].self, from: data)
        else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        DispatchQueue.main.async { completion(envArray) }
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
git commit -m "feat(core): add fetchEnvVars to ColimaManager"
```

---

## Task 4: ContainersPanelViewController — restart column + applyFilter image fix

**Files:**
- Modify: `Sources/ColimaBar/ContainersPanelViewController.swift`

- [ ] **Step 1: Add `restartPolicies` instance var and update `update()` signature**

In the `// MARK: - Containers tab` properties block, after `containerStats`, add:

```swift
private var restartPolicies: [String: String] = [:]
```

Update the `update()` method signature to accept restartPolicies (with default so existing callers compile):

```swift
func update(containers: [DockerContainer], usage: ResourceUsage?,
            containerStats: [String: ResourceUsage] = [:],
            restartPolicies: [String: String] = [:]) {
    updateHistoryBuffers(containers: containers, stats: containerStats)
    allContainers        = containers
    self.usage           = usage
    self.containerStats  = containerStats
    self.restartPolicies = restartPolicies
    guard isViewLoaded else { return }
    applyFilter()
    refreshStats()
}
```

- [ ] **Step 2: Add `"restart"` column to the containers table**

In `buildContainersUI()`, in the columns array, insert `"restart"` after `"status"`:

```swift
for (id, title, width) in [
    ("state",   "",                                22.0),
    ("name",    L.t("Nom", "Name"),              160.0),
    ("image",   L.t("Image", "Image"),            150.0),
    ("status",  L.t("Statut", "Status"),           90.0),
    ("restart", L.t("Restart", "Restart"),         70.0),
    ("ports",   L.t("Ports", "Ports"),            100.0),
    ("cpu",     "CPU %",                           65.0),
    ("ram",     "RAM",                            100.0),
] as [(String, String, CGFloat)] {
```

- [ ] **Step 3: Handle `"restart"` case in `tableView(_:viewFor:row:)`**

In the containers table section of `tableView(_:viewFor:row:)`, add after the `"status"` case:

```swift
case "restart":
    let policy = restartPolicies[c.name] ?? ""
    switch policy {
    case "always":          cell.textField?.stringValue = "↺ always";  cell.textField?.textColor = .secondaryLabelColor
    case "on-failure":      cell.textField?.stringValue = "⚠ on-fail"; cell.textField?.textColor = .secondaryLabelColor
    case "unless-stopped":  cell.textField?.stringValue = "◎ unless";  cell.textField?.textColor = .secondaryLabelColor
    default:                cell.textField?.stringValue = "—";          cell.textField?.textColor = .tertiaryLabelColor
    }
```

- [ ] **Step 4: Fix `applyFilter()` to also match container image name**

Replace the existing filter predicate:

```swift
// Before:
: base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

// After:
: base.filter {
    $0.name.localizedCaseInsensitiveContains(searchText) ||
    $0.image.localizedCaseInsensitiveContains(searchText)
}
```

- [ ] **Step 5: Build**

```bash
swift build
```

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBar/ContainersPanelViewController.swift
git commit -m "feat(ui): add restart policy column, fix applyFilter to match image name"
```

---

## Task 5: ContainersPanelViewController — context menu

**Files:**
- Modify: `Sources/ColimaBar/ContainersPanelViewController.swift`

- [ ] **Step 1: Add new callbacks and `contextMenu` + `onInspect` vars**

In the `// MARK: - Callbacks` section, add:

```swift
var onSetRestartPolicy: ((String, String, @escaping (Result<Void, Error>) -> Void) -> Void)?
var onFetchEnvVars:     ((String, @escaping ([String]) -> Void) -> Void)?
var onInspect:          ((String) -> Void)?
```

In the `// MARK: - Containers tab` properties block, add:

```swift
private var contextMenu = NSMenu()
```

- [ ] **Step 2: Set `tableView.menu` and make VC an `NSMenuDelegate`**

At the end of `buildContainersUI()`, before `refreshStats()`:

```swift
tableView.menu = contextMenu
contextMenu.delegate = self
```

Add the conformance at the bottom of the file (outside the existing extensions):

```swift
// MARK: - NSMenuDelegate

extension ContainersPanelViewController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let row = tableView.clickedRow
        guard row >= 0 && row < displayed.count else {
            menu.removeAllItems()
            return
        }
        rebuildContextMenu(for: displayed[row])
    }
}
```

- [ ] **Step 3: Add `rebuildContextMenu(for:)` private method**

Add in the `// MARK: - Containers data` area:

```swift
private func rebuildContextMenu(for c: DockerContainer) {
    contextMenu.removeAllItems()

    // Start / Stop / Restart
    let startItem = NSMenuItem(title: L.t("▶ Démarrer", "▶ Start"),
                               action: #selector(menuStart), keyEquivalent: "")
    startItem.target = self; startItem.isEnabled = !c.isRunning
    contextMenu.addItem(startItem)

    let stopItem = NSMenuItem(title: L.t("■ Arrêter", "■ Stop"),
                              action: #selector(menuStop), keyEquivalent: "")
    stopItem.target = self; stopItem.isEnabled = c.isRunning
    contextMenu.addItem(stopItem)

    let restartItem = NSMenuItem(title: L.t("↺ Restart", "↺ Restart"),
                                 action: #selector(menuRestart), keyEquivalent: "")
    restartItem.target = self; restartItem.isEnabled = c.isRunning
    contextMenu.addItem(restartItem)

    contextMenu.addItem(.separator())

    // Logs / Shell
    let logsItem = NSMenuItem(title: L.t("Logs", "Logs"),
                              action: #selector(menuLogs), keyEquivalent: "")
    logsItem.target = self
    contextMenu.addItem(logsItem)

    let shellItem = NSMenuItem(title: L.t("Shell…", "Shell…"),
                               action: #selector(menuShell), keyEquivalent: "")
    shellItem.target = self; shellItem.isEnabled = c.isRunning
    contextMenu.addItem(shellItem)

    contextMenu.addItem(.separator())

    // Copy ID
    let copyItem = NSMenuItem(title: L.t("Copier l'ID", "Copy ID"),
                              action: #selector(menuCopyID), keyEquivalent: "")
    copyItem.target = self
    contextMenu.addItem(copyItem)

    // Open port(s)
    for port in c.hostPortNumbers {
        let portItem = NSMenuItem(title: "Open Port \(port)",
                                  action: #selector(menuOpenPort(_:)), keyEquivalent: "")
        portItem.target = self; portItem.tag = port
        contextMenu.addItem(portItem)
    }

    contextMenu.addItem(.separator())

    // Filter by image
    let filterItem = NSMenuItem(title: L.t("Filtrer par cette image", "Filter by this image"),
                                action: #selector(menuFilterByImage), keyEquivalent: "")
    filterItem.target = self
    contextMenu.addItem(filterItem)

    contextMenu.addItem(.separator())

    // Restart policy submenu
    let policySubmenu = NSMenu()
    let currentPolicy = restartPolicies[c.name] ?? "no"
    for policy in ["always", "on-failure", "unless-stopped", "no"] {
        let item = NSMenuItem(title: policy, action: #selector(menuSetPolicy(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = policy
        item.state = currentPolicy == policy ? .on : .off
        policySubmenu.addItem(item)
    }
    let policyItem = NSMenuItem(title: L.t("Restart policy", "Restart policy"),
                                action: nil, keyEquivalent: "")
    policyItem.submenu = policySubmenu
    contextMenu.addItem(policyItem)

    // Inspect
    let inspectItem = NSMenuItem(title: L.t("Inspect", "Inspect"),
                                 action: #selector(menuInspect), keyEquivalent: "")
    inspectItem.target = self
    contextMenu.addItem(inspectItem)
}
```

- [ ] **Step 4: Add `clickedContainer()` helper and all menu action handlers**

Add after `rebuildContextMenu`:

```swift
private func clickedContainer() -> DockerContainer? {
    let row = tableView.clickedRow
    guard row >= 0 && row < displayed.count else { return nil }
    return displayed[row]
}

@objc private func menuStart()   { guard let c = clickedContainer() else { return }; onStart?(c.name) }
@objc private func menuStop()    { guard let c = clickedContainer() else { return }; onStop?(c.name) }
@objc private func menuRestart() { guard let c = clickedContainer() else { return }; onRestart?(c.name) }
@objc private func menuLogs()    { guard let c = clickedContainer() else { return }; onLogs?(c.name) }
@objc private func menuShell()   { guard let c = clickedContainer() else { return }; showExecDialog(for: c) }

@objc private func menuCopyID() {
    guard let c = clickedContainer() else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(c.id, forType: .string)
}

@objc private func menuOpenPort(_ sender: NSMenuItem) {
    NSWorkspace.shared.open(URL(string: "http://localhost:\(sender.tag)")!)
}

@objc private func menuFilterByImage() {
    guard let c = clickedContainer() else { return }
    searchField.stringValue = c.image
    searchText = c.image
    applyFilter()
}

@objc private func menuSetPolicy(_ sender: NSMenuItem) {
    guard let c = clickedContainer(),
          let policy = sender.representedObject as? String else { return }
    onSetRestartPolicy?(policy, c.name) { _ in }
}

@objc private func menuInspect() {
    guard let c = clickedContainer() else { return }
    onInspect?(c.name)
}
```

- [ ] **Step 5: Build**

```bash
swift build
```

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBar/ContainersPanelViewController.swift
git commit -m "feat(ui): add context menu with all actions (start/stop/logs/copy/ports/policy/inspect)"
```

---

## Task 6: ContainersPanelViewController — custom exec dialog

**Files:**
- Modify: `Sources/ColimaBar/ContainersPanelViewController.swift`
- Modify: `Sources/ColimaBar/StatusBarController.swift`

- [ ] **Step 1: Change `onShell` callback signature from `(String)` to `(String, String)`**

In the `// MARK: - Callbacks` section, change:

```swift
// Before:
var onShell: ((String) -> Void)?

// After:
var onShell: ((String, String) -> Void)?   // (containerName, command)
```

- [ ] **Step 2: Add `showExecDialog(for:)` and update `shellAction()`**

Replace the existing `shellAction()`:

```swift
@objc private func shellAction() {
    guard let c = selected() else { return }
    showExecDialog(for: c)
}
```

Add `showExecDialog` in the `// MARK: - Containers actions` section:

```swift
private func showExecDialog(for container: DockerContainer) {
    let alert = NSAlert()
    alert.messageText     = "Shell into \(container.name)"
    alert.informativeText = L.t("Commande à exécuter :", "Command to execute:")
    let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
    tf.stringValue = "sh"
    alert.accessoryView = tf
    alert.addButton(withTitle: L.t("Exécuter", "Run"))
    alert.addButton(withTitle: L.t("Annuler", "Cancel"))
    alert.window.initialFirstResponder = tf
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let cmd = tf.stringValue.trimmingCharacters(in: .whitespaces)
    onShell?(container.name, cmd.isEmpty ? "sh" : cmd)
}
```

- [ ] **Step 3: Update `StatusBarController.swift` — fix onShell wiring + openShellTerminal**

In `setupContainersPopover()`, replace the `onShell` block:

```swift
// Before:
containersPanelVC.onShell = { [weak self] name in
    self?.openShellTerminal(containerName: name)
}

// After:
containersPanelVC.onShell = { [weak self] name, command in
    self?.openShellTerminal(containerName: name, command: command)
}
```

Replace `openShellTerminal`:

```swift
// Before:
private func openShellTerminal(containerName name: String) {
    runInTerminal("docker exec -it \(name) sh")
}

// After:
private func openShellTerminal(containerName name: String, command: String) {
    runInTerminal("docker exec -it \(name) \(command)")
}
```

- [ ] **Step 4: Build**

```bash
swift build
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ColimaBar/ContainersPanelViewController.swift Sources/ColimaBar/StatusBarController.swift
git commit -m "feat(ui): custom exec command dialog — Shell… prompts for command before opening Terminal"
```

---

## Task 7: EnvVarsViewController — new file

**Files:**
- Create: `Sources/ColimaBar/EnvVarsViewController.swift`

- [ ] **Step 1: Create the file**

```swift
import AppKit
import ColimaBarCore

final class EnvVarsViewController: NSViewController {
    var containerName: String = ""
    private var envVars: [(key: String, value: String)] = []

    private var headerLbl:   NSTextField!
    private var scrollView:  NSScrollView!
    private var tableView:   NSTableView!
    private var statusLbl:   NSTextField!
    private var copyAllBtn:  NSButton!

    func loadEnvVars(_ vars: [String]) {
        envVars = vars.map { s -> (String, String) in
            if let idx = s.firstIndex(of: "=") {
                return (String(s[..<idx]), String(s[s.index(after: idx)...]))
            }
            return (s, "")
        }
        tableView?.reloadData()
        statusLbl?.stringValue = envVars.isEmpty ? L.t("Aucune variable", "No env vars") : ""
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 320))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        statusLbl.stringValue = L.t("Chargement…", "Loading…")
    }

    private func buildUI() {
        headerLbl = NSTextField(labelWithString: containerName)
        headerLbl.font      = .boldSystemFont(ofSize: 13)
        headerLbl.textColor = .labelColor
        headerLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLbl)

        tableView = NSTableView()
        tableView.style     = .plain
        tableView.rowHeight = 20
        tableView.delegate  = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()

        for (id, title, width) in [
            ("key",   L.t("Clé", "Key"),       180.0),
            ("value", L.t("Valeur", "Value"),   280.0),
        ] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title; col.width = width; col.minWidth = 40
            tableView.addTableColumn(col)
        }

        scrollView = NSScrollView()
        scrollView.documentView        = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.borderType          = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        statusLbl = NSTextField(labelWithString: "")
        statusLbl.font        = .systemFont(ofSize: 11)
        statusLbl.textColor   = .secondaryLabelColor
        statusLbl.alignment   = .center
        statusLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLbl)

        copyAllBtn = NSButton(title: L.t("Copier tout", "Copy all"),
                              target: self, action: #selector(copyAll))
        copyAllBtn.bezelStyle  = .rounded
        copyAllBtn.controlSize = .small
        copyAllBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(copyAllBtn)

        NSLayoutConstraint.activate([
            headerLbl.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            headerLbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            headerLbl.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: headerLbl.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: copyAllBtn.topAnchor, constant: -6),

            statusLbl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLbl.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            copyAllBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            copyAllBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])
    }

    @objc private func copyAll() {
        let text = envVars.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension EnvVarsViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { envVars.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id  = tableColumn?.identifier.rawValue ?? ""
        let cid = NSUserInterfaceItemIdentifier("env-\(id)")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cid, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cid
            let tf = NSTextField(labelWithString: "")
            tf.font          = .monospacedSystemFont(ofSize: 11, weight: .regular)
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf); cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let pair = envVars[row]
        switch id {
        case "key":
            cell.textField?.stringValue = pair.key
            cell.textField?.textColor   = .labelColor
        case "value":
            cell.textField?.stringValue = pair.value
            cell.textField?.textColor   = .secondaryLabelColor
        default: break
        }
        return cell
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
git add Sources/ColimaBar/EnvVarsViewController.swift
git commit -m "feat(ui): add EnvVarsViewController — env vars popover with KEY/VALUE table"
```

---

## Task 8: ContainersPanelViewController — Env button

**Files:**
- Modify: `Sources/ColimaBar/ContainersPanelViewController.swift`

- [ ] **Step 1: Add `envBtn` + `envPopover` instance vars**

In the `// MARK: - Containers tab` properties block, after `shellBtn`:

```swift
private var envBtn:     NSButton!
private var envPopover: NSPopover?
```

- [ ] **Step 2: Add `envBtn` to the action button stack in `buildContainersUI()`**

Replace the button stack creation:

```swift
// Before:
let btnStack = NSStackView(views: [startBtn, stopBtn, restartBtn, logsBtn, shellBtn])

// After:
envBtn = makeBtn(L.t("Env", "Env"), #selector(envAction))
let btnStack = NSStackView(views: [startBtn, stopBtn, restartBtn, logsBtn, shellBtn, envBtn])
```

- [ ] **Step 3: Update `updateButtons()` to handle envBtn**

Add to the end of `updateButtons()`:

```swift
envBtn.isEnabled = c != nil
```

- [ ] **Step 4: Add `envAction()` method**

In `// MARK: - Containers actions`, add:

```swift
@objc private func envAction() {
    guard let c = selected() else { return }
    let vc = EnvVarsViewController()
    vc.containerName = c.name
    envPopover?.close()
    let popover = NSPopover()
    popover.contentViewController = vc
    popover.behavior               = .semitransient
    popover.contentSize            = NSSize(width: 500, height: 320)
    envPopover = popover
    popover.show(relativeTo: envBtn.bounds, of: envBtn, preferredEdge: .minY)
    onFetchEnvVars?(c.name) { [weak vc] vars in
        vc?.loadEnvVars(vars)
    }
}
```

- [ ] **Step 5: Build**

```bash
swift build
```

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBar/ContainersPanelViewController.swift
git commit -m "feat(ui): add Env button — opens env vars popover for selected container"
```

---

## Task 9: StatusBarController — wire new callbacks + update() calls

**Files:**
- Modify: `Sources/ColimaBar/StatusBarController.swift`

- [ ] **Step 1: Wire `onSetRestartPolicy`, `onInspect`, `onFetchEnvVars` in `setupContainersPopover()`**

After the existing `containersPanelVC.onPruneVolumes` block, add:

```swift
containersPanelVC.onSetRestartPolicy = { [weak self] policy, name, completion in
    self?.manager.setRestartPolicy(policy, container: name, completion: completion)
}
containersPanelVC.onInspect = { [weak self] name in
    self?.runInTerminal("docker inspect \(name)")
}
containersPanelVC.onFetchEnvVars = { [weak self] name, completion in
    self?.manager.fetchEnvVars(container: name, completion: completion)
}
```

- [ ] **Step 2: Pass `restartPolicies` in all `update()` calls**

In `updateContainersItem(_:)`, update the `update()` call:

```swift
// Before:
containersPanelVC.update(containers: containers, usage: lastState.usage, containerStats: lastState.containerStats)

// After:
containersPanelVC.update(containers: containers, usage: lastState.usage,
                         containerStats: lastState.containerStats,
                         restartPolicies: lastState.restartPolicies)
```

In `openContainersPanel()`, update the `update()` call:

```swift
// Before:
containersPanelVC.update(containers: lastState.containers, usage: lastState.usage, containerStats: lastState.containerStats)

// After:
containersPanelVC.update(containers: lastState.containers, usage: lastState.usage,
                         containerStats: lastState.containerStats,
                         restartPolicies: lastState.restartPolicies)
```

- [ ] **Step 3: Build**

```bash
swift build
```

- [ ] **Step 4: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all tests pass.

- [ ] **Step 5: Install and verify visually**

```bash
make install && open /Applications/ColimaBar.app
```

Verify:
- Right-click container row → full context menu appears with correct enabled states
- Context menu → Restart policy → submenu shows current policy with checkmark, selecting changes it
- Context menu → Filter by this image → search field fills with image name, list filters
- Context menu → Inspect → Terminal opens with `docker inspect <name>`
- Context menu → Open Port 8080 → browser opens http://localhost:8080
- Shell button → NSAlert dialog with pre-filled "sh" → confirm → Terminal opens with command
- Env button (enabled when container selected) → popover with KEY/VALUE table
- Restart column shows policy text (↺ always, ⚠ on-fail, ◎ unless, —)

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBar/StatusBarController.swift
git commit -m "feat(ui): wire onSetRestartPolicy, onInspect, onFetchEnvVars; pass restartPolicies to panel"
```
