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

    // Parses `docker ps -a --format '{{json .}}'` output (one JSON object per line).
    public static func parseDockerContainers(_ output: String) -> [DockerContainer] {
        output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8),
                      let c = try? JSONDecoder().decode(DockerContainerJSON.self, from: data)
                else { return nil }
                let name = c.Names.hasPrefix("/") ? String(c.Names.dropFirst()) : c.Names
                return DockerContainer(
                    id: c.ID,
                    name: name,
                    state: DockerContainer.ContainerState(rawValue: c.State) ?? .unknown,
                    status: c.Status,
                    image: c.Image
                )
            }
    }

    // Parses `docker stats --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}"` output.
    public static func parseDockerStats(_ output: String) -> ResourceUsage? {
        var totalCPU = 0.0
        var totalMemMiB = 0.0
        var limitGiB = 0.0

        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        for line in lines {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }

            let cpuStr = parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
            if let cpu = Double(cpuStr) { totalCPU += cpu }

            let memParts = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " / ")
            if memParts.count >= 2 {
                totalMemMiB += parseSizeMiB(memParts[0].trimmingCharacters(in: .whitespaces))
                if limitGiB == 0 { limitGiB = parseSizeGiB(memParts[1].trimmingCharacters(in: .whitespaces)) }
            }
        }

        guard limitGiB > 0 else { return nil }
        return ResourceUsage(cpuPercent: totalCPU, memUsedMiB: totalMemMiB, memTotalGiB: limitGiB)
    }

    private static func parseSizeMiB(_ s: String) -> Double {
        if s.hasSuffix("GiB"), let v = Double(s.dropLast(3)) { return v * 1024 }
        if s.hasSuffix("MiB"), let v = Double(s.dropLast(3)) { return v }
        if s.hasSuffix("kB"),  let v = Double(s.dropLast(2)) { return v / 1024 }
        if s.hasSuffix("B"),   let v = Double(s.dropLast(1)) { return v / 1_048_576 }
        return 0
    }

    private static func parseSizeGiB(_ s: String) -> Double {
        if s.hasSuffix("GiB"), let v = Double(s.dropLast(3)) { return v }
        if s.hasSuffix("MiB"), let v = Double(s.dropLast(3)) { return v / 1024 }
        return 0
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
            onTransition(ColimaAppState(colima: .transitioning(L.t("Démarrage…", "Starting…"))))
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
                let err = ShellError(message: result.error.isEmpty ? L.t("Échec démarrage Colima", "Failed to start Colima") : result.error)
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
            onTransition(ColimaAppState(colima: .transitioning(L.t("Arrêt…", "Stopping…"))))
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.colimaPath, args: ["stop"])
            guard result.exitCode == 0 else {
                let err = ShellError(message: result.error.isEmpty ? L.t("Échec arrêt Colima", "Failed to stop Colima") : result.error)
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
                let msg = result.error.isEmpty ? L.t("Échec installation Portainer", "Failed to install Portainer") : String(result.error.prefix(200))
                DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
            }
        }
    }

    // Synchronous stop — called from applicationWillTerminate where async is not possible.
    public func stopColimaSync() {
        let state = fetchStateSync()
        guard state.colima == .running else { return }
        _ = shell.run(colimaPath, args: ["stop"])
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
        var usage: ResourceUsage? = nil
        if isRunning {
            let r = shell.run(dockerPath, args: [
                "ps", "-a",
                "--filter", "name=^portainer$",
                "--format", "{{.Names}}"
            ])
            portainerExists = Self.portainerExistsInOutput(r.output)

            let statsResult = shell.run(dockerPath, args: [
                "stats", "--no-stream", "--format", "{{.CPUPerc}}\t{{.MemUsage}}"
            ])
            usage = Self.parseDockerStats(statsResult.output)
        }

        return ColimaAppState(
            colima: isRunning ? .running : .stopped,
            cpus: entry.cpus,
            memoryGB: memoryGB,
            portainerExists: portainerExists,
            usage: usage
        )
    }
}

// MARK: - ShellError

public struct ShellError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
