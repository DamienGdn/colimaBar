import Foundation

public struct DockerContainer: Equatable {
    public enum ContainerState: String, Equatable {
        case running, exited, paused, restarting, dead, created, removing
        case unknown
    }

    public enum HealthStatus: String, Equatable {
        case healthy, unhealthy, starting
    }

    public let id: String
    public let name: String
    public let state: ContainerState
    public let status: String
    public let image: String
    public let ports: String

    public init(id: String, name: String, state: ContainerState, status: String, image: String, ports: String) {
        self.id = id
        self.name = name
        self.state = state
        self.status = status
        self.image = image
        self.ports = ports
    }

    public var isRunning: Bool { state == .running }

    public var health: HealthStatus? {
        if status.contains("(healthy)")          { return .healthy }
        if status.contains("(unhealthy)")        { return .unhealthy }
        if status.contains("(health: starting)") { return .starting }
        return nil
    }

    // Extracts unique host port numbers: "0.0.0.0:8000->8000/tcp, :::9443->9443/tcp" → "8000, 9443"
    public var hostPorts: String {
        guard !ports.isEmpty else { return "" }
        var seen = Set<String>()
        let nums = ports.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { part -> String? in
                guard let arrow = part.range(of: "->"),
                      let colon = part[..<arrow.lowerBound].lastIndex(of: ":") else { return nil }
                return String(part[part.index(after: colon)..<arrow.lowerBound])
            }
            .filter { seen.insert($0).inserted }
        return nums.joined(separator: ", ")
    }

    // Extracts unique host port numbers as [Int]
    public var hostPortNumbers: [Int] {
        hostPorts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { Int($0) }
    }
}

struct DockerContainerJSON: Codable {
    let ID: String
    let Names: String
    let State: String
    let Status: String
    let Image: String
    let Ports: String?
}
