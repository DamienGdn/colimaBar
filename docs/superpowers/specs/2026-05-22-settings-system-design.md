# Settings & System Enhancements — Design Spec
**Date:** 2026-05-22
**Scope:** Group D — 5 system/settings features

---

## D1 — Polling Interval Presets

### Goal
Replace the hardcoded 5s/30s polling with a user-selectable preset.

### Data model — `ColimaConfig`

```swift
public enum PollingPreset: String, CaseIterable {
    case fast   = "fast"    // 2s running / 10s stopped
    case normal = "normal"  // 5s running / 30s stopped (default)
    case slow   = "slow"    // 15s running / 60s stopped
    
    public var runningInterval: TimeInterval {
        switch self { case .fast: return 2; case .normal: return 5; case .slow: return 15 }
    }
    public var stoppedInterval: TimeInterval {
        switch self { case .fast: return 10; case .normal: return 30; case .slow: return 60 }
    }
}

// ColimaConfig:
public static var pollingPreset: PollingPreset { get/set via UserDefaults "colima.pollingPreset" }
```

### ColimaManager

`pollOnce()` reads `ColimaConfig.pollingPreset.runningInterval / .stoppedInterval` instead of literals 5.0 / 30.0.

### UI — SettingsPanelViewController

3-segment `NSSegmentedControl` [Rapide | Normal | Lent] in Settings panel, below existing controls. Persisted immediately on change. Takes effect on next poll cycle (no restart needed).

---

## D2 — Resource Alerts (fixed thresholds)

### Goal
Fire a system notification when CPU > 80% or RAM > 90% for 2 consecutive polling cycles.

### StatusBarController

Track alert state:
```swift
private var consecutiveHighCPU = 0
private var consecutiveHighRAM = 0
```

In `update(state:)`, after updating containers:
- If `state.usage?.cpuPercent ?? 0 > 80`: `consecutiveHighCPU += 1` else reset to 0
- If `state.usage?.memUsedPercent ?? 0 > 90`: `consecutiveHighRAM += 1` else reset to 0
- If `consecutiveHighCPU == 2`: fire notification "CPU élevé / High CPU — X%", reset counter
- If `consecutiveHighRAM == 2`: fire notification "RAM élevée / High RAM — X%", reset counter

Use existing `AppDelegate.showError(message:)` for notifications.

---

## D3 — Compact Mode (container count in menu bar)

### Goal
Optionally show running container count next to the icon in the menu bar.

### ColimaConfig

```swift
public static var compactModeEnabled: Bool { get/set via UserDefaults "colima.compactMode" }
```

### StatusBarController — `updateIcon`

When compact mode enabled and Colima is running:
```swift
button.title = " ▶\(runningContainerCount)"
button.imagePosition = .imageLeft
```
When disabled or stopped: `button.title = ""`.

### UI — SettingsPanelViewController

`NSButton` checkbox "Afficher le nombre de containers / Show container count" in Settings.

---

## D4 — Multi-Instance Switcher

### Goal
Quick instance switch from the menu bar without going to Settings.

### ColimaManager

```swift
public func listInstances(completion: @escaping ([String]) -> Void)
// colima list --json → parse all instance names
```

### StatusBarController

New menu item "Instance ▶" with a dynamic `NSMenu` submenu. On menu open (`menuWillOpen` or `menuNeedsUpdate`): call `manager.listInstances` → rebuild submenu with one item per instance. Current instance gets a checkmark. Selecting an instance: sets `ColimaConfig.activeInstanceName`, triggers re-poll.

Submenu appears between Stop and the separator before Portainer.

---

## D5 — Disk Resize

### Goal
Allow resizing Colima disk from Settings without manual CLI.

### SettingsPanelViewController

Below the existing Disk stepper/presets, add a "Resize disk…" `NSButton`. Enabled only when Colima is running.

On click:
1. `NSAlert` — "Resizing disk requires restarting Colima. This may take 30–60 seconds. Continue?"
2. On confirm: call `onResizeDisk?()` callback → StatusBarController runs stop + start with new disk size
3. Status label shows progress.

### StatusBarController

```swift
settingsPanelVC.onResizeDisk = { [weak self] in
    self?.restartWithNewConfig()  // already exists — stop then start with current ColimaConfig values
}
```

`restartWithNewConfig()` already exists and uses `ColimaConfig.desiredDiskGB` — no new logic needed.

---

## File Change Summary

| File | Change |
|---|---|
| `ColimaBarCore/ColimaConfig.swift` | + `PollingPreset` enum + `pollingPreset` + `compactModeEnabled` |
| `ColimaBarCore/ColimaManager.swift` | + `listInstances`; update `pollOnce` to use preset intervals |
| `ColimaBar/StatusBarController.swift` | + resource alert tracking; compact mode icon; instance submenu |
| `ColimaBar/SettingsPanelViewController.swift` | + polling preset control; compact mode toggle; disk resize button |

---

## Out of Scope

- Per-container CPU/RAM alert thresholds (fixed at 80%/90%)
- Alert snooze / dismiss
- Disk shrink (only enlarge supported by Colima)
