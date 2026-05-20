# ColimaBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App macOS native dans la barre de menus pour démarrer/arrêter Colima et gérer Portainer, sans Docker Desktop.

**Architecture:** Swift Package Manager avec deux targets — `ColimaBarCore` (library pure Foundation, testable) et `ColimaBar` (executable AppKit). `ColimaBarCore` contient le shell runner, le parsing d'état, et le manager. `ColimaBar` contient NSStatusItem, AppDelegate, notifications. Un Makefile package en `.app` et installe dans `/Applications`.

**Tech Stack:** Swift 5.9, macOS 13+, AppKit, ServiceManagement (SMAppService), UserNotifications, Swift Package Manager, XCTest.

---

## File Map

| Fichier | Rôle |
|---------|------|
| `Package.swift` | Déclaration SPM : ColimaBarCore + ColimaBar + tests |
| `Makefile` | build → bundle → codesign → install |
| `Resources/Info.plist` | LSUIElement=true, bundle ID, min OS |
| `Sources/ColimaBarCore/ShellRunner.swift` | Protocol `ShellRunner` + `ProcessShellRunner` |
| `Sources/ColimaBarCore/ColimaState.swift` | `ColimaAppState`, `ColimaRunningState`, `ColimaListEntry` |
| `Sources/ColimaBarCore/ColimaConfig.swift` | Presets CPU/mémoire, persistance UserDefaults |
| `Sources/ColimaBarCore/ColimaManager.swift` | Polling, parsers statiques, actions start/stop/install |
| `Sources/ColimaBar/main.swift` | Entry point NSApplication |
| `Sources/ColimaBar/AppDelegate.swift` | Wire manager + controller, SMAppService, notifications |
| `Sources/ColimaBar/StatusBarController.swift` | NSStatusItem, NSMenu, icône colorée, mises à jour UI |
| `Tests/ColimaBarTests/ColimaStateTests.swift` | Tests parseurs JSON + détection Portainer + fetchStateSync |

---

## Task 1: Scaffold projet

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `Resources/Info.plist`
- Create: `Sources/ColimaBarCore/.gitkeep`
- Create: `Sources/ColimaBar/.gitkeep`
- Create: `Tests/ColimaBarTests/.gitkeep`

- [ ] **Step 1: Créer la structure de répertoires**

```bash
cd /Users/d.guesdon/Documents/projets/tools/colima
mkdir -p Sources/ColimaBarCore Sources/ColimaBar Tests/ColimaBarTests Resources
```

- [ ] **Step 2: Écrire Package.swift**

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ColimaBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ColimaBarCore",
            path: "Sources/ColimaBarCore"
        ),
        .executableTarget(
            name: "ColimaBar",
            dependencies: ["ColimaBarCore"],
            path: "Sources/ColimaBar"
        ),
        .testTarget(
            name: "ColimaBarTests",
            dependencies: ["ColimaBarCore"],
            path: "Tests/ColimaBarTests"
        )
    ]
)
```

- [ ] **Step 3: Écrire Resources/Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.local.ColimaBar</string>
    <key>CFBundleName</key>
    <string>ColimaBar</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>ColimaBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
```

- [ ] **Step 4: Écrire Makefile**

```makefile
BINARY      = ColimaBar
APP         = ColimaBar.app
INSTALL_DIR = /Applications

.PHONY: build bundle install clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/$(BINARY) $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	codesign --force --sign - $(APP)
	@echo "Bundle: $(APP)"

install: bundle
	rm -rf $(INSTALL_DIR)/$(APP)
	cp -r $(APP) $(INSTALL_DIR)/
	@echo "Installed: $(INSTALL_DIR)/$(APP)"

open: install
	open $(INSTALL_DIR)/$(APP)

clean:
	swift package clean
	rm -rf $(APP)
```

- [ ] **Step 5: Vérifier que SPM résout le package**

```bash
swift package resolve
```

Expected: pas d'erreur, dossier `.build` créé.

- [ ] **Step 6: Commit**

```bash
git init
git add Package.swift Makefile Resources/Info.plist
git commit -m "chore: scaffold SPM project structure"
```

---

## Task 2: ShellRunner

**Files:**
- Create: `Sources/ColimaBarCore/ShellRunner.swift`

- [ ] **Step 1: Écrire ShellRunner.swift**

```swift
import Foundation

public protocol ShellRunner: AnyObject {
    func run(_ executable: String, args: [String]) -> (output: String, error: String, exitCode: Int32)
}

public final class ProcessShellRunner: ShellRunner {
    public init() {}

    public func run(_ executable: String, args: [String]) -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ("", error.localizedDescription, -1)
        }
        process.waitUntilExit()

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (out, err, process.terminationStatus)
    }
}
```

