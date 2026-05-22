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

// MARK: - ColimaProfile tests

func test_colimaProfiles_presets() {
    check(ColimaProfile.presets.count == 3, "3 presets")
    check(ColimaProfile.presets[0].name == "Minimal", "first = Minimal")
    check(ColimaProfile.presets[1].cpus == 2, "Dev = 2 CPUs")
    check(ColimaProfile.presets[2].memoryGB == 8, "Heavy = 8 GB")
}

func test_colimaProfiles_activeMatch() {
    UserDefaults.standard.removeObject(forKey: "colima.desiredCPUs")
    UserDefaults.standard.removeObject(forKey: "colima.desiredMemoryGB")
    ColimaConfig.desiredCPUs = 2
    ColimaConfig.desiredMemoryGB = 4
    let active = ColimaProfile.presets.first {
        $0.cpus == ColimaConfig.desiredCPUs && $0.memoryGB == ColimaConfig.desiredMemoryGB
    }
    check(active?.name == "Dev", "active profile = Dev when 2CPU/4GB")
    UserDefaults.standard.removeObject(forKey: "colima.desiredCPUs")
    UserDefaults.standard.removeObject(forKey: "colima.desiredMemoryGB")
}

// MARK: - DockerContainer health check tests

func test_health_healthy() {
    let c = DockerContainer(id: "x", name: "x", state: .running,
                            status: "Up 2 hours (healthy)", image: "nginx", ports: "")
    checkEqual(c.health, DockerContainer.HealthStatus.healthy, "status contains (healthy)")
}

func test_health_unhealthy() {
    let c = DockerContainer(id: "x", name: "x", state: .running,
                            status: "Up 1 hour (unhealthy)", image: "nginx", ports: "")
    checkEqual(c.health, DockerContainer.HealthStatus.unhealthy, "status contains (unhealthy)")
}

func test_health_starting() {
    let c = DockerContainer(id: "x", name: "x", state: .running,
                            status: "Up 5s (health: starting)", image: "nginx", ports: "")
    checkEqual(c.health, DockerContainer.HealthStatus.starting, "status contains (health: starting)")
}

func test_health_nil_no_healthcheck() {
    let c = DockerContainer(id: "x", name: "x", state: .running,
                            status: "Up 3 days", image: "nginx", ports: "")
    checkNil(c.health, "status without health → nil")
}

// MARK: - DockerContainer hostPortNumbers tests

func test_hostPortNumbers_single() {
    let c = DockerContainer(id: "x", name: "x", state: .running, status: "",
                            image: "", ports: "0.0.0.0:8080->8080/tcp")
    checkEqual(c.hostPortNumbers, [8080], "single port → [8080]")
}

func test_hostPortNumbers_multiple() {
    let c = DockerContainer(id: "x", name: "x", state: .running, status: "",
                            image: "", ports: "0.0.0.0:8000->8000/tcp, :::9443->9443/tcp")
    checkEqual(c.hostPortNumbers, [8000, 9443], "two ports → [8000, 9443]")
}

func test_hostPortNumbers_empty() {
    let c = DockerContainer(id: "x", name: "x", state: .running, status: "", image: "", ports: "")
    check(c.hostPortNumbers.isEmpty, "no ports → empty array")
}

// MARK: - parseDockerImages tests

private let imageOneLine = """
{"ID":"sha256:abc123","Repository":"nginx","Tag":"latest","Size":"142MB","CreatedSince":"3 weeks ago"}
"""
private let imageTwoLines = """
{"ID":"sha256:abc123","Repository":"nginx","Tag":"latest","Size":"142MB","CreatedSince":"3 weeks ago"}
{"ID":"sha256:def456","Repository":"postgres","Tag":"15","Size":"379MB","CreatedSince":"2 months ago"}
"""

func test_parseDockerImages_singleLine() {
    let images = ColimaManager.parseDockerImages(imageOneLine)
    check(images.count == 1, "1 image parsed")
    checkEqual(images[0].repository, "nginx", "repository = nginx")
    checkEqual(images[0].tag, "latest", "tag = latest")
    checkEqual(images[0].size, "142MB", "size = 142MB")
    checkEqual(images[0].created, "3 weeks ago", "created = 3 weeks ago")
    checkEqual(images[0].id, "sha256:abc123", "id correct")
}

func test_parseDockerImages_multiLine() {
    let images = ColimaManager.parseDockerImages(imageTwoLines)
    check(images.count == 2, "2 images parsed")
    checkEqual(images[1].repository, "postgres", "second repo = postgres")
}

func test_parseDockerImages_empty() {
    check(ColimaManager.parseDockerImages("").isEmpty, "empty → empty array")
    check(ColimaManager.parseDockerImages("not json").isEmpty, "invalid → empty array")
}

// MARK: - parseDockerVolumes tests

private let volumeLsOutput = """
{"Driver":"local","Name":"portainer_data"}
{"Driver":"local","Name":"my-vol"}
"""

private let volumeDfOutput = """
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Local Volumes   2         1         43MB      0B (0%)

Local Volumes space usage:

VOLUME NAME             LINKS     SIZE
portainer_data          1         42.54MB
my-vol                  0         1.23GB
"""

func test_parseDockerVolumes_countAndNames() {
    let vols = ColimaManager.parseDockerVolumes(volumeLsOutput, volumeDfOutput)
    check(vols.count == 2, "2 volumes")
    checkEqual(vols[0].name, "portainer_data", "first volume name")
    checkEqual(vols[1].name, "my-vol", "second volume name")
}

func test_parseDockerVolumes_driverAndSize() {
    let vols = ColimaManager.parseDockerVolumes(volumeLsOutput, volumeDfOutput)
    checkEqual(vols[0].driver, "local", "driver = local")
    checkEqual(vols[0].size, "42.54MB", "size from df output")
    checkEqual(vols[1].size, "1.23GB", "second volume size")
}

func test_parseDockerVolumes_sizeNA_whenDfMissing() {
    let vols = ColimaManager.parseDockerVolumes(volumeLsOutput, "")
    checkEqual(vols[0].size, "N/A", "size = N/A when df output empty")
}

func test_parseDockerVolumes_empty() {
    check(ColimaManager.parseDockerVolumes("", "").isEmpty, "empty ls → empty array")
}

func test_parseDockerVolumes_containers() {
    let psOutput = "portainer\tportainer_data,/var/run/docker.sock\nmy-app\tmy-vol"
    let vols = ColimaManager.parseDockerVolumes(volumeLsOutput, volumeDfOutput, psOutput)
    checkEqual(vols[0].containers, ["portainer"], "portainer_data used by portainer")
    checkEqual(vols[1].containers, ["my-app"], "my-vol used by my-app")
}

func test_parseDockerVolumes_containers_empty_whenNone() {
    let vols = ColimaManager.parseDockerVolumes(volumeLsOutput, volumeDfOutput, "")
    check(vols[0].containers.isEmpty, "no ps output → empty containers")
}

func test_parseDockerVolumes_bindMounts_ignored() {
    let psOutput = "my-app\t/home/user/data,my-vol"
    let vols = ColimaManager.parseDockerVolumes(volumeLsOutput, volumeDfOutput, psOutput)
    // /home/user/data is a bind mount (starts with /) — should be ignored
    checkEqual(vols[1].containers, ["my-app"], "named volume linked, bind mount ignored")
    check(vols[0].containers.isEmpty, "portainer_data not linked to my-app")
}
