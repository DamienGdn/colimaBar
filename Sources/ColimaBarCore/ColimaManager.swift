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

    // MARK: - Static parsers

    public static func parseListJSON(_ json: String) -> ColimaListEntry? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ColimaListEntry.self, from: data)
    }

    public static func portainerExistsInOutput(_ output: String) -> Bool {
        let lines = output.components(separatedBy: .newlines)
        return lines.contains { $0.trimmingCharacters(in: .whitespaces) == "portainer" }
    }

    // MARK: - State fetch

    public func fetchStateSync() -> ColimaAppState {
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
}
