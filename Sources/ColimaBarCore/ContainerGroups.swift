import Foundation

public enum StackStatus: Equatable {
    case allRunning
    case partial(running: Int, total: Int)
    case stopped
}

public struct StackGroup: Equatable {
    public let name: String
    public let containers: [DockerContainer]
    public let status: StackStatus
    public let cpuPercent: Double
    public let memUsedMiB: Double

    public init(name: String, containers: [DockerContainer], status: StackStatus, cpuPercent: Double, memUsedMiB: Double) {
        self.name = name
        self.containers = containers
        self.status = status
        self.cpuPercent = cpuPercent
        self.memUsedMiB = memUsedMiB
    }
}

public enum ContainerGrouping {
    public static func group(_ containers: [DockerContainer],
                             stats: [String: ResourceUsage]) -> (stacks: [StackGroup], standalone: [DockerContainer]) {
        let byName: (DockerContainer, DockerContainer) -> Bool = { $0.name < $1.name }
        var projects: [String: [DockerContainer]] = [:]
        var standalone: [DockerContainer] = []
        for c in containers {
            if let p = c.composeProject { projects[p, default: []].append(c) } else { standalone.append(c) }
        }
        let stacks = projects.keys.sorted().map { name -> StackGroup in
            let members = projects[name]!.sorted(by: byName)
            let running = members.filter { $0.isRunning }.count
            let status: StackStatus = running == 0 ? .stopped
                : running == members.count ? .allRunning
                : .partial(running: running, total: members.count)
            let used = members.compactMap { stats[$0.name] }
            return StackGroup(name: name, containers: members, status: status,
                              cpuPercent: used.reduce(0) { $0 + $1.cpuPercent },
                              memUsedMiB: used.reduce(0) { $0 + $1.memUsedMiB })
        }
        return (stacks, standalone.sorted(by: byName))
    }

    /// Groups then filters by a case-insensitive query (name, image, compose service).
    /// A stack whose name matches keeps all its members; otherwise it keeps only its
    /// matching members and is rebuilt so counts, status and totals reflect what is shown.
    public static func filtered(_ containers: [DockerContainer],
                                stats: [String: ResourceUsage],
                                query: String) -> (stacks: [StackGroup], standalone: [DockerContainer]) {
        let grouped = group(containers, stats: stats)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return grouped }
        func matches(_ c: DockerContainer) -> Bool {
            [c.name, c.image, c.labelValue(forKey: "com.docker.compose.service")]
                .contains { $0?.lowercased().contains(q) ?? false }
        }
        let stacks = grouped.stacks.compactMap { stack -> StackGroup? in
            if stack.name.lowercased().contains(q) { return stack }
            let kept = stack.containers.filter(matches)
            return kept.isEmpty ? nil : group(kept, stats: stats).stacks.first
        }
        return (stacks, grouped.standalone.filter(matches))
    }
}
