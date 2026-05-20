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

    // MARK: - Polling

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

    // MARK: - Actions

    public func startColima(
        onTransition: @escaping (ColimaAppState) -> Void,
        completion: @escaping (Result<ColimaAppState, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            onTransition(ColimaAppState(colima: .transitioning("Démarrage…"), cpus: nil, memoryGB: nil, portainerExists: false))
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let cpus = ColimaConfig.desiredCPUs
            let mem = ColimaConfig.desiredMemoryGB
            let result = self.shell.run(self.colimaPath, args: [
                "start",
                "--cpu", "\(cpus)",
                "--memory", "\(mem)"
            ])
            guard result.exitCode == 0 else {
                let err = ShellError(message: result.error.isEmpty ? "Échec démarrage Colima" : result.error)
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            self.waitForSocket()
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

    // MARK: - Private helpers

    private func waitForSocket() {
        let socketPath = NSHomeDirectory() + "/.colima/default/docker.sock"
        var attempts = 0
        while !FileManager.default.fileExists(atPath: socketPath) && attempts < 60 {
            Thread.sleep(forTimeInterval: 1)
            attempts += 1
        }
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

// MARK: - ShellError

public struct ShellError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
