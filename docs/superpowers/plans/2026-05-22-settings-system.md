# Settings & System Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable polling presets, resource alerts, compact mode, multi-instance switcher, and disk resize to ColimaBar.

**Architecture:** Core changes in ColimaConfig + ColimaManager (testable); UI changes in StatusBarController + SettingsPanelViewController (AppKit only). No new files.

**Tech Stack:** Swift 5.9, AppKit, Foundation, UserDefaults, SPM, macOS 13+

---

## Task 1: ColimaConfig — PollingPreset + compactModeEnabled

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaConfig.swift`

- [ ] **Step 1: Add `PollingPreset` enum and two new config properties**

Append to `Sources/ColimaBarCore/ColimaConfig.swift`, after the `ColimaProfile` struct:

```swift
public enum PollingPreset: String, CaseIterable {
    case fast   = "fast"   // 2s running / 10s stopped
    case normal = "normal" // 5s running / 30s stopped (default)
    case slow   = "slow"   // 15s running / 60s stopped

    public var runningInterval: TimeInterval {
        switch self { case .fast: return 2; case .normal: return 5; case .slow: return 15 }
    }
    public var stoppedInterval: TimeInterval {
        switch self { case .fast: return 10; case .normal: return 30; case .slow: return 60 }
    }
    public var label: String {
        switch self {
        case .fast:   return L.t("Rapide", "Fast")
        case .normal: return L.t("Normal", "Normal")
        case .slow:   return L.t("Lent", "Slow")
        }
    }
}
```

And add two new properties inside `ColimaConfig` (after `activeInstanceName`):

```swift
private static let pollingKey     = "colima.pollingPreset"
private static let compactModeKey = "colima.compactMode"

public static var pollingPreset: PollingPreset {
    get {
        let raw = UserDefaults.standard.string(forKey: pollingKey) ?? ""
        return PollingPreset(rawValue: raw) ?? .normal
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: pollingKey) }
}

public static var compactModeEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: compactModeKey) }
    set { UserDefaults.standard.set(newValue, forKey: compactModeKey) }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

- [ ] **Step 3: Commit**

```bash
git add Sources/ColimaBarCore/ColimaConfig.swift
git commit -m "feat(core): add PollingPreset enum and compactModeEnabled to ColimaConfig"
```

---

## Task 2: ColimaManager — use preset intervals + listInstances

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`

- [ ] **Step 1: Update `pollOnce()` to use preset intervals**

In `pollOnce()`, replace the hardcoded intervals:

```swift
// Before:
let interval: TimeInterval = self.isCurrentlyRunning ? 5.0 : 30.0

// After:
let preset = ColimaConfig.pollingPreset
let interval: TimeInterval = self.isCurrentlyRunning ? preset.runningInterval : preset.stoppedInterval
```

- [ ] **Step 2: Add `parseInstanceNames` static parser**

In the `// MARK: - Static parsers` section, add after `parseRestartPolicies`:

```swift
// Parses all instance names from `colima list --json` NDJSON output.
public static func parseInstanceNames(_ output: String) -> [String] {
    let names = output.components(separatedBy: .newlines)
        .filter { !$0.isEmpty }
        .compactMap { line -> String? in
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(ColimaListEntry.self, from: data)
            else { return nil }
            return entry.name
        }
    return names.isEmpty ? ["default"] : names
}
```

- [ ] **Step 3: Add `listInstances` action**

In the `// MARK: - Actions` section, add after `fetchEnvVars`:

```swift
public func listInstances(completion: @escaping ([String]) -> Void) {
    DispatchQueue.global(qos: .background).async {
        let result = self.shell.run(self.colimaPath, args: ["list", "--json"])
        let names = Self.parseInstanceNames(result.output)
        DispatchQueue.main.async { completion(names) }
    }
}
```

- [ ] **Step 4: Build**

```bash
swift build
```

- [ ] **Step 5: Run tests**

```bash
swift run ColimaBarTests
```

