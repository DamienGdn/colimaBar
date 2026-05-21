import Foundation
import ColimaBarCore

// MARK: - Minimal test runner (no XCTest — CLT only)

var _passed = 0
var _failed = 0

func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        _passed += 1
        print("  ✅ \(message)")
    } else {
        let f = URL(fileURLWithPath: file).lastPathComponent
        print("  ❌ FAIL: \(message) (\(f):\(line))")
        _failed += 1
    }
}

func checkNil<T>(_ value: T?, _ message: String, file: String = #file, line: Int = #line) {
    check(value == nil, message, file: file, line: line)
}

func checkNotNil<T>(_ value: T?, _ message: String, file: String = #file, line: Int = #line) {
    check(value != nil, message, file: file, line: line)
}

func checkEqual<T: Equatable>(_ actual: T?, _ expected: T, _ message: String, file: String = #file, line: Int = #line) {
    let ok = actual == expected
    let detail = ok ? message : "\(message): got \(String(describing: actual)), expected \(expected)"
    check(ok, detail, file: file, line: line)
}

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

let _colimaPath = "/opt/homebrew/bin/colima"
let _dockerPath = "/opt/homebrew/bin/docker"

func makeKey(_ path: String, _ args: [String]) -> String {
    ([path] + args).joined(separator: " ")
}

// MARK: - parseListJSON tests

func test_parseListJSON_running() {
    let json = """
    {"name":"default","status":"Running","arch":"aarch64","cpus":2,"memory":4294967296,"disk":10737418240}
    """
    let entry = ColimaManager.parseListJSON(json)
    checkNotNil(entry, "parseListJSON should parse valid JSON")
    checkEqual(entry?.status, "Running", "status should be Running")
    checkEqual(entry?.cpus, 2, "cpus should be 2")
    checkEqual(entry?.memory, 4_294_967_296, "memory bytes")
}

func test_parseListJSON_stopped() {
    let json = """
    {"name":"default","status":"Stopped","arch":"aarch64","cpus":4,"memory":8589934592,"disk":10737418240}
    """
    let entry = ColimaManager.parseListJSON(json)
    checkEqual(entry?.status, "Stopped", "status should be Stopped")
    checkEqual(entry?.cpus, 4, "cpus should be 4")
}

func test_parseListJSON_invalid_returnsNil() {
    checkNil(ColimaManager.parseListJSON("not json"), "invalid json → nil")
    checkNil(ColimaManager.parseListJSON(""), "empty string → nil")
    checkNil(ColimaManager.parseListJSON("{}"), "incomplete JSON → nil")
}

func test_memoryGB_conversion() {
    let memBytes: Int64 = 4_294_967_296
    let gb = Double(memBytes) / 1_073_741_824
    check(abs(gb - 4.0) < 0.01, "4294967296 bytes = 4.0 GB (got \(gb))")
}

// MARK: - portainerExistsInOutput tests

func test_portainerExists_found() {
    check(ColimaManager.portainerExistsInOutput("portainer"), "plain 'portainer' found")
    check(ColimaManager.portainerExistsInOutput("portainer\n"), "'portainer\\n' found")
    check(ColimaManager.portainerExistsInOutput("  portainer  "), "'  portainer  ' found")
}

func test_portainerExists_notFound() {
    check(!ColimaManager.portainerExistsInOutput(""), "empty string not matched")
    check(!ColimaManager.portainerExistsInOutput("nginx"), "'nginx' not matched")
    check(!ColimaManager.portainerExistsInOutput("portainer-agent"), "'portainer-agent' not matched")
}

// MARK: - fetchStateSync tests

private let runningJSON = "{\"name\":\"default\",\"status\":\"Running\",\"arch\":\"aarch64\",\"cpus\":2,\"memory\":4294967296,\"disk\":0}"
private let stoppedJSON = "{\"name\":\"default\",\"status\":\"Stopped\",\"arch\":\"aarch64\",\"cpus\":2,\"memory\":4294967296,\"disk\":0}"
private let dockerFilter = ["ps", "-a", "--filter", "name=^portainer$", "--format", "{{.Names}}"]

func test_fetchStateSync_running_portainerExists() {
    let mock = MockShellRunner()
    mock.responses[makeKey(_colimaPath, ["list", "--json"])] = (output: runningJSON, error: "", exitCode: 0)
    mock.responses[makeKey(_dockerPath, dockerFilter)] = (output: "portainer", error: "", exitCode: 0)
    let manager = ColimaManager(shell: mock, colimaPath: _colimaPath, dockerPath: _dockerPath)
    let state = manager.fetchStateSync()
    check(state.colima == ColimaRunningState.running, "colima state = running")
    checkEqual(state.cpus, 2, "cpus = 2")
    check(abs((state.memoryGB ?? 0) - 4.0) < 0.01, "memoryGB ~= 4.0")
    check(state.portainerExists, "portainerExists = true")
}

func test_fetchStateSync_running_portainerMissing() {
    let mock = MockShellRunner()
    mock.responses[makeKey(_colimaPath, ["list", "--json"])] = (output: runningJSON, error: "", exitCode: 0)
    mock.responses[makeKey(_dockerPath, dockerFilter)] = (output: "", error: "", exitCode: 0)
    let manager = ColimaManager(shell: mock, colimaPath: _colimaPath, dockerPath: _dockerPath)
    let state = manager.fetchStateSync()
    check(state.colima == ColimaRunningState.running, "colima state = running")
    check(!state.portainerExists, "portainerExists = false")
}

