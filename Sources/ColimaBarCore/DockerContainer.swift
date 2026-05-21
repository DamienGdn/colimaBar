import Foundation

public struct DockerContainer: Equatable {
    public enum ContainerState: String, Equatable {
        case running, exited, paused, restarting, dead, created, removing
        case unknown
    }

    public let id: String
    public let name: String
    public let state: ContainerState
    public let status: String
    public let image: String
    public let ports: String

    public var isRunning: Bool { state == .running }

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
}

struct DockerContainerJSON: Codable {
    let ID: String
    let Names: String
    let State: String
    let Status: String
    let Image: String
    let Ports: String?
}
