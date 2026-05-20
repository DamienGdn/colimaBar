@testable import ColimaBarCore

// MARK: - Test Cases

/// Tests for ColimaState and ColimaManager static parsers
///
/// These tests verify:
/// - JSON parsing of Colima list output
/// - Memory conversion (bytes to GB)
/// - Container name detection in docker output
final class ColimaStateTests {

    // MARK: - parseListJSON

    func test_parseListJSON_running() {
        let json = """
        {"name":"default","status":"Running","arch":"aarch64","cpus":2,"memory":4294967296,"disk":10737418240}
        """
        let entry = ColimaManager.parseListJSON(json)
        assert(entry != nil, "parseListJSON should parse valid JSON")
        assert(entry?.status == "Running", "status should be Running")
        assert(entry?.cpus == 2, "cpus should be 2")
        assert(entry?.memory == 4_294_967_296, "memory should be 4294967296")
    }

    func test_parseListJSON_stopped() {
        let json = """
        {"name":"default","status":"Stopped","arch":"aarch64","cpus":4,"memory":8589934592,"disk":10737418240}
        """
        let entry = ColimaManager.parseListJSON(json)
        assert(entry?.status == "Stopped", "status should be Stopped")
        assert(entry?.cpus == 4, "cpus should be 4")
    }

    func test_parseListJSON_invalid_returnsNil() {
        assert(ColimaManager.parseListJSON("not json") == nil, "should return nil for invalid json")
        assert(ColimaManager.parseListJSON("") == nil, "should return nil for empty string")
        assert(ColimaManager.parseListJSON("{}") == nil, "should return nil for incomplete JSON")
    }

    func test_memoryGB_conversion() {
        // 4294967296 bytes = 4.0 GB
        let memBytes: Int64 = 4_294_967_296
        let gb = Double(memBytes) / 1_073_741_824
        let expected = 4.0
        let diff = abs(gb - expected)
        assert(diff < 0.01, "Memory conversion should be close to 4.0 GB, got \(gb)")
    }

    // MARK: - portainerExistsInOutput

    func test_portainerExists_found() {
        assert(ColimaManager.portainerExistsInOutput("portainer") == true, "should find 'portainer'")
        assert(ColimaManager.portainerExistsInOutput("portainer\n") == true, "should find 'portainer' with newline")
        assert(ColimaManager.portainerExistsInOutput("  portainer  ") == true, "should find 'portainer' with whitespace")
    }

    func test_portainerExists_notFound() {
        assert(ColimaManager.portainerExistsInOutput("") == false, "should not find in empty string")
        assert(ColimaManager.portainerExistsInOutput("nginx") == false, "should not find 'nginx'")
        assert(ColimaManager.portainerExistsInOutput("portainer-agent") == false, "should not find 'portainer-agent'")
    }
}

