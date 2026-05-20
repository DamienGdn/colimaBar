import Foundation

public protocol ShellRunner: AnyObject {
    func run(_ executable: String, args: [String]) -> (output: String, error: String, exitCode: Int32)
}

public final class ProcessShellRunner: ShellRunner {
    public init() {}

    public func run(_ executable: String, args: [String]) -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ("", error.localizedDescription, -1)
        }
        process.waitUntilExit()

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (out, err, process.terminationStatus)
    }
}
