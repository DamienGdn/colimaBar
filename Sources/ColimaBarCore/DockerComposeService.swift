// Sources/ColimaBarCore/DockerComposeService.swift
import Foundation

public struct ComposeProject: Equatable {
    public let name: String
    public let workingDir: String
    public let configFile: URL

    public init(name: String, workingDir: String, configFile: URL) {
        self.name = name
        self.workingDir = workingDir
        self.configFile = configFile
    }
}

public enum DockerComposeError: Error {
    case composeFileNotFound
    case readFailed(String)
    case writeFailed(String)
    case restartFailed(String)
}

public final class DockerComposeService {
    private let shell: ShellRunner
    private let dockerPath: String

    public init(shell: ShellRunner = ProcessShellRunner(),
                dockerPath: String = "/opt/homebrew/bin/docker") {
        self.shell = shell
        self.dockerPath = dockerPath
    }

    // MARK: - Static helpers (testable)

    public static func findComposeFile(for container: DockerContainer) -> URL? {
        let workingDir = container.labelValue(forKey: "com.docker.compose.project.working_dir")
        let configFiles = container.labelValue(forKey: "com.docker.compose.project.config_files")
        guard let dir = workingDir, !dir.isEmpty,
              let cfgRaw = configFiles, !cfgRaw.isEmpty else { return nil }
        let cfg = cfgRaw.split(separator: ",").first.map(String.init) ?? cfgRaw
        if cfg.hasPrefix("/") { return URL(fileURLWithPath: cfg) }
        return URL(fileURLWithPath: dir).appendingPathComponent(cfg)
    }

    public static func listProjects(from containers: [DockerContainer]) -> [ComposeProject] {
        var seen = Set<String>()
        return containers.compactMap { container -> ComposeProject? in
            guard let name = container.composeProject,
                  !seen.contains(name),
                  let dir = container.labelValue(forKey: "com.docker.compose.project.working_dir"),
                  let url = findComposeFile(for: container)
            else { return nil }
            seen.insert(name)
            return ComposeProject(name: name, workingDir: dir, configFile: url)
        }
    }

    // MARK: - File I/O

    public func readComposeFile(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw DockerComposeError.readFailed(error.localizedDescription)
        }
    }

    public func saveAndRestart(content: String, project: ComposeProject) throws {
        do {
            try content.write(to: project.configFile, atomically: true, encoding: .utf8)
        } catch {
            throw DockerComposeError.writeFailed(error.localizedDescription)
        }
        let result = shell.run(dockerPath, args: [
            "compose", "-f", project.configFile.path, "up", "-d", "--build"
        ])
        guard result.exitCode == 0 else {
            throw DockerComposeError.restartFailed(result.error)
        }
    }
}

/// Decides what the compose editor shows after the project list or the loaded project changes.
public enum ComposeEditorPlan {
    public struct Result: Equatable {
        /// Picker entries, sorted; may include the loaded project after it disappeared ("detached").
        public let entries: [ComposeProject]
        /// Project to select; nil means the empty state.
        public let selection: ComposeProject?
        /// Whether the selected project's file must be (re)loaded into the editor.
        public let reload: Bool
    }

    public static func reconcile(available: [ComposeProject],
                                 loaded: ComposeProject?,
                                 dirty: Bool) -> Result {
        let sorted = available.sorted { $0.name < $1.name }
        if let loaded, sorted.contains(loaded) {
            return Result(entries: sorted, selection: loaded, reload: false)
        }
        if let loaded, dirty {
            // Unsaved edits: keep the project and its text until the user saves or discards.
            let entries = (sorted + [loaded]).sorted { $0.name < $1.name }
            return Result(entries: entries, selection: loaded, reload: false)
        }
        return Result(entries: sorted, selection: sorted.first, reload: sorted.first != nil)
    }
}
