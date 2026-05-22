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

    // Supports both single-JSON and NDJSON (one object per line) output from `colima list --json`.
    public static func parseListJSON(_ json: String, instanceName: String = "default") -> ColimaListEntry? {
        let lines = json.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(ColimaListEntry.self, from: data)
            else { continue }
            if entry.name == instanceName { return entry }
        }
        // Fallback: single JSON blob
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ColimaListEntry.self, from: data)
    }

    public static func portainerExistsInOutput(_ output: String) -> Bool {
        let lines = output.components(separatedBy: .newlines)
        return lines.contains {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t == "portainer" || t == "/portainer"
        }
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
                    image: c.Image,
                    ports: c.Ports ?? ""
                )
            }
    }

    // Parses `docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"` → per-container dict.
    public static func parseContainerStats(_ output: String) -> [String: ResourceUsage] {
        var result: [String: ResourceUsage] = [:]
        for line in output.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let name   = parts[0].trimmingCharacters(in: .whitespaces)
            let cpuStr = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
            guard let cpu = Double(cpuStr) else { continue }
            let memParts = parts[2].trimmingCharacters(in: .whitespaces).components(separatedBy: " / ")
            guard memParts.count >= 2 else { continue }
            let used  = parseSizeMiB(memParts[0].trimmingCharacters(in: .whitespaces))
            let total = parseSizeGiB(memParts[1].trimmingCharacters(in: .whitespaces))
            guard total > 0 else { continue }
            result[name] = ResourceUsage(cpuPercent: cpu, memUsedMiB: used, memTotalGiB: total)
        }
        return result
    }

    // Parses `docker images --format '{{json .}}'` NDJSON output.
    public static func parseDockerImages(_ output: String) -> [DockerImage] {
        output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8),
                      let j = try? JSONDecoder().decode(DockerImageJSON.self, from: data)
                else { return nil }
                return DockerImage(id: j.ID, repository: j.Repository, tag: j.Tag,
                                   size: j.Size, created: j.CreatedSince)
            }
    }

    // Parses `docker volume ls --format '{{json .}}'` (lsOutput) for name+driver,
    // cross-references `docker system df -v` (dfOutput) for sizes.
    public static func parseDockerVolumes(_ lsOutput: String, _ dfOutput: String,
                                          _ psOutput: String = "") -> [DockerVolume] {
        // Parse volume ls → name + driver
        var volumes: [(name: String, driver: String)] = []
        for line in lsOutput.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
            guard let data = line.data(using: .utf8),
                  let v = try? JSONDecoder().decode(DockerVolumeLSJSON.self, from: data)
            else { continue }
            volumes.append((name: v.Name, driver: v.Driver))
        }

        // Parse df output for sizes: find "VOLUME NAME" header, then read name+size per line
        var sizes: [String: String] = [:]
        var inVolumeSection = false
        for line in dfOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("VOLUME NAME") { inVolumeSection = true; continue }
            guard inVolumeSection, !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 3, let name = parts.first, let size = parts.last {
                sizes[String(name)] = String(size)
            }
        }

        // Parse `docker ps -a --format '{{.Names}}\t{{.Mounts}}'` → volume→[containers] mapping
        // Named volumes don't start with '/' and don't contain ':'
        var volumeContainers: [String: [String]] = [:]
        for line in psOutput.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let containerName = parts[0].trimmingCharacters(in: .whitespaces)
            let mounts = parts[1].components(separatedBy: ",")
            for mount in mounts {
                let m = mount.trimmingCharacters(in: .whitespaces)
                guard !m.isEmpty, !m.hasPrefix("/"), !m.contains(":") else { continue }
                volumeContainers[m, default: []].append(containerName)
            }
        }

        return volumes.map { v in
            DockerVolume(name: v.name, driver: v.driver,
                         size: sizes[v.name] ?? "N/A",
                         containers: volumeContainers[v.name] ?? [])
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

    // MARK: - Polling (adaptive: 5s when running, 30s when stopped)

    private var pollingActive = false
    private var isCurrentlyRunning = false

    public func startPolling() {
        pollingActive = true
        pollOnce()
    }

    public func stopPolling() {
        pollingActive = false
        timer?.cancel()
        timer = nil
    }

    private func pollOnce() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self, self.pollingActive else { return }
            let state = self.fetchStateSync()
            self.isCurrentlyRunning = state.colima == .running
            DispatchQueue.main.async { self.onStateChange?(state) }
            let interval: TimeInterval = self.isCurrentlyRunning ? 5.0 : 30.0
            let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
            t.schedule(deadline: .now() + interval)
            t.setEventHandler { [weak self] in
                t.cancel()
                self?.pollOnce()
            }
            t.resume()
            self.timer = t
        }
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
            let startTime = Date()
            let cpus     = ColimaConfig.desiredCPUs
            let mem      = ColimaConfig.desiredMemoryGB
            let disk     = ColimaConfig.desiredDiskGB
            let instance = ColimaConfig.activeInstanceName
            var args = ["start"]
            if instance != "default" { args.append(instance) }
            args += ["--cpu", "\(cpus)", "--memory", "\(mem)", "--disk", "\(disk)"]
            let result = self.shell.run(self.colimaPath, args: args)
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
            let duration = Date().timeIntervalSince(startTime)
            let base = self.fetchStateSync()
            let state = ColimaAppState(
                colima: base.colima,
                cpus: base.cpus,
                memoryGB: base.memoryGB,
                portainerExists: base.portainerExists,
                usage: base.usage,
                containers: base.containers,
                startDuration: duration
            )
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
            let instance = ColimaConfig.activeInstanceName
            var args = ["stop"]
            if instance != "default" { args.append(instance) }
            let result = self.shell.run(self.colimaPath, args: args)
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

    public func startContainer(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.dockerPath, args: ["start", name])
            if result.exitCode == 0 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let msg = result.error.isEmpty
                    ? "\(L.t("Impossible de démarrer", "Failed to start")) \(name)"
                    : result.error
                DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
            }
        }
    }

    public func stopContainer(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.dockerPath, args: ["stop", name])
            if result.exitCode == 0 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let msg = result.error.isEmpty
                    ? "\(L.t("Impossible d'arrêter", "Failed to stop")) \(name)"
                    : result.error
                DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
            }
        }
    }

    // Checks brew outdated colima once. Returns new version string or nil if up to date.
    public func checkForColimaUpdate(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let result = self.shell.run("/opt/homebrew/bin/brew", args: ["outdated", "colima", "--json"])
            guard result.exitCode == 0, !result.output.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            struct BrewFormula: Codable { let name: String; let current_version: String }
            struct BrewOutdated: Codable { let formulae: [BrewFormula] }
            if let data = result.output.data(using: .utf8),
               let outdated = try? JSONDecoder().decode(BrewOutdated.self, from: data),
               let colima = outdated.formulae.first(where: { $0.name == "colima" }) {
                DispatchQueue.main.async { completion(colima.current_version) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // Synchronous stop — called from applicationWillTerminate where async is not possible.
    public func stopColimaSync() {
        let state = fetchStateSync()
        guard state.colima == .running else { return }
        let instance = ColimaConfig.activeInstanceName
        var args = ["stop"]
        if instance != "default" { args.append(instance) }
        _ = shell.run(colimaPath, args: args)
    }

    public func pruneDocker(completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.dockerPath, args: ["system", "prune", "-f"])
            if result.exitCode == 0 {
                DispatchQueue.main.async { completion(.success(result.output)) }
            } else {
                let msg = result.error.isEmpty ? "docker system prune failed" : result.error
                DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
            }
        }
    }

    public func fetchImages(completion: @escaping ([DockerImage]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.dockerPath, args: ["images", "--format", "{{json .}}"])
            let images = result.exitCode == 0 ? Self.parseDockerImages(result.output) : []
            DispatchQueue.main.async { completion(images) }
        }
    }

    public func deleteImage(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.dockerPath, args: ["rmi", id])
            if result.exitCode == 0 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let msg = result.error.isEmpty ? "docker rmi \(id) failed" : result.error
                DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
            }
        }
    }

    public func pullImage(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.dockerPath, args: ["pull", name])
            if result.exitCode == 0 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let msg = result.error.isEmpty ? "docker pull \(name) failed" : result.error
                DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
            }
        }
    }

    public func fetchVolumes(completion: @escaping ([DockerVolume]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let lsResult = self.shell.run(self.dockerPath, args: ["volume", "ls", "--format", "{{json .}}"])
            let dfResult = self.shell.run(self.dockerPath, args: ["system", "df", "-v"])
            let psResult = self.shell.run(self.dockerPath, args: ["ps", "-a", "--format", "{{.Names}}\t{{.Mounts}}"])
            let volumes = Self.parseDockerVolumes(lsResult.output, dfResult.output, psResult.output)
            DispatchQueue.main.async { completion(volumes) }
        }
    }

    public func pruneVolumes(completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.dockerPath, args: ["volume", "prune", "-f"])
            if result.exitCode == 0 {
                DispatchQueue.main.async { completion(.success(result.output)) }
            } else {
                let msg = result.error.isEmpty ? "docker volume prune failed" : result.error
                DispatchQueue.main.async { completion(.failure(ShellError(message: msg))) }
            }
        }
    }

    // MARK: - Private helpers

    private func waitForSocket() {
        let instance   = ColimaConfig.activeInstanceName
        let socketPath = NSHomeDirectory() + "/.colima/\(instance)/docker.sock"
        var attempts = 0
        while !FileManager.default.fileExists(atPath: socketPath) && attempts < 60 {
            Thread.sleep(forTimeInterval: 1)
            attempts += 1
        }
    }

    // MARK: - State fetch

    public func fetchContainerStats(name: String, completion: @escaping (ResourceUsage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell.run(self.dockerPath, args: [
                "stats", "--no-stream", "--format", "{{.CPUPerc}}\t{{.MemUsage}}", name
            ])
            let usage = result.exitCode == 0 ? Self.parseDockerStats(result.output) : nil
            DispatchQueue.main.async { completion(usage) }
        }
    }

    public func fetchStateSync() -> ColimaAppState {
        let listResult = shell.run(colimaPath, args: ["list", "--json"])
        guard let entry = Self.parseListJSON(listResult.output, instanceName: ColimaConfig.activeInstanceName) else {
            return .unknown
        }

        let isRunning = entry.status.lowercased() == "running"
        let memoryGB = Double(entry.memory) / 1_073_741_824

        var portainerExists = false
        var usage: ResourceUsage? = nil
        var containerStats: [String: ResourceUsage] = [:]
        var containers: [DockerContainer] = []
        if isRunning {
            let r = shell.run(dockerPath, args: [
                "ps", "-a",
                "--filter", "name=^portainer$",
                "--format", "{{.Names}}"
            ])
            portainerExists = Self.portainerExistsInOutput(r.output)

            let statsResult = shell.run(dockerPath, args: [
                "stats", "--no-stream", "--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
            ])
            let perContainer = Self.parseContainerStats(statsResult.output)
            containerStats = perContainer
            if !perContainer.isEmpty {
                let totalCPU    = perContainer.values.reduce(0) { $0 + $1.cpuPercent }
                let totalMemMiB = perContainer.values.reduce(0) { $0 + $1.memUsedMiB }
                let limitGiB    = perContainer.values.first?.memTotalGiB ?? 0
                usage = ResourceUsage(cpuPercent: totalCPU, memUsedMiB: totalMemMiB, memTotalGiB: limitGiB)
            }

            let containerResult = shell.run(dockerPath, args: ["ps", "-a", "--format", "{{json .}}"])
            containers = Self.parseDockerContainers(containerResult.output)
        }

        return ColimaAppState(
            colima: isRunning ? .running : .stopped,
            cpus: entry.cpus,
            memoryGB: memoryGB,
            portainerExists: portainerExists,
            usage: usage,
            containerStats: containerStats,
            containers: containers
        )
    }
}

// MARK: - ShellError

public struct ShellError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
