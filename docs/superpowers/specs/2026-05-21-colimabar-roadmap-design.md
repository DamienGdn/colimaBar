# ColimaBar Roadmap — Design Spec
**Date:** 2026-05-21  
**Scope:** 5 features for the containers popover panel

---

## Overview

Five independent features extending ColimaBar's containers panel. All follow the existing two-layer architecture:

- **`ColimaBarCore`** — models, parsers, shell commands (Foundation only, testable)
- **`ColimaBar`** — AppKit UI only

No global refactor. Each feature is additive.

---

## Feature 1 — Health Check Status

### Goal
Show container health (healthy / unhealthy / starting) as a colored indicator in the containers table.

### Data model (`DockerContainer.swift`)

Add `HealthStatus` enum and derive it from the existing `status` string — no extra shell command needed. Docker embeds health in the `Status` field (e.g. `"Up 2 hours (healthy)"`).

```swift
public enum HealthStatus: String {
    case healthy, unhealthy, starting
}

// On DockerContainer:
public var health: HealthStatus? {
    if status.contains("(healthy)")          { return .healthy }
    if status.contains("(unhealthy)")        { return .unhealthy }
    if status.contains("(health: starting)") { return .starting }
    return nil
}
```

### UI (`ContainersPanelViewController.swift`)

- New column `"health"` (22px wide), inserted after the state column.
- Cell displays a filled circle: `●` green (healthy), red (unhealthy), yellow (starting), empty string (no health check configured).
- Column is not sortable.

---

## Feature 2 — Clickable Port URLs

### Goal
Each port number in the Ports column is a clickable link that opens `http://localhost:PORT` in the default browser.

### Data model (`DockerContainer.swift`)

New computed property:

```swift
public var hostPortNumbers: [Int] {
    hostPorts
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .compactMap { Int($0) }
}
```

### UI — `PortsCell: NSTableCellView`

Custom cell view with a horizontal `NSStackView` of `NSButton`s:
- Style: `.plain` bezel, blue tint, no border — visually a hyperlink.
- One button per port number, title = port string.
- Action: `NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!)`.
- If no ports: show a dim `–` label (same as current behavior).

The existing `"ports"` column keeps its identifier; only the cell view type changes.

---

## Feature 3 — CPU/RAM Sparklines

### Goal
Show a mini history graph for the selected container's CPU and RAM in the detail zone below the table.

### History buffer (`ContainersPanelViewController.swift`)

```swift
private var cpuHistory: [String: [Double]] = [:]   // % values, max 20 points
private var ramHistory: [String: [Double]] = [:]   // MiB values, max 20 points
```

Updated on each `update(containers:usage:containerStats:)` call: for each running container with stats, append to its buffer and drop leading elements when count > 20.

### `SparklineView.swift` (new file in `ColimaBar/`)

`NSView` subclass:
- Takes `values: [Double]` and `color: NSColor`.
- `draw(_:)` normalizes values to the view height and draws a filled `NSBezierPath` area chart.
- Empty / single-point input draws nothing.

### Detail zone layout

Replace the single `containerStatLbl: NSTextField` with:

```
┌─────────────────────────────────────────────────┐
│  my-container                                   │
│  CPU ▁▂▃▅▄▆▇▅▃▂ ·············· 12.4%           │
│  RAM ▃▃▄▄▄▅▅▄▄▄ ·············· 128 MB          │
└─────────────────────────────────────────────────┘
```

- Container name label (bold, 12pt)
- `SparklineView` CPU (height 28px) + value label right-aligned
- `SparklineView` RAM (height 28px) + value label right-aligned
- Total zone height: ~80px (up from 16px for the old label)
- Panel height: 500 → 560px

When no container is selected or the container is stopped: zone is hidden (zero-height collapse via constraint).

---

## Feature 4 — Image Management

### Data model — `DockerImage.swift` (new file in `ColimaBarCore/`)

