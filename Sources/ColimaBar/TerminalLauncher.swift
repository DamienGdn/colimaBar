import AppKit
import ColimaBarCore

/// Runs commands in Terminal.app (shell into a container, brew upgrade…).
enum TerminalLauncher {

    static func run(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Terminal\" to do script \"\(escaped)\""]
        try? process.run()
    }

    static func openShell(container name: String, command: String) {
        run("docker exec -it \(name) \(command)")
    }

    /// Asks for the command to run (default `sh`), then opens it in Terminal.
    static func promptShell(container name: String) {
        let alert = NSAlert()
        alert.messageText = "Shell into \(name)"
        alert.informativeText = L.t("Commande à exécuter :", "Command to execute:")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        field.stringValue = "sh"
        alert.accessoryView = field
        alert.addButton(withTitle: L.t("Exécuter", "Run"))
        alert.addButton(withTitle: L.t("Annuler", "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let cmd = field.stringValue.trimmingCharacters(in: .whitespaces)
        openShell(container: name, command: cmd.isEmpty ? "sh" : cmd)
    }
}