- [ ] **Step 2: Vérifier que le package compile**

```bash
swift build 2>&1 | head -20
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/ColimaBarCore/ShellRunner.swift
git commit -m "feat: add ShellRunner protocol and ProcessShellRunner"
```

---

## Task 3: ColimaState + tests parseurs

**Files:**
- Create: `Sources/ColimaBarCore/ColimaState.swift`
- Create: `Tests/ColimaBarTests/ColimaStateTests.swift`

- [ ] **Step 1: Écrire le test en premier**

```swift
// Tests/ColimaBarTests/ColimaStateTests.swift
import XCTest
@testable import ColimaBarCore

final class ColimaStateTests: XCTestCase {

    // MARK: - parseListJSON

    func test_parseListJSON_running() {
        let json = """
        {"name":"default","status":"Running","arch":"aarch64","cpus":2,"memory":4294967296,"disk":10737418240}
        """
        let entry = ColimaManager.parseListJSON(json)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.status, "Running")
        XCTAssertEqual(entry?.cpus, 2)
        XCTAssertEqual(entry?.memory, 4_294_967_296)
    }

    func test_parseListJSON_stopped() {
        let json = """
        {"name":"default","status":"Stopped","arch":"aarch64","cpus":4,"memory":8589934592,"disk":10737418240}
        """
        let entry = ColimaManager.parseListJSON(json)
        XCTAssertEqual(entry?.status, "Stopped")
        XCTAssertEqual(entry?.cpus, 4)
    }

    func test_parseListJSON_invalid_returnsNil() {
        XCTAssertNil(ColimaManager.parseListJSON("not json"))
        XCTAssertNil(ColimaManager.parseListJSON(""))
        XCTAssertNil(ColimaManager.parseListJSON("{}"))
    }

    func test_memoryGB_conversion() {
        // 4294967296 bytes = 4.0 GB
        let memBytes: Int64 = 4_294_967_296
        let gb = Double(memBytes) / 1_073_741_824
        XCTAssertEqual(gb, 4.0, accuracy: 0.01)
    }

    // MARK: - portainerExistsInOutput

    func test_portainerExists_found() {
        XCTAssertTrue(ColimaManager.portainerExistsInOutput("portainer"))
        XCTAssertTrue(ColimaManager.portainerExistsInOutput("portainer\n"))
        XCTAssertTrue(ColimaManager.portainerExistsInOutput("  portainer  "))
    }

    func test_portainerExists_notFound() {
        XCTAssertFalse(ColimaManager.portainerExistsInOutput(""))
        XCTAssertFalse(ColimaManager.portainerExistsInOutput("nginx"))
        XCTAssertFalse(ColimaManager.portainerExistsInOutput("portainer-agent"))
    }
}
```

- [ ] **Step 2: Lancer les tests — vérifier qu'ils échouent**

```bash
swift test 2>&1 | tail -20
```

Expected: erreur de compilation (`ColimaManager` not found).

- [ ] **Step 3: Écrire ColimaState.swift**

```swift
// Sources/ColimaBarCore/ColimaState.swift
import Foundation

public enum ColimaRunningState: Equatable {
    case running
    case stopped
    case transitioning(String)
    case unknown
}

public struct ColimaAppState: Equatable {
    public let colima: ColimaRunningState
    public let cpus: Int?
    public let memoryGB: Double?
    public let portainerExists: Bool

    public static let unknown = ColimaAppState(
        colima: .unknown, cpus: nil, memoryGB: nil, portainerExists: false
    )
}

struct ColimaListEntry: Codable {
    let name: String
    let status: String
    let cpus: Int
    let memory: Int64
}
```

- [ ] **Step 4: Ajouter les parseurs statiques dans ColimaManager.swift (stub)**

Créer `Sources/ColimaBarCore/ColimaManager.swift` avec les méthodes statiques seulement pour débloquer les tests :

```swift
// Sources/ColimaBarCore/ColimaManager.swift
import Foundation

public final class ColimaManager {
    private let shell: ShellRunner
    private let colimaPath: String
    private let dockerPath: String

    public var onStateChange: ((ColimaAppState) -> Void)?
    private var timer: DispatchSourceTimer?

    public init(
        shell: ShellRunner = ProcessShellRunner(),
        colimaPath: String = "/opt/homebrew/bin/colima",
        dockerPath: String = "/opt/homebrew/bin/docker"
    ) {
        self.shell = shell
        self.colimaPath = colimaPath
        self.dockerPath = dockerPath
    }

    // MARK: - Parseurs statiques (internes, accessibles via @testable)

    static func parseListJSON(_ json: String) -> ColimaListEntry? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ColimaListEntry.self, from: data)
    }

    static func portainerExistsInOutput(_ output: String) -> Bool {
        let lines = output.components(separatedBy: .newlines)
        return lines.contains { $0.trimmingCharacters(in: .whitespaces) == "portainer" }
    }
}
```

