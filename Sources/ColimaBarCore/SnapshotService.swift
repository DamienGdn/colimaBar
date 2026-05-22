// Sources/ColimaBarCore/SnapshotService.swift
import Foundation

public struct ColimaSnapshot: Equatable {
    public let name: String
    public let fileURL: URL
    public let date: Date
    public let sizeBytes: Int64

    public init(name: String, fileURL: URL, date: Date, sizeBytes: Int64) {
        self.name = name
        self.fileURL = fileURL
        self.date = date
        self.sizeBytes = sizeBytes
    }

    public var formattedSize: String {
        let mb = Double(sizeBytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

public enum SnapshotError: Error {
    case colimaStopFailed(String)
    case copyFailed(String)
    case colimaStartFailed(String)
    case deleteFailed(String)
}

public final class SnapshotService {
    private let shell: ShellRunner
    private let colimaPath: String
    private let diskPath: URL
    private let snapshotDir: URL

    public init(
        shell: ShellRunner = ProcessShellRunner(),
        colimaPath: String = "/opt/homebrew/bin/colima",
        diskPath: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".colima/default/disk.qcow2"),
        snapshotDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".colima/snapshots")
    ) {
        self.shell = shell
        self.colimaPath = colimaPath
        self.diskPath = diskPath
        self.snapshotDir = snapshotDir
    }

    // MARK: - Static helpers (testable)

    public static func parseSnapshot(from url: URL) -> ColimaSnapshot? {
        guard url.pathExtension == "qcow2" else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = (attrs?[.modificationDate] as? Date) ?? Date()
        let size = (attrs?[.size] as? Int64) ?? 0
        return ColimaSnapshot(name: name, fileURL: url, date: date, sizeBytes: size)
    }

    public static func snapshotPath(in dir: URL, name: String) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return dir.appendingPathComponent("\(name)_\(timestamp).qcow2")
    }

    // MARK: - Commands (blocking, run on background queue)

    public func listSnapshots() -> [ColimaSnapshot] {
        try? FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: snapshotDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []
        return urls.compactMap { SnapshotService.parseSnapshot(from: $0) }
                   .sorted { $0.date > $1.date }
    }

    public func createSnapshot(name: String) throws {
        let dest = SnapshotService.snapshotPath(in: snapshotDir, name: name)
        try? FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

        let stop = shell.run(colimaPath, args: ["stop"])
        guard stop.exitCode == 0 else { throw SnapshotError.colimaStopFailed(stop.error) }

        let cp = shell.run("/bin/cp", args: ["-a", diskPath.path, dest.path])
        guard cp.exitCode == 0 else {
            _ = shell.run(colimaPath, args: ["start"])
            throw SnapshotError.copyFailed(cp.error)
        }

        let start = shell.run(colimaPath, args: ["start"])
        guard start.exitCode == 0 else { throw SnapshotError.colimaStartFailed(start.error) }
    }

    public func restoreSnapshot(_ snapshot: ColimaSnapshot) throws {
        let stop = shell.run(colimaPath, args: ["stop"])
        guard stop.exitCode == 0 else { throw SnapshotError.colimaStopFailed(stop.error) }

        let cp = shell.run("/bin/cp", args: ["-a", snapshot.fileURL.path, diskPath.path])
        guard cp.exitCode == 0 else {
            _ = shell.run(colimaPath, args: ["start"])
            throw SnapshotError.copyFailed(cp.error)
        }

        let start = shell.run(colimaPath, args: ["start"])
        guard start.exitCode == 0 else { throw SnapshotError.colimaStartFailed(start.error) }
    }

    public func deleteSnapshot(_ snapshot: ColimaSnapshot) throws {
        do {
            try FileManager.default.removeItem(at: snapshot.fileURL)
        } catch {
            throw SnapshotError.deleteFailed(error.localizedDescription)
        }
    }
}
