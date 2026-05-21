import Foundation

public struct DockerImage: Equatable {
    public let id: String
    public let repository: String
    public let tag: String
    public let size: String       // e.g. "142MB"
    public let created: String    // e.g. "3 weeks ago"
}

struct DockerImageJSON: Codable {
    let ID: String
    let Repository: String
    let Tag: String
    let Size: String
    let CreatedSince: String
}
