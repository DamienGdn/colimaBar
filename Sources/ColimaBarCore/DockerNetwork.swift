import Foundation

public struct DockerNetwork: Equatable {
    public let id: String
    public let name: String
    public let driver: String
    public let scope: String
}

struct DockerNetworkJSON: Codable {
    let ID: String
    let Name: String
    let Driver: String
    let Scope: String
}