- [ ] **Step 5: Lancer les tests — vérifier qu'ils passent**

```bash
swift test 2>&1 | tail -20
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 6: Commit**

```bash
git add Sources/ColimaBarCore/ColimaState.swift Sources/ColimaBarCore/ColimaManager.swift Tests/ColimaBarTests/ColimaStateTests.swift
git commit -m "feat: add ColimaState model and static parsers with tests"
```

---

## Task 4: Tests fetchStateSync + MockShellRunner

**Files:**
- Modify: `Tests/ColimaBarTests/ColimaStateTests.swift`

- [ ] **Step 1: Ajouter MockShellRunner et tests fetchStateSync**

Ajouter à la fin de `Tests/ColimaBarTests/ColimaStateTests.swift` :

```swift
// MARK: - MockShellRunner

final class MockShellRunner: ShellRunner {
    typealias Response = (output: String, error: String, exitCode: Int32)
    var responses: [String: Response] = [:]
    var calls: [(executable: String, args: [String])] = []

    func run(_ executable: String, args: [String]) -> Response {
        let key = ([executable] + args).joined(separator: " ")
        calls.append((executable: executable, args: args))
        return responses[key] ?? (output: "", error: "not mocked: \(key)", exitCode: 1)
    }
}

// MARK: - fetchStateSync

final class ColimaManagerFetchTests: XCTestCase {

    let colimaPath = "/opt/homebrew/bin/colima"
    let dockerPath = "/opt/homebrew/bin/docker"

    func makeKey(_ path: String, _ args: [String]) -> String {
        ([path] + args).joined(separator: " ")
    }

    func test_fetchStateSync_running_portainerExists() {
        let mock = MockShellRunner()
        mock.responses[makeKey(colimaPath, ["list", "--json"])] = (
            output: """{"name":"default","status":"Running","arch":"aarch64","cpus":2,"memory":4294967296,"disk":0}""",
            error: "", exitCode: 0
        )
        mock.responses[makeKey(dockerPath, ["ps", "-a", "--filter", "name=^portainer$", "--format", "{{.Names}}"])] = (
            output: "portainer", error: "", exitCode: 0
        )

        let manager = ColimaManager(shell: mock, colimaPath: colimaPath, dockerPath: dockerPath)
        let state = manager.fetchStateSync()

        XCTAssertEqual(state.colima, .running)
        XCTAssertEqual(state.cpus, 2)
        XCTAssertEqual(state.memoryGB ?? 0, 4.0, accuracy: 0.01)
        XCTAssertTrue(state.portainerExists)
    }

    func test_fetchStateSync_running_portainerMissing() {
        let mock = MockShellRunner()
        mock.responses[makeKey(colimaPath, ["list", "--json"])] = (
            output: """{"name":"default","status":"Running","arch":"aarch64","cpus":2,"memory":4294967296,"disk":0}""",
            error: "", exitCode: 0
        )
        mock.responses[makeKey(dockerPath, ["ps", "-a", "--filter", "name=^portainer$", "--format", "{{.Names}}"])] = (
            output: "", error: "", exitCode: 0
        )

        let manager = ColimaManager(shell: mock, colimaPath: colimaPath, dockerPath: dockerPath)
        let state = manager.fetchStateSync()

        XCTAssertEqual(state.colima, .running)
        XCTAssertFalse(state.portainerExists)
    }

    func test_fetchStateSync_stopped_skipsDockerCheck() {
        let mock = MockShellRunner()
        mock.responses[makeKey(colimaPath, ["list", "--json"])] = (
            output: """{"name":"default","status":"Stopped","arch":"aarch64","cpus":2,"memory":4294967296,"disk":0}""",
            error: "", exitCode: 0
        )

        let manager = ColimaManager(shell: mock, colimaPath: colimaPath, dockerPath: dockerPath)
        let state = manager.fetchStateSync()

        XCTAssertEqual(state.colima, .stopped)
        XCTAssertFalse(state.portainerExists)
        // Docker ne doit pas être appelé quand colima est stopped
        let dockerCalls = mock.calls.filter { $0.executable == dockerPath }
        XCTAssertTrue(dockerCalls.isEmpty)
    }

