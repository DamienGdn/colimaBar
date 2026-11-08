import Foundation

public struct MetricHistory: Equatable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int = 60) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
}

public struct MetricHistoryStore {
    public let capacity: Int
    public private(set) var cpu: [String: MetricHistory] = [:]
    public private(set) var mem: [String: MetricHistory] = [:]

    public init(capacity: Int = 60) {
        self.capacity = capacity
    }

    public mutating func record(_ stats: [String: ResourceUsage]) {
        cpu = cpu.filter { stats[$0.key] != nil }
        mem = mem.filter { stats[$0.key] != nil }
        for (name, u) in stats {
            cpu[name, default: MetricHistory(capacity: capacity)].append(u.cpuPercent)
            mem[name, default: MetricHistory(capacity: capacity)].append(u.memUsedMiB)
        }
    }
}
