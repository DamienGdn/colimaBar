# Networks & Compose Tabs — Design Spec
**Date:** 2026-05-22
**Scope:** Group C — Networks tab + Compose grouped view

---

## Overview

Two new tabs added to the containers panel (making 5 total: Containers | Images | Volumes | Networks | Compose). Both are read-only views with minimal actions.

---

## C1 — Networks Tab

### Goal
List Docker networks with driver and scope. Prune unused networks.

### Data model — `DockerNetwork.swift` (new in ColimaBarCore)

```swift
public struct DockerNetwork: Equatable {
    public let id: String
    public let name: String
    public let driver: String
    public let scope: String   // "local" or "swarm"
}

struct DockerNetworkJSON: Codable {
    let ID: String
    let Name: String
    let Driver: String
    let Scope: String
}
```

### ColimaManager additions

```swift
public static func parseDockerNetworks(_ output: String) -> [DockerNetwork]
// Parses `docker network ls --format '{{json .}}'` NDJSON

public func fetchNetworks(completion: @escaping ([DockerNetwork]) -> Void)
// docker network ls --format '{{json .}}'

public func pruneNetworks(completion: @escaping (Result<String, Error>) -> Void)
// docker network prune -f
```

### UI — Networks tab

Table: Name (220px), Driver (80px), Scope (70px)
Button: "🗑 Prune réseaux…" with NSAlert confirmation.
Status label below button.

---

## C2 — Compose Tab

### Goal
Show containers grouped by their Docker Compose project. Derived from container labels — no extra `docker compose` command needed.

### Data model — `DockerContainer`

Add `labels: String` to `DockerContainerJSON` (optional, `String?`):
```swift
let Labels: String?  // "com.docker.compose.project=myapp,com.docker.compose.service=web,..."
```

Add `labels: String` and `composeProject: String?` to `DockerContainer`:
```swift
public let labels: String   // raw labels string, empty if none

public var composeProject: String? {
    // Extract "com.docker.compose.project=<name>" from labels
    labels.components(separatedBy: ",")
        .first { $0.hasPrefix("com.docker.compose.project=") }
        .flatMap { kv -> String? in
            let v = String(kv.dropFirst("com.docker.compose.project=".count))
            return v.isEmpty ? nil : v
        }
}
```

`parseDockerContainers` passes `c.Labels ?? ""` as the `labels` field when constructing `DockerContainer`.

### UI — Compose tab

Table with 3 columns: Project (240px), Containers (80px, total count), Status (160px).

Status column value:
- All containers running → "✅ All running"
- None running → "⛔ Stopped"
- Mix → "⚠ \(running)/\(total) running"

Rows: one per distinct project. Containers not in any project are not shown (they appear in the Containers tab). No actions — read-only.

Data is derived from `allContainers` (already held by ContainersPanelViewController) grouped by `composeProject`. Updated whenever `update()` is called.

---

## Panel tab bar

The segmented control changes from 3 segments to 5:
`[Containers | Images | Volumes | Networks | Compose]`

Two new content views added: `networksContentView` and `composeContentView`.

---

## File Change Summary

| File | Change |
|---|---|
| `ColimaBarCore/DockerNetwork.swift` | **new** — struct + JSON helper |
| `ColimaBarCore/DockerContainer.swift` | + `labels` field + `composeProject` computed property |
| `ColimaBarCore/ColimaManager.swift` | + `parseDockerNetworks`, `fetchNetworks`, `pruneNetworks` |
| `ColimaBar/ContainersPanelViewController.swift` | + 2 tabs, Networks UI, Compose UI, callbacks |
| `ColimaBar/StatusBarController.swift` | + wire `onFetchNetworks`, `onPruneNetworks` |
| `Tests/ColimaBarTests/ColimaStateTests.swift` | + parseDockerNetworks tests + composeProject tests |
| `Tests/ColimaBarTests/main.swift` | + register new tests |

---

## Out of Scope

- `docker compose up/down` actions (would need compose file path)
- Network connect/disconnect
- Network creation
- Compose service logs per service