    func test_fetchStateSync_invalidJSON_returnsUnknown() {
        let mock = MockShellRunner()
        mock.responses[makeKey(colimaPath, ["list", "--json"])] = (
            output: "error: colima not running", error: "", exitCode: 1
        )

        let manager = ColimaManager(shell: mock, colimaPath: colimaPath, dockerPath: dockerPath)
        let state = manager.fetchStateSync()

        XCTAssertEqual(state.colima, .unknown)
    }
}
```

- [ ] **Step 2: Lancer les tests — vérifier échec (fetchStateSync pas encore implémenté)**

```bash
swift test 2>&1 | tail -30
```

Expected: erreur de compilation (`fetchStateSync` not found).

- [ ] **Step 3: Implémenter fetchStateSync dans ColimaManager.swift**

Ajouter à `ColimaManager` (dans `Sources/ColimaBarCore/ColimaManager.swift`) :

```swift
    func fetchStateSync() -> ColimaAppState {
        let listResult = shell.run(colimaPath, args: ["list", "--json"])
        guard let entry = Self.parseListJSON(listResult.output) else {
            return .unknown
        }

        let isRunning = entry.status.lowercased() == "running"
        let memoryGB = Double(entry.memory) / 1_073_741_824

        var portainerExists = false
        if isRunning {
            let r = shell.run(dockerPath, args: [
                "ps", "-a",
                "--filter", "name=^portainer$",
                "--format", "{{.Names}}"
            ])
            portainerExists = Self.portainerExistsInOutput(r.output)
        }

        return ColimaAppState(
            colima: isRunning ? .running : .stopped,
            cpus: entry.cpus,
            memoryGB: memoryGB,
            portainerExists: portainerExists
        )
    }
```

- [ ] **Step 4: Lancer les tests — vérifier qu'ils passent tous**

```bash
swift test 2>&1 | tail -10
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/ColimaBarCore/ColimaManager.swift Tests/ColimaBarTests/ColimaStateTests.swift
git commit -m "feat: implement fetchStateSync with full test coverage"
```

---

## Task 5: ColimaManager — polling + actions

**Files:**
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`

- [ ] **Step 1: Ajouter startPolling / stopPolling**

Ajouter à `ColimaManager` :

```swift
    public func startPolling() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now(), repeating: 5.0)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let state = self.fetchStateSync()
            DispatchQueue.main.async { self.onStateChange?(state) }
        }
        t.resume()
        timer = t
    }

    public func stopPolling() {
        timer?.cancel()
        timer = nil
    }
```

- [ ] **Step 2: Ajouter ShellError**

```swift
    public struct ShellError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }
```

- [ ] **Step 3: Ajouter startColima**

```swift
    public func startColima(
        onTransition: @escaping (ColimaAppState) -> Void,
        completion: @escaping (Result<ColimaAppState, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            onTransition(ColimaAppState(colima: .transitioning("Démarrage…"), cpus: nil, memoryGB: nil, portainerExists: false))
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.colimaPath, args: ["start"])
            guard result.exitCode == 0 else {
                let err = ShellError(message: result.error.isEmpty ? "Échec démarrage Colima" : result.error)
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            self.waitForSocket()
            // Démarrer Portainer s'il existe
            let portainerCheck = self.shell.run(self.dockerPath, args: [
                "ps", "-a", "--filter", "name=^portainer$", "--format", "{{.Names}}"
            ])
            if Self.portainerExistsInOutput(portainerCheck.output) {
                _ = self.shell.run(self.dockerPath, args: ["start", "portainer"])
            }
            let state = self.fetchStateSync()
            DispatchQueue.main.async { completion(.success(state)) }
        }
    }
```

- [ ] **Step 4: Ajouter stopColima**

```swift
    public func stopColima(
        onTransition: @escaping (ColimaAppState) -> Void,
        completion: @escaping (Result<ColimaAppState, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            onTransition(ColimaAppState(colima: .transitioning("Arrêt…"), cpus: nil, memoryGB: nil, portainerExists: false))
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.colimaPath, args: ["stop"])
            guard result.exitCode == 0 else {
                let err = ShellError(message: result.error.isEmpty ? "Échec arrêt Colima" : result.error)
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            let state = self.fetchStateSync()
            DispatchQueue.main.async { completion(.success(state)) }
        }
    }
```

- [ ] **Step 5: Ajouter installPortainer**

```swift
    public func installPortainer(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.dockerPath, args: [
                "run", "-d",
                "-p", "8000:8000",
                "-p", "9443:9443",
                "--name", "portainer",
                "--restart=always",
                "-v", "/var/run/docker.sock:/var/run/docker.sock",
                "-v", "portainer_data:/data",
                "portainer/portainer-ce:latest"
            ])
            if result.exitCode == 0 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let msg = result.error.isEmpty ? "Échec installation Portainer" : String(result.error.prefix(200))
                DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
            }
        }
    }
```

