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

    public var isRunning: Bool { state == .running }
}

struct DockerContainerJSON: Codable {
    let ID: String
    let Names: String
    let State: String
    let Status: String
    let Image: String
}
