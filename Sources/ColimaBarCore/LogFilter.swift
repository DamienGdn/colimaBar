// Sources/ColimaBarCore/LogFilter.swift
import Foundation

public enum LogLevel: Equatable {
    case error, warning, success, normal
}

public struct FilteredLogLine: Equatable {
    public let text: String
    public let level: LogLevel

    public init(text: String, level: LogLevel) {
        self.text = text
        self.level = level
    }
}

public struct LogFilter {
    public static func apply(lines: [String], query: String) -> [FilteredLogLine] {
        let filtered = query.isEmpty
            ? lines
            : lines.filter { $0.localizedCaseInsensitiveContains(query) }
        return filtered.map { line in
            FilteredLogLine(text: line, level: classify(line))
        }
    }

    public static func extractErrorLines(from lines: [String], max: Int) -> [String] {
        Array(lines.filter { classify($0) == .error }.prefix(max))
    }

    private static func classify(_ line: String) -> LogLevel {
        let upper = line.uppercased()
        if upper.contains("ERROR") || upper.contains("FATAL") || upper.contains("EXCEPTION") {
            return .error
        }
        if upper.contains("WARN") { return .warning }
        if upper.contains("SUCCESS") || upper.contains(" OK") || upper.hasPrefix("OK") {
            return .success
        }
        return .normal
    }
}

public enum LogTargets {
    /// Containers whose logs can be shown: running ones first, then stopped ones, each by name.
    /// `docker logs` works on exited containers too.
    public static func order(_ containers: [DockerContainer]) -> [DockerContainer] {
        containers.sorted { a, b in
            a.isRunning != b.isRunning ? a.isRunning : a.name < b.name
        }
    }
}
