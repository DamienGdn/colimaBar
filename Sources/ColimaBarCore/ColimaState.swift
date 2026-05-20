import Foundation

public enum ColimaRunningState: Equatable {
    case running
    case stopped
    case transitioning(String)
    case unknown
}

public struct ColimaAppState: Equatable {
    public let colima: ColimaRunningState
    public let cpus: Int?
    public let memoryGB: Double?
    public let portainerExists: Bool

    public init(
        colima: ColimaRunningState,
        cpus: Int? = nil,
        memoryGB: Double? = nil,
        portainerExists: Bool = false
    ) {
        self.colima = colima
        self.cpus = cpus
        self.memoryGB = memoryGB
        self.portainerExists = portainerExists
    }

    public static let unknown = ColimaAppState(
        colima: .unknown, cpus: nil, memoryGB: nil, portainerExists: false
    )
}

public struct ColimaListEntry: Codable {
    public let name: String
    public let status: String
    public let cpus: Int
    public let memory: Int64
}
