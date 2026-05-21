import Foundation

public struct DockerVolume: Equatable {
    public let name: String
    public let driver: String
    public let size: String    // e.g. "1.2GB" or "N/A"
}

struct DockerVolumeLSJSON: Codable {
    let Name: String
    let Driver: String
}
