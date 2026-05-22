// Tests/ColimaBarTests/DockerExecServiceTests.swift
import Foundation
import ColimaBarCore

// MARK: - DockerExecService tests

func test_listFiles_parsesLsOutput() {
    let output = """
    total 24
    drwxr-xr-x 2 root root 4096 Jan  1 12:00 .
    drwxr-xr-x 3 root root 4096 Jan  1 12:00 ..
    -rw-r--r-- 1 root root  512 Jan  1 12:00 config.yml
    drwxr-xr-x 2 root root 4096 Jan  1 12:00 data
    -rwxr-xr-x 1 root root  128 Jan  1 12:00 run.sh
    """
    let entries = DockerExecService.parseListOutput(output)
    checkEqual(entries.count, 3, "listFiles: 3 entries (dot entries filtered)")
    checkEqual(entries[0].name, "config.yml", "listFiles: first entry name")
    checkEqual(entries[0].permissions, "-rw-r--r--", "listFiles: permissions")
    checkEqual(entries[0].size, "512", "listFiles: size")
    check(!entries[0].isDirectory, "listFiles: file not isDirectory")
    checkEqual(entries[1].name, "data", "listFiles: dir name")
    check(entries[1].isDirectory, "listFiles: dir isDirectory")
}

func test_listFiles_emptyOutput() {
    let entries = DockerExecService.parseListOutput("")
    checkEqual(entries.count, 0, "listFiles: empty input → empty result")
}

func test_listFiles_totalLineFiltered() {
    let output = "total 0\n"
    let entries = DockerExecService.parseListOutput(output)
    checkEqual(entries.count, 0, "listFiles: total line filtered")
}

func test_execShellCommand_containerNotRunning() {
    let mock = MockShellRunner()
    let container = DockerContainer(id: "abc", name: "myapp", state: .exited,
                                    status: "Exited (0)", image: "nginx", ports: "")
    let service = DockerExecService(shell: mock, dockerPath: "/usr/bin/docker")
    var errorThrown = false
    do {
        _ = try service.listFiles(container: container, path: "/")
    } catch DockerExecError.containerNotRunning {
        errorThrown = true
    } catch {}
    check(errorThrown, "listFiles: throws containerNotRunning when container is exited")
}

func test_execShellCommand_callsDockerExec() {
    let mock = MockShellRunner()
    mock.responses["/usr/bin/docker exec myapp ls -la /app"] = (output: "total 0\n", error: "", exitCode: 0)
    let container = DockerContainer(id: "abc", name: "myapp", state: .running,
                                    status: "Up 5 minutes", image: "nginx", ports: "")
    let service = DockerExecService(shell: mock, dockerPath: "/usr/bin/docker")
    _ = try? service.listFiles(container: container, path: "/app")
    let called = mock.calls.contains { $0.executable == "/usr/bin/docker" && $0.args == ["exec", "myapp", "ls", "-la", "/app"] }
    check(called, "listFiles: calls docker exec with correct args")
}
