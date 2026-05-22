// Sources/ColimaBarCore/DockerExecService.swift
import Foundation

public enum DockerExecError: Error {
    case containerNotRunning
    case commandFailed(String)
}

public struct FileEntry: Equatable {
    public let name: String
    public let size: String
    public let permissions: String
    public let isDirectory: Bool

    public init(name: String, size: String, permissions: String, isDirectory: Bool) {
        self.name = name
        self.size = size
        self.permissions = permissions
        self.isDirectory = isDirectory
    }
}

public final class DockerExecService {
    private let shell: ShellRunner
    private let dockerPath: String

    public init(shell: ShellRunner = ProcessShellRunner(),
                dockerPath: String = "/opt/homebrew/bin/docker") {
        self.shell = shell
        self.dockerPath = dockerPath
    }

    // MARK: - Static parser (testable without shell)

    public static func parseListOutput(_ output: String) -> [FileEntry] {
        output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty && !$0.hasPrefix("total") }
            .compactMap { line -> FileEntry? in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 9 else { return nil }
                let permissions = parts[0]
                let size = parts[4]
                let name = parts[8...].joined(separator: " ")
                guard name != "." && name != ".." else { return nil }
                return FileEntry(
                    name: name,
                    size: size,
                    permissions: permissions,
                    isDirectory: permissions.first == "d"
                )
            }
    }

    // MARK: - Commands

    public func listFiles(container: DockerContainer, path: String) throws -> [FileEntry] {
        guard container.isRunning else { throw DockerExecError.containerNotRunning }
        let result = shell.run(dockerPath, args: ["exec", container.name, "ls", "-la", path])
        guard result.exitCode == 0 else { throw DockerExecError.commandFailed(result.error) }
        return DockerExecService.parseListOutput(result.output)
    }

    public func copyFromContainer(container: DockerContainer, remotePath: String, localURL: URL) throws {
        guard container.isRunning else { throw DockerExecError.containerNotRunning }
        let src = "\(container.name):\(remotePath)"
        let result = shell.run(dockerPath, args: ["cp", src, localURL.path])
        guard result.exitCode == 0 else { throw DockerExecError.commandFailed(result.error) }
    }

    public func copyToContainer(container: DockerContainer, localURL: URL, remotePath: String) throws {
        guard container.isRunning else { throw DockerExecError.containerNotRunning }
        let dst = "\(container.name):\(remotePath)"
        let result = shell.run(dockerPath, args: ["cp", localURL.path, dst])
        guard result.exitCode == 0 else { throw DockerExecError.commandFailed(result.error) }
    }
}