- [ ] **Step 6: Ajouter waitForSocket (privé)**

```swift
    private func waitForSocket() {
        let socketPath = NSHomeDirectory() + "/.colima/default/docker.sock"
        var attempts = 0
        while !FileManager.default.fileExists(atPath: socketPath) && attempts < 60 {
            Thread.sleep(forTimeInterval: 1)
            attempts += 1
        }
    }
```

- [ ] **Step 7: Vérifier que les tests passent toujours**

```bash
swift test 2>&1 | tail -10
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 8: Commit**

```bash
git add Sources/ColimaBarCore/ColimaManager.swift
git commit -m "feat: add polling, startColima, stopColima, installPortainer actions"
```

---

## Task 6: main.swift + AppDelegate squelette

**Files:**
- Create: `Sources/ColimaBar/main.swift`
- Create: `Sources/ColimaBar/AppDelegate.swift`

- [ ] **Step 1: Écrire main.swift**

```swift
// Sources/ColimaBar/main.swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: Écrire AppDelegate.swift**

```swift
// Sources/ColimaBar/AppDelegate.swift
import AppKit
import ServiceManagement
import UserNotifications
import ColimaBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: ColimaManager!
    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()
        manager = ColimaManager()
        statusBarController = StatusBarController(manager: manager)
        manager.startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopPolling()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Appelé par StatusBarController
    func showError(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "ColimaBar"
        content.body = message
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Login item

    func isLoginItemEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func toggleLoginItem() {
        do {
            if isLoginItemEnabled() {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("Impossible de modifier le démarrage automatique : \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 3: Vérifier que ça compile (StatusBarController manquant — normal)**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: erreur `cannot find type 'StatusBarController'` — normal, on l'ajoute en task 7.

- [ ] **Step 4: Commit**

```bash
git add Sources/ColimaBar/main.swift Sources/ColimaBar/AppDelegate.swift
git commit -m "feat: add main entry point and AppDelegate with SMAppService"
```

---

## Task 7: StatusBarController

**Files:**
- Create: `Sources/ColimaBar/StatusBarController.swift`

- [ ] **Step 1: Écrire StatusBarController.swift**

```swift
// Sources/ColimaBar/StatusBarController.swift
import AppKit
import ColimaBarCore

final class StatusBarController {
    private let manager: ColimaManager
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // Status items
    private var colimaStatusItem: NSMenuItem!
    private var resourcesItem: NSMenuItem!