func test_fetchStateSync_stopped_skipsDockerCheck() {
    let mock = MockShellRunner()
    mock.responses[makeKey(_colimaPath, ["list", "--json"])] = (output: stoppedJSON, error: "", exitCode: 0)
    let manager = ColimaManager(shell: mock, colimaPath: _colimaPath, dockerPath: _dockerPath)
    let state = manager.fetchStateSync()
    check(state.colima == ColimaRunningState.stopped, "colima state = stopped")
    check(!state.portainerExists, "portainerExists = false when stopped")
    let dockerCalls = mock.calls.filter { $0.executable == _dockerPath }
    check(dockerCalls.isEmpty, "docker NOT called when colima stopped")
}

func test_fetchStateSync_invalidJSON_returnsUnknown() {
    let mock = MockShellRunner()
    mock.responses[makeKey(_colimaPath, ["list", "--json"])] = (output: "error: not running", error: "", exitCode: 1)
    let manager = ColimaManager(shell: mock, colimaPath: _colimaPath, dockerPath: _dockerPath)
    let state = manager.fetchStateSync()
    check(state.colima == ColimaRunningState.unknown, "invalid JSON → unknown state")
}

// MARK: - ColimaConfig tests

func test_colimaConfig() {
    UserDefaults.standard.removeObject(forKey: "colima.desiredCPUs")
    UserDefaults.standard.removeObject(forKey: "colima.desiredMemoryGB")
    check(ColimaConfig.desiredCPUs == 2, "default CPUs = 2")
    check(ColimaConfig.desiredMemoryGB == 4, "default memory = 4 GB")
    ColimaConfig.desiredCPUs = 6
    check(ColimaConfig.desiredCPUs == 6, "persist CPUs = 6")
    ColimaConfig.desiredMemoryGB = 8
    check(ColimaConfig.desiredMemoryGB == 8, "persist memory = 8 GB")
    check(ColimaConfig.cpuOptions.contains(2), "CPU options has 2")
    check(ColimaConfig.cpuOptions.contains(4), "CPU options has 4")
    UserDefaults.standard.removeObject(forKey: "colima.desiredCPUs")
    UserDefaults.standard.removeObject(forKey: "colima.desiredMemoryGB")
}

// MARK: - DockerContainer parsing

private let dockerOneLine = "{\"ID\":\"abc123def456\",\"Names\":\"portainer\",\"State\":\"running\",\"Status\":\"Up 5 minutes\",\"Image\":\"portainer/portainer-ce:latest\"}"
private let dockerStoppedLine = "{\"ID\":\"def456abc789\",\"Names\":\"nginx\",\"State\":\"exited\",\"Status\":\"Exited (0) 2 hours ago\",\"Image\":\"nginx:latest\"}"

func test_parseDockerContainers_multiLine() {
    let output = dockerOneLine + "\n" + dockerStoppedLine
    let containers = ColimaManager.parseDockerContainers(output)
    check(containers.count == 2, "should parse 2 containers")
}

func test_parseDockerContainers_running() {
    let containers = ColimaManager.parseDockerContainers(dockerOneLine)
    check(containers.count == 1, "1 container")
    check(containers[0].name == "portainer", "name portainer")
    check(containers[0].state == DockerContainer.ContainerState.running, "state running")
    check(containers[0].image == "portainer/portainer-ce:latest", "image")
}

func test_parseDockerContainers_exited() {
    let containers = ColimaManager.parseDockerContainers(dockerStoppedLine)
    check(containers[0].state == DockerContainer.ContainerState.exited, "state exited")
}

func test_parseDockerContainers_empty() {
    check(ColimaManager.parseDockerContainers("").isEmpty, "empty → empty array")
    check(ColimaManager.parseDockerContainers("not json").isEmpty, "invalid → empty array")
}

func test_fetchStateSync_running_includesContainers() {
    let mock = MockShellRunner()
    mock.responses[makeKey(_colimaPath, ["list", "--json"])] = (output: runningJSON, error: "", exitCode: 0)
    mock.responses[makeKey(_dockerPath, dockerFilter)] = (output: "portainer", error: "", exitCode: 0)
    mock.responses[makeKey(_dockerPath, ["stats", "--no-stream", "--format", "{{.CPUPerc}}\t{{.MemUsage}}"])] = (output: "portainer\t1.5%\t80MiB / 4GiB", error: "", exitCode: 0)
    mock.responses[makeKey(_dockerPath, ["ps", "-a", "--format", "{{json .}}"])] = (
        output: "{\"ID\":\"abc\",\"Names\":\"portainer\",\"State\":\"running\",\"Status\":\"Up\",\"Image\":\"portainer/portainer-ce:latest\"}",
        error: "", exitCode: 0
    )
    let manager = ColimaManager(shell: mock, colimaPath: _colimaPath, dockerPath: _dockerPath)
    let state = manager.fetchStateSync()
    check(state.containers.count == 1, "should have 1 container")
    check(state.containers[0].name == "portainer", "container name")
    check(state.containers[0].isRunning, "container running")
}

func test_fetchStateSync_stopped_noContainers() {
    let mock = MockShellRunner()
    mock.responses[makeKey(_colimaPath, ["list", "--json"])] = (output: stoppedJSON, error: "", exitCode: 0)
    let manager = ColimaManager(shell: mock, colimaPath: _colimaPath, dockerPath: _dockerPath)
    let state = manager.fetchStateSync()
    check(state.containers.isEmpty, "stopped → no containers")
}
