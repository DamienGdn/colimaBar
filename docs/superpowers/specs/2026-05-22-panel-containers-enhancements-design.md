# Panel Containers Enhancements — Design Spec
**Date:** 2026-05-22
**Scope:** Group A — 5 features improving the containers panel

---

## Overview

Five additive features to the existing containers panel. No global refactor. All follow the two-layer architecture:
- **`ColimaBarCore`** — Foundation, testable
- **`ColimaBar`** — AppKit UI only

---

## Feature 1 — Context Menu (right-click)

### Goal
Right-click any container row to access actions without selecting the row first.

### UI

`NSMenu` presented via `tableView(_:menuForEvent:)` (set `tableView.menu` to a bound `NSMenu`, override `menuWillOpen` to update item states based on the right-clicked row).

Menu items in order:

```
▶ Start              — disabled if container is running
■ Stop               — disabled if container is stopped/exited
↺ Restart            — disabled if container is stopped/exited
─── separator ───
Logs                 — opens `docker logs -f <name>` in Terminal
Shell…               — triggers the exec dialog (Feature 5)
─── separator ───
Copy ID              — copies full container ID to clipboard
Open Port 8080       — one item per exposed host port; opens http://localhost:<port>
                       (entire "Open Port" section omitted if no ports)
─── separator ───
Filter by this image — sets searchField to container.image, calls applyFilter()
─── separator ───
Restart policy ▶     — submenu: always / on-failure / unless-stopped / no
                       current policy shown with a checkmark
Inspect              — runs `docker inspect <name>` in Terminal
```

Right-click on empty table area: menu not shown (guard against row == -1).

### Implementation note
`NSTableView` has a `menu` property. Set it to a configured `NSMenu`. In `menuWillOpen(_:)`, identify the right-clicked row via `tableView.clickedRow` and update item enabled states + checkmarks accordingly.

---

## Feature 2 — Environment Variables Popover

### Goal
Show the environment variables of the selected container in a dedicated popover.

### Data model — `ColimaManager`

```swift
public func fetchEnvVars(container: String,
                         completion: @escaping ([String]) -> Void)
// docker inspect --format '{{json .Config.Env}}' <name>
// Returns array of "KEY=VALUE" strings. Empty array on error.
```

### UI

New **"Env"** button added to the action bar (between Shell and the end), enabled only when a container is selected. Clic → opens `EnvVarsViewController` in a `NSPopover` (detached from the Env button).

**`EnvVarsViewController`** (new file `Sources/ColimaBar/EnvVarsViewController.swift`):
- `NSTextField` header: container name
- `NSScrollView` + `NSTableView` with 2 columns: Key (180px) and Value (300px)
- "Copy all" button: copies all `KEY=VALUE` lines joined by `\n` to clipboard
- Shows "Loading…" while fetching, "No env vars" if empty result
- Popover size: 500 × 320

Parsing: split each `"KEY=VALUE"` string on the first `=` to separate key and value.

---

## Feature 3 — Restart Policy (display + configurable)

### Goal
Show each container's restart policy in the table and allow changing it via context menu.

### Data model

**`ColimaManager`** additions:

```swift
// Parses `docker inspect --format '{{slice .Name 1}}\t{{.HostConfig.RestartPolicy.Name}}' <id>...`
public static func parseRestartPolicies(_ output: String) -> [String: String]
// Returns [containerName: policyName]

public func setRestartPolicy(_ policy: String, container: String,
                             completion: @escaping (Result<Void, Error>) -> Void)
// docker update --restart=<policy> <container>
```

**`ColimaAppState`**: add field `restartPolicies: [String: String] = [:]`

**`fetchStateSync()`**: when running and containers list is non-empty, after fetching container list, run:
```
docker inspect --format '{{slice .Name 1}}\t{{.HostConfig.RestartPolicy.Name}}' <id1> <id2> ...
```
Pass all container IDs at once. Guard: skip if `containers.isEmpty`. Parse → store in `ColimaAppState.restartPolicies`.

### UI

New column `"restart"` (70px) inserted after `"status"` in the containers table. Cell displays:

| Policy value | Displayed |
|---|---|
| `always` | `↺ always` |
| `on-failure` | `⚠ on-fail` |
| `unless-stopped` | `◎ unless` |
| `no` or empty | `—` |

Text color: `.secondaryLabelColor` for all, `.tertiaryLabelColor` for `—`.

**Changing policy**: "Restart policy ▶" in the context menu → submenu with 4 items (always / on-failure / unless-stopped / no). Current policy shown with `NSControlStateValue.on` checkmark. Selecting an item calls `onSetRestartPolicy?(policy, containerName)` callback → `manager.setRestartPolicy` → re-fetch state.

New callback on `ContainersPanelViewController`:
```swift
var onSetRestartPolicy: ((String, String, @escaping (Result<Void, Error>) -> Void) -> Void)?
```

---

## Feature 4 — Quick Filter by Image

### Goal
One-click to filter the container list to all containers sharing the same image.

### Implementation

Added as a menu item in the context menu (Feature 1): **"Filter by this image"**.

Action: `searchField.stringValue = container.image` → `searchChanged()`.

No new code beyond the menu item wiring — `applyFilter()` already handles image name in the search field since it filters on `container.name`, but the search must be updated to also match `container.image`.

**Required change to `applyFilter()`**: extend the filter predicate to match both name AND image:
```swift
base.filter {
    $0.name.localizedCaseInsensitiveContains(searchText) ||
    $0.image.localizedCaseInsensitiveContains(searchText)
}
```

---

## Feature 5 — Custom Exec Command (dialog)

### Goal
Allow the user to specify the command run by Shell instead of the hardcoded `sh`.

### UI

Shell button action → `NSAlert` with:
- `messageText`: `"Shell into \(containerName)"`
- `informativeText`: `"Command to execute:"`
- Accessory view: `NSTextField` pre-filled `"sh"`, width 300px
- Buttons: "Run" (default) / "Cancel"
- On "Run": execute `docker exec -it <name> <command>` in Terminal via osascript
- Empty command: defaults to `sh`

No persistent storage for the last command (YAGNI).

---

## File Change Summary

| File | Change |
|---|---|
| `ColimaBarCore/ColimaState.swift` | + `restartPolicies: [String: String]` on `ColimaAppState` |
| `ColimaBarCore/ColimaManager.swift` | + `parseRestartPolicies`, `fetchEnvVars`, `setRestartPolicy`; update `fetchStateSync` |
| `ColimaBar/EnvVarsViewController.swift` | **new** — env vars popover |
| `ColimaBar/ContainersPanelViewController.swift` | + context menu, restart column, Env button, exec dialog, image filter fix |
| `ColimaBar/StatusBarController.swift` | + wire `onSetRestartPolicy` callback |
| `Tests/ColimaBarTests/ColimaStateTests.swift` | + `parseRestartPolicies` tests |
| `Tests/ColimaBarTests/main.swift` | + register new tests |

---

## Out of Scope

- Restart policy display for stopped containers (docker inspect still works, but low value)
- Env vars search/filter within the popover
- Persistent last-used exec command
