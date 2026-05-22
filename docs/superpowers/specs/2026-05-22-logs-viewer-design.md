# Logs Viewer — Design Spec
**Date:** 2026-05-22
**Scope:** Group B — inline log streaming in a floating NSWindow

---

## Goal

Replace the current `docker logs -f <name>` Terminal launch with an in-app floating window that streams logs in real time.

---

## Architecture

**New file:** `Sources/ColimaBar/LogsWindowController.swift`

Singleton held by `StatusBarController`. Manages one reusable `NSWindow`.

---

## Window

- Size: 700 × 450, `styleMask`: `.titled .closable .resizable .miniaturizable`
- Title: `"ColimaBar — <containerName> logs"`
- Content: `NSScrollView` + `NSTextView` (read-only, monospaced 12pt, black bg / system text color)
- Toolbar row (horizontal NSStackView above scroll view):
  - `NSTextField` label — container name (bold)
  - Toggle button `"▶ Follow"` / `"■ Stop"` — starts/stops streaming
  - `NSButton` `"Clear"` — clears text view
- Auto-scroll to bottom when Follow is active and new text arrives

---

## Streaming

Command: `docker logs --tail 200 -f <containerName>`

- Run via `Foundation.Process` with stdout `Pipe`
- `fileHandleForReading.readabilityHandler` fires on background thread → append to `NSTextView` on main thread
- Max 5 000 lines in buffer — when exceeded, remove first 1 000 lines (trim top of text view)
- On new container: `stopStreaming()` → clear → start new process
- On window close: stop streaming (process terminated), window hides (not destroyed — reused on next open)

```swift
public func show(containerName: String, dockerPath: String) {
    stopStreaming()
    window.title = "ColimaBar — \(containerName) logs"
    containerLabel.stringValue = containerName
    clearText()
    startStreaming(containerName: containerName, dockerPath: dockerPath)
    window.makeKeyAndOrderFront(nil)
}
```

---

## Integration

`StatusBarController` holds `private let logsWindowController = LogsWindowController()`.

Replace `openLogsTerminal(containerName:)`:

```swift
// Before:
private func openLogsTerminal(containerName name: String) {
    runInTerminal("docker logs -f \(name)")
}

// After:
private func openLogsTerminal(containerName name: String) {
    logsWindowController.show(containerName: name, dockerPath: "/opt/homebrew/bin/docker")
}
```

`onLogs` callback and `ContainersPanelViewController` unchanged.

---

## Out of Scope

- Multiple simultaneous log windows (one window, reused)
- Log filtering / search
- Log export
- Stderr separate from stdout
