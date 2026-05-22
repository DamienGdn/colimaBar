import Foundation

public enum ColimaRunningState: Equatable {
    case running
    case stopped
    case transitioning(String)
    case unknown
}

public struct ResourceUsage: Equatable {
    public let cpuPercent: Double      // sum across all running containers
    public let memUsedMiB: Double
    public let memTotalGiB: Double

    public var memUsedFormatted: String {
        memUsedMiB >= 1024
            ? String(format: "%.1f GB", memUsedMiB / 1024)
            : String(format: "%.0f MB", memUsedMiB)
    }

    public var memUsedPercent: Double {
        memTotalGiB > 0 ? (memUsedMiB / (memTotalGiB * 1024)) * 100 : 0
    }
}

public struct ColimaAppState: Equatable {
    public let colima: ColimaRunningState
    public let cpus: Int?
    public let memoryGB: Double?
    public let portainerExists: Bool
    public let usage: ResourceUsage?
    public let containerStats: [String: ResourceUsage]
    public let containers: [DockerContainer]
    public let startDuration: TimeInterval?
    public let restartPolicies: [String: String]

    public init(
        colima: ColimaRunningState,
        cpus: Int? = nil,
        memoryGB: Double? = nil,
        portainerExists: Bool = false,
        usage: ResourceUsage? = nil,
        containerStats: [String: ResourceUsage] = [:],
        containers: [DockerContainer] = [],
        startDuration: TimeInterval? = nil,
        restartPolicies: [String: String] = [:]
    ) {
        self.colima = colima
        self.cpus = cpus
        self.memoryGB = memoryGB
        self.portainerExists = portainerExists
        self.usage = usage
        self.containerStats = containerStats
        self.containers = containers
        self.startDuration = startDuration
        self.restartPolicies = restartPolicies
    }

    public static let unknown = ColimaAppState(colima: .unknown)
}

public struct ColimaListEntry: Codable {
    public let name: String
    public let status: String
    public let cpus: Int
    public let memory: Int64
}