```swift
public struct DockerImage: Equatable {
    public let id: String
    public let repository: String
    public let tag: String
    public let size: String      // raw string from docker, e.g. "245MB"
    public let created: String   // raw string, e.g. "3 weeks ago"
}

struct DockerImageJSON: Codable {
    let ID: String
    let Repository: String
    let Tag: String
    let Size: String
    let CreatedSince: String
}
```

Parser in `ColimaManager`:

```swift
public static func parseDockerImages(_ output: String) -> [DockerImage]
// Parses `docker images --format '{{json .}}'` NDJSON output
```

### ColimaManager additions

```swift
public func fetchImages(completion: @escaping ([DockerImage]) -> Void)
// docker images --format '{{json .}}'

public func deleteImage(_ id: String, completion: @escaping (Result<Void, Error>) -> Void)
// docker rmi <id>

public func pullImage(_ name: String, completion: @escaping (Result<Void, Error>) -> Void)
// docker pull <name>  — runs async, can be slow
```

### UI — Images tab

Tabs added to `ContainersPanelViewController` via `NSSegmentedControl` [Containers | Images | Volumes] at top of panel. Selected tab shows/hides the corresponding content `NSView`. The existing containers content becomes one of three content views.

Images tab layout:
- Table: columns Repository (200px), Tag (80px), Size (70px), Created (100px).
- Sortable by Repository and Size.
- Toolbar below table: text field (placeholder `nginx:latest`) + "Pull" button + "Delete" button (enabled when row selected).
- Pull shows a spinner/progress indicator inline; output/error shown in a label below.

---

## Feature 5 — Volume Management

### Data model — `DockerVolume.swift` (new file in `ColimaBarCore/`)

```swift
public struct DockerVolume: Equatable {
    public let name: String
    public let driver: String
    public let size: String    // e.g. "1.2GB" or "N/A"
}
```

Parser:

```swift
public static func parseDockerVolumes(_ dfOutput: String, _ lsOutput: String) -> [DockerVolume]
// Primary: parses `docker volume ls --format '{{json .}}'` (name + driver)
// Size: cross-references `docker system df -v` text output (tab-separated) via volume name
// If size unavailable: "N/A"
```

> Note: `docker system df -v` outputs tab-separated text (not JSON). Size is extracted by matching volume name in that output. On parse failure size = "N/A" — never crashes.

### ColimaManager additions

```swift
public func fetchVolumes(completion: @escaping ([DockerVolume]) -> Void)

public func pruneVolumes(completion: @escaping (Result<String, Error>) -> Void)
// docker volume prune -f
```

### UI — Volumes tab

Volumes tab layout:
- Table: columns Name (280px), Driver (80px), Size (80px).
- Button "🗑 Prune volumes…" below table, triggers confirmation `NSAlert` before executing.
- Prune result shown in a label ("Deleted N volumes, reclaimed X").

---

## File Change Summary

| File | Change |
|------|--------|
| `ColimaBarCore/DockerContainer.swift` | + `HealthStatus` enum, `health` property, `hostPortNumbers` property |
| `ColimaBarCore/DockerImage.swift` | **new** — `DockerImage` struct + `DockerImageJSON` |
| `ColimaBarCore/DockerVolume.swift` | **new** — `DockerVolume` struct |
| `ColimaBarCore/ColimaManager.swift` | + `parseDockerImages`, `parseDockerVolumes`, `fetchImages`, `deleteImage`, `pullImage`, `fetchVolumes`, `pruneVolumes` |
| `ColimaBar/SparklineView.swift` | **new** — `NSView` subclass for area charts |
| `ColimaBar/ContainersPanelViewController.swift` | + tab segmented control, health column, `PortsCell`, sparkline detail zone, history buffers, images tab view, volumes tab view |

`SettingsPanelViewController.swift` and `StatusBarController.swift` — **no changes** (hotkey feature removed).

---

## Out of Scope

- Global hotkey (removed per user request)
- Container health polling via `docker inspect` (parsed from existing `status` field only)
- Image search / autocomplete for pull
- Volume creation