    // Action items
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var openPortainerItem: NSMenuItem!
    private var portainerWarningItem: NSMenuItem!
    private var installPortainerItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    init(manager: ColimaManager) {
        self.manager = manager
        setupStatusItem()
        manager.onStateChange = { [weak self] state in
            self?.update(state: state)
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        statusItem.menu = menu
        updateIcon(colima: .unknown)
    }

    private func buildMenu() {
        menu = NSMenu()

        colimaStatusItem = NSMenuItem(title: "Colima : …", action: nil, keyEquivalent: "")
        colimaStatusItem.isEnabled = false
        menu.addItem(colimaStatusItem)

        resourcesItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        resourcesItem.isEnabled = false
        resourcesItem.isHidden = true
        menu.addItem(resourcesItem)

        menu.addItem(NSMenuItem.separator())

        startItem = NSMenuItem(title: "▶ Démarrer Colima", action: #selector(startColima), keyEquivalent: "")
        startItem.target = self
        menu.addItem(startItem)

        stopItem = NSMenuItem(title: "■ Arrêter Colima", action: #selector(stopColima), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        portainerWarningItem = NSMenuItem(title: "⚠ Portainer non installé", action: nil, keyEquivalent: "")
        portainerWarningItem.isEnabled = false
        portainerWarningItem.isHidden = true
        menu.addItem(portainerWarningItem)

        installPortainerItem = NSMenuItem(title: "Installer Portainer…", action: #selector(installPortainer), keyEquivalent: "")
        installPortainerItem.target = self
        installPortainerItem.isHidden = true
        menu.addItem(installPortainerItem)

        openPortainerItem = NSMenuItem(title: "Ouvrir Portainer", action: #selector(openPortainer), keyEquivalent: "")
        openPortainerItem.target = self
        openPortainerItem.isHidden = true
        menu.addItem(openPortainerItem)

        menu.addItem(NSMenuItem.separator())

        loginItem = NSMenuItem(title: "Lancer au démarrage", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - State updates

    func update(state: ColimaAppState) {
        updateIcon(colima: state.colima)
        updateMenuItems(state: state)
    }

    private func updateIcon(colima: ColimaRunningState) {
        guard let button = statusItem.button else { return }
        let color: NSColor
        switch colima {
        case .running:              color = .systemGreen
        case .stopped, .unknown:   color = .secondaryLabelColor
        case .transitioning:        color = .systemYellow
        }
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        if let base = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "ColimaBar"),
           let colored = base.withSymbolConfiguration(config) {
            colored.isTemplate = false
            button.image = colored
        }
    }

    private func updateMenuItems(state: ColimaAppState) {
        let running: Bool
        switch state.colima {
        case .running:      running = true
        default:            running = false
        }
        let transitioning: Bool
        if case .transitioning(let msg) = state.colima {
            colimaStatusItem.title = "Colima : \(msg)"
            transitioning = true
        } else {
            colimaStatusItem.title = running ? "● Colima : En cours d'exécution" : "○ Colima : Arrêté"
            transitioning = false
        }

        if let cpus = state.cpus, let mem = state.memoryGB {
            resourcesItem.title = String(format: "   CPUs: %d  |  Mémoire: %.0f GB", cpus, mem)
            resourcesItem.isHidden = false
        } else {
            resourcesItem.isHidden = true
        }

        startItem.isEnabled = !running && !transitioning
        stopItem.isEnabled = running && !transitioning

        let portainerSection = running
        openPortainerItem.isHidden = !portainerSection || !state.portainerExists
        portainerWarningItem.isHidden = !portainerSection || state.portainerExists
        installPortainerItem.isHidden = !portainerSection || state.portainerExists

        if let appDelegate = NSApp.delegate as? AppDelegate {
            loginItem.state = appDelegate.isLoginItemEnabled() ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func startColima() {
        manager.startColima(onTransition: { [weak self] state in
            self?.update(state: state)
        }, completion: { [weak self] result in
            switch result {
            case .success(let state):
                self?.update(state: state)
                if state.portainerExists {
                    NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
                }
            case .failure(let error):
                (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
                self?.manager.onStateChange?(ColimaAppState.unknown)
            }
        })
    }

    @objc private func stopColima() {
        manager.stopColima(onTransition: { [weak self] state in
            self?.update(state: state)
        }, completion: { [weak self] result in
            switch result {
            case .success(let state):
                self?.update(state: state)
            case .failure(let error):
                (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
            }
        })
    }

    @objc private func openPortainer() {
        NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
    }

    @objc private func installPortainer() {
        installPortainerItem.isEnabled = false
        manager.installPortainer { [weak self] result in
            self?.installPortainerItem.isEnabled = true
            switch result {
            case .success:
                NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
            case .failure(let error):
                (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
            }
        }
    }

    @objc private func toggleLoginItem() {
        (NSApp.delegate as? AppDelegate)?.toggleLoginItem()
        if let appDelegate = NSApp.delegate as? AppDelegate {
            loginItem.state = appDelegate.isLoginItemEnabled() ? .on : .off
        }
    }
}
```

- [ ] **Step 2: Vérifier que le build complet passe**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Vérifier que les tests passent encore**

```bash
swift test 2>&1 | tail -5
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 4: Commit**

```bash
git add Sources/ColimaBar/StatusBarController.swift
git commit -m "feat: implement StatusBarController with dynamic menu and colored icon"
```

---

## Task 8: Configuration CPU/Mémoire

**Files:**
- Create: `Sources/ColimaBarCore/ColimaConfig.swift`
- Modify: `Sources/ColimaBarCore/ColimaManager.swift`
- Modify: `Sources/ColimaBar/StatusBarController.swift`
- Modify: `Tests/ColimaBarTests/ColimaStateTests.swift`

**Comportement :**
- Sous-menu "⚙ Configuration" avec presets CPU et Mémoire
- Valeurs désirées persistées dans `UserDefaults`
- Si Colima stopped → sauvegarde, sera appliqué au prochain démarrage
- Si Colima running → redémarre automatiquement avec nouvelles valeurs (stop + start)

- [ ] **Step 1: Écrire ColimaConfig.swift**

```swift
// Sources/ColimaBarCore/ColimaConfig.swift
import Foundation

public struct ColimaConfig {
    public static let cpuOptions: [Int] = [1, 2, 4, 6, 8]
    public static let memoryOptions: [Int] = [2, 4, 6, 8, 16]  // en GB

    private static let cpuKey = "colima.desiredCPUs"
    private static let memKey = "colima.desiredMemoryGB"

    public static var desiredCPUs: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: cpuKey)
            return v > 0 ? v : 2
        }
        set { UserDefaults.standard.set(newValue, forKey: cpuKey) }
    }

    public static var desiredMemoryGB: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: memKey)
            return v > 0 ? v : 4
        }
        set { UserDefaults.standard.set(newValue, forKey: memKey) }
    }
}
```

- [ ] **Step 2: Écrire les tests pour ColimaConfig**

Ajouter dans `Tests/ColimaBarTests/ColimaStateTests.swift` :

```swift
final class ColimaConfigTests: XCTestCase {

    override func setUp() {
        // Reset defaults avant chaque test
        UserDefaults.standard.removeObject(forKey: "colima.desiredCPUs")
        UserDefaults.standard.removeObject(forKey: "colima.desiredMemoryGB")
    }

    func test_defaultCPUs_is2() {
        XCTAssertEqual(ColimaConfig.desiredCPUs, 2)
    }

    func test_defaultMemory_is4() {
        XCTAssertEqual(ColimaConfig.desiredMemoryGB, 4)
    }

    func test_persistCPUs() {
        ColimaConfig.desiredCPUs = 6
        XCTAssertEqual(ColimaConfig.desiredCPUs, 6)
    }

    func test_persistMemory() {
        ColimaConfig.desiredMemoryGB = 8
        XCTAssertEqual(ColimaConfig.desiredMemoryGB, 8)
    }

    func test_cpuOptions_contains_common_values() {
        XCTAssertTrue(ColimaConfig.cpuOptions.contains(2))
        XCTAssertTrue(ColimaConfig.cpuOptions.contains(4))
    }
}
```

- [ ] **Step 3: Lancer les tests — vérifier échec**

```bash
swift test 2>&1 | grep -E "error:|FAILED|passed"
```

Expected: erreur `ColimaConfig` not found.

- [ ] **Step 4: Modifier startColima pour utiliser ColimaConfig**

Dans `Sources/ColimaBarCore/ColimaManager.swift`, modifier la signature et l'implémentation de `startColima` pour passer les flags CPU/mémoire :

Remplacer :
```swift
            let result = self.shell.run(self.colimaPath, args: ["start"])
```

Par :
```swift
            let cpus = ColimaConfig.desiredCPUs
            let mem = ColimaConfig.desiredMemoryGB
            let result = self.shell.run(self.colimaPath, args: [
                "start",
                "--cpu", "\(cpus)",
                "--memory", "\(mem)"
            ])
```

- [ ] **Step 5: Lancer les tests — vérifier qu'ils passent tous**

```bash
swift test 2>&1 | tail -10
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 6: Ajouter le sous-menu Configuration dans StatusBarController**

Dans `Sources/ColimaBar/StatusBarController.swift`, ajouter les propriétés :

```swift
    private var configMenu: NSMenu!
    private var cpuMenuItems: [NSMenuItem] = []
    private var memMenuItems: [NSMenuItem] = []
    private var isColimaRunning = false
```

Dans `buildMenu()`, ajouter avant le séparateur des login items :

```swift
        menu.addItem(NSMenuItem.separator())

        let configItem = NSMenuItem(title: "⚙ Configuration", action: nil, keyEquivalent: "")
        configMenu = NSMenu()

        // Sous-menu CPUs
        let cpuHeader = NSMenuItem(title: "CPUs", action: nil, keyEquivalent: "")
        cpuHeader.isEnabled = false
        configMenu.addItem(cpuHeader)

        for cpu in ColimaConfig.cpuOptions {
            let item = NSMenuItem(
                title: "\(cpu) CPU\(cpu > 1 ? "s" : "")",
                action: #selector(setCPU(_:)),
                keyEquivalent: ""
            )
            item.tag = cpu
            item.target = self
            configMenu.addItem(item)
            cpuMenuItems.append(item)
        }

        configMenu.addItem(NSMenuItem.separator())

        // Sous-menu Mémoire
        let memHeader = NSMenuItem(title: "Mémoire", action: nil, keyEquivalent: "")
        memHeader.isEnabled = false
        configMenu.addItem(memHeader)

        for gb in ColimaConfig.memoryOptions {
            let item = NSMenuItem(
                title: "\(gb) GB",
                action: #selector(setMemory(_:)),
                keyEquivalent: ""
            )
            item.tag = gb
            item.target = self
            configMenu.addItem(item)
            memMenuItems.append(item)
        }

        configItem.submenu = configMenu
        menu.addItem(configItem)
```

- [ ] **Step 7: Ajouter la mise à jour des checkmarks dans updateMenuItems**

Ajouter à la fin de `updateMenuItems(state:)` :

```swift
        isColimaRunning = running

        let currentCPU = state.cpus ?? ColimaConfig.desiredCPUs
        let currentMem = state.memoryGB.map { Int($0.rounded()) } ?? ColimaConfig.desiredMemoryGB

        for item in cpuMenuItems {
            item.state = item.tag == currentCPU ? .on : .off
        }
        for item in memMenuItems {
            item.state = item.tag == currentMem ? .on : .off
        }
```

- [ ] **Step 8: Ajouter les actions setCPU et setMemory**

```swift
    @objc private func setCPU(_ sender: NSMenuItem) {
        let cpus = sender.tag
        ColimaConfig.desiredCPUs = cpus
        for item in cpuMenuItems { item.state = item.tag == cpus ? .on : .off }

        if isColimaRunning {
            restartWithNewConfig()
        }
    }

    @objc private func setMemory(_ sender: NSMenuItem) {
        let gb = sender.tag
        ColimaConfig.desiredMemoryGB = gb
        for item in memMenuItems { item.state = item.tag == gb ? .on : .off }

        if isColimaRunning {
            restartWithNewConfig()
        }
    }

    private func restartWithNewConfig() {
        manager.stopColima(onTransition: { [weak self] state in
            self?.update(state: state)
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.manager.startColima(onTransition: { state in
                    self.update(state: state)
                }, completion: { result in
                    switch result {
                    case .success(let state):
                        self.update(state: state)
                        if state.portainerExists {
                            NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
                        }
                    case .failure(let error):
                        (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
                    }
                })
            case .failure(let error):
                (NSApp.delegate as? AppDelegate)?.showError(error.localizedDescription)
            }
        })
    }
```

- [ ] **Step 9: Vérifier que le build complet passe**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 10: Commit**

```bash
git add Sources/ColimaBarCore/ColimaConfig.swift Sources/ColimaBarCore/ColimaManager.swift Sources/ColimaBar/StatusBarController.swift Tests/ColimaBarTests/ColimaStateTests.swift
git commit -m "feat: add CPU and memory configuration submenu with restart on change"
```

---

## Task 9: Build, bundle, install, smoke test

**Files:** aucun nouveau — utilise le Makefile existant.

- [ ] **Step 1: Build release**

```bash
make build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 2: Créer le bundle et signer**

```bash
make bundle
```

Expected:
```
Build complete!
Bundle: ColimaBar.app
```

- [ ] **Step 3: Vérifier la structure du bundle**

```bash
find ColimaBar.app -type f
```

Expected:
```
ColimaBar.app/Contents/Info.plist
ColimaBar.app/Contents/MacOS/ColimaBar
```

- [ ] **Step 4: Installer dans /Applications**

```bash
make install
```

Expected: `Installed: /Applications/ColimaBar.app`

- [ ] **Step 5: Lancer l'app**

```bash
open /Applications/ColimaBar.app
```

Vérifier dans la barre de menus : icône `📦` apparaît (grise si Colima stopped).

- [ ] **Step 6: Smoke test — état stopped**

Cliquer sur l'icône. Vérifier :
- "○ Colima : Arrêté" affiché
- "▶ Démarrer Colima" cliquable
- "■ Arrêter Colima" grisé
- Pas de section Portainer visible

- [ ] **Step 7: Smoke test — démarrer Colima**

Cliquer "▶ Démarrer Colima". Vérifier :
- Icône devient jaune pendant démarrage
- Icône devient verte quand running
- CPUs + Mémoire affichés
- Si Portainer existe : "Ouvrir Portainer" visible + navigateur ouvre `https://localhost:9443`
- Si Portainer absent : "⚠ Portainer non installé" + "Installer Portainer…" visibles

- [ ] **Step 8: Smoke test — installer Portainer (si absent)**

Cliquer "Installer Portainer…". Vérifier :
- `docker pull portainer/portainer-ce:latest` se lance (peut prendre 1-2 min)
- Navigateur ouvre `https://localhost:9443` après installation

- [ ] **Step 9: Smoke test — arrêter Colima**

Cliquer "■ Arrêter Colima". Vérifier :
- Icône devient jaune pendant arrêt
- Icône devient grise quand stopped
- Section Portainer disparaît

- [ ] **Step 10: Smoke test — login item**

Cliquer "Lancer au démarrage". Vérifier :
- Coche ✓ apparaît à côté
- Recliquer enlève la coche
- Aller dans Réglages Système → Général → Éléments de connexion → vérifier ColimaBar présent/absent selon état

- [ ] **Step 11: Commit final**

```bash
git add -A
git commit -m "feat: complete ColimaBar — menu bar app for Colima + Portainer management"
```

- [ ] **Step 12 (optionnel): Supprimer l'ancienne Portainer.app**

Si le smoke test est satisfaisant, supprimer l'ancien wrapper :

```bash
rm /Applications/Portainer.app
rm ~/Applications/PortainerLauncher.sh
```
