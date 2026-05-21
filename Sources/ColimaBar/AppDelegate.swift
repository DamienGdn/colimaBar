import AppKit
import ServiceManagement
import UserNotifications
import ColimaBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: ColimaManager!
    var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()
        manager = ColimaManager()
        statusBarController = StatusBarController(manager: manager)
        manager.startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopPolling()
        manager.stopColimaSync()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func showError(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "ColimaBar"
        content.body = message
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func showSuccess(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "ColimaBar"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Login item

    func isLoginItemEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func toggleLoginItem() {
        do {
            if isLoginItemEnabled() {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError(L.t("Impossible de modifier le démarrage automatique : \(error.localizedDescription)",
                          "Unable to change login item: \(error.localizedDescription)"))
        }
    }
}