Expected: all 85 tests pass (no test changes needed — new parsers follow existing patterns).

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBarCore/ColimaManager.swift
git commit -m "feat(core): use PollingPreset in pollOnce, add listInstances + parseInstanceNames"
```

---

## Task 3: StatusBarController — alerts + compact mode + instance submenu

**Files:**
- Modify: `Sources/ColimaBar/StatusBarController.swift`

- [ ] **Step 1: Add alert tracking properties and instance cache**

Add near the top of the class, after `previousContainerStates`:

```swift
private var consecutiveHighCPU   = 0
private var consecutiveHighRAM   = 0
private var lastKnownInstances:  [String] = ["default"]
private var instanceSubmenuItem: NSMenuItem?
```

- [ ] **Step 2: Add resource alert logic in `update(state:)`**

In `update(state:)`, after `updateMenuItems(state: state)`, add:

```swift
// Resource alerts — fire after 2 consecutive cycles above threshold
if let u = state.usage {
    if u.cpuPercent > 80 {
        consecutiveHighCPU += 1
        if consecutiveHighCPU == 2 {
            let msg = L.t("CPU élevé : \(String(format: "%.0f%%", u.cpuPercent))",
                          "High CPU: \(String(format: "%.0f%%", u.cpuPercent))")
            (NSApp.delegate as? AppDelegate)?.showError(msg)
            consecutiveHighCPU = 0
        }
    } else { consecutiveHighCPU = 0 }

    if u.memUsedPercent > 90 {
        consecutiveHighRAM += 1
        if consecutiveHighRAM == 2 {
            let msg = L.t("RAM élevée : \(String(format: "%.0f%%", u.memUsedPercent))",
                          "High RAM: \(String(format: "%.0f%%", u.memUsedPercent))")
            (NSApp.delegate as? AppDelegate)?.showError(msg)
            consecutiveHighRAM = 0
        }
    } else { consecutiveHighRAM = 0 }
}

// Refresh instance list cache when running
if case .running = state.colima {
    manager.listInstances { [weak self] names in
        self?.lastKnownInstances = names
        self?.rebuildInstanceSubmenu()
    }
}
```

- [ ] **Step 3: Update `updateIcon` for compact mode**

Replace the existing `updateIcon` method:

```swift
private func updateIcon(colima: ColimaRunningState) {
    guard let button = statusItem.button else { return }
    let bubbleColor: NSColor
    switch colima {
    case .running:           bubbleColor = .systemGreen
    case .stopped, .unknown: bubbleColor = .white
    case .transitioning:     bubbleColor = .systemOrange
    }
    button.image = colimaIcon(bubbleColor: bubbleColor)

    if ColimaConfig.compactModeEnabled, case .running = colima {
        let running = lastState.containers.filter { $0.isRunning }.count
        button.title         = " ▶\(running)"
        button.imagePosition = .imageLeft
    } else {
        button.title         = ""
        button.imagePosition = .imageOnly
    }
}
```

- [ ] **Step 4: Add instance submenu to `buildMenu()`**

In `buildMenu()`, after `stopItem` is added to the menu (before the first separator after stop), add:

```swift
let instanceItem = NSMenuItem(title: L.t("Instance", "Instance"), action: nil, keyEquivalent: "")
instanceItem.submenu = NSMenu()
instanceSubmenuItem  = instanceItem
menu.addItem(instanceItem)
```

Then add `rebuildInstanceSubmenu()` and `switchInstance(_:)` methods:

```swift
private func rebuildInstanceSubmenu() {
    guard let submenu = instanceSubmenuItem?.submenu else { return }
    submenu.removeAllItems()
    let current = ColimaConfig.activeInstanceName
    for name in lastKnownInstances {
        let item = NSMenuItem(title: name, action: #selector(switchInstance(_:)), keyEquivalent: "")
        item.target = self
        item.state  = name == current ? .on : .off
        submenu.addItem(item)
    }
}

@objc private func switchInstance(_ sender: NSMenuItem) {
    let name = sender.title
    guard name != ColimaConfig.activeInstanceName else { return }
    ColimaConfig.activeInstanceName = name
    manager.stopPolling()
    manager.startPolling()
}
```

- [ ] **Step 5: Wire `onResizeDisk` in `setupSettingsPopover()`**

Add after `settingsPanelVC.onApplyConfig = { ... }`:

```swift
settingsPanelVC.onResizeDisk = { [weak self] in
    self?.restartWithNewConfig()
}
```

- [ ] **Step 6: Build**

```bash
swift build
```

- [ ] **Step 7: Commit**

```bash
git add Sources/ColimaBar/StatusBarController.swift
git commit -m "feat(ui): resource alerts, compact mode, instance switcher submenu, disk resize wiring"
```

---

## Task 4: SettingsPanelViewController — polling preset + compact mode + disk resize

**Files:**
- Modify: `Sources/ColimaBar/SettingsPanelViewController.swift`

- [ ] **Step 1: Add new properties and callback**

Add to the class properties block:

```swift
var onResizeDisk: (() -> Void)?

private var pollingControl: NSSegmentedControl!
private var compactCheck:   NSButton!
private var resizeDiskBtn:  NSButton!
```

- [ ] **Step 2: Increase view height and add new controls in `buildUI()`**

Change `loadView()` height from 420 to 520:

```swift
override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 520))
}
```

In `buildUI()`, after the disk control line (`outer.addArrangedSubview(diskControl)`), add the resize button before `outer.addArrangedSubview(sep())`:

```swift
resizeDiskBtn = NSButton(
    title: L.t("Redimensionner le disque…", "Resize disk…"),
    target: self, action: #selector(resizeDiskTapped))
resizeDiskBtn.bezelStyle  = .rounded
resizeDiskBtn.controlSize = .small
outer.addArrangedSubview(resizeDiskBtn)
```

After the language section (`outer.addArrangedSubview(sep())`), add the polling and compact controls:

```swift
outer.addArrangedSubview(header(L.t("Intervalle de polling", "Polling interval")))
pollingControl = seg(PollingPreset.allCases.map { $0.label }, #selector(pollingChanged(_:)))
outer.addArrangedSubview(pollingControl)
outer.addArrangedSubview(sep())

compactCheck = NSButton(
    checkboxWithTitle: L.t("Afficher le nombre de containers actifs", "Show running container count"),
    target: self, action: #selector(compactToggled))
compactCheck.controlSize = .small
outer.addArrangedSubview(compactCheck)
```

- [ ] **Step 3: Update `syncControls()` for new controls**

Add at the end of `syncControls()`:

```swift
let preset = ColimaConfig.pollingPreset
for (i, p) in PollingPreset.allCases.enumerated() {
    pollingControl.setSelected(p == preset, forSegment: i)
}
compactCheck.state     = ColimaConfig.compactModeEnabled ? .on : .off
resizeDiskBtn.isEnabled = isColimaRunning
```

- [ ] **Step 4: Add new action methods**

Add after `loginToggled()`:

```swift
@objc private func pollingChanged(_ sender: NSSegmentedControl) {
    ColimaConfig.pollingPreset = PollingPreset.allCases[sender.selectedSegment]
}

@objc private func compactToggled() {
    ColimaConfig.compactModeEnabled = compactCheck.state == .on
}

@objc private func resizeDiskTapped() {
    let alert = NSAlert()
    alert.messageText     = L.t("Redimensionner le disque", "Resize disk")
    alert.informativeText = L.t(
        "Le disque sera redimensionné à \(ColimaConfig.desiredDiskGB) GB. Colima va redémarrer (30–60 s).",
        "Disk will be resized to \(ColimaConfig.desiredDiskGB) GB. Colima will restart (30–60 s).")
    alert.alertStyle = .warning
    alert.addButton(withTitle: L.t("Redimensionner", "Resize"))
    alert.addButton(withTitle: L.t("Annuler", "Cancel"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    onResizeDisk?()
}
```

- [ ] **Step 5: Build**

```bash
swift build
```

- [ ] **Step 6: Update popover height in StatusBarController**

`SettingsPopover` contentSize must also be updated. In `setupSettingsPopover()`:

```swift
// Before:
settingsPopover.contentSize = NSSize(width: 420, height: 420)
// After:
settingsPopover.contentSize = NSSize(width: 420, height: 520)
```

- [ ] **Step 7: Build + run tests + install**

```bash
swift build
swift run ColimaBarTests
make install && open /Applications/ColimaBar.app
```

Expected: 85 tests pass.

Verify in app:
- Settings → "Intervalle de polling" shows Rapide/Normal/Lent
- Settings → checkbox "Afficher le nombre de containers actifs" → icon shows `▶ N`
- Settings → disk section → "Redimensionner le disque…" button (enabled only when Colima running)
- Menu bar → "Instance" submenu shows current instance(s) with checkmark
- When CPU>80% for 2 polls → system notification

- [ ] **Step 8: Commit**

```bash
git add Sources/ColimaBar/SettingsPanelViewController.swift Sources/ColimaBar/StatusBarController.swift
git commit -m "feat(ui): polling preset, compact mode, disk resize button in Settings"
```
