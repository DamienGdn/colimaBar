import AppKit
import ServiceManagement
import UserNotifications
import ColimaBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: ColimaManager!
    private(set) var store: AppStore!
    var statusBarController: StatusBarController!
    var dashboardWindowController: DashboardWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()
        manager = ColimaManager()
        store = AppStore(manager: manager)
        statusBarController = StatusBarController(store: store)
        dashboardWindowController = DashboardWindowController(store: store)
        manager.startPolling()
        if ColimaConfig.autoStartOnLaunch {
            store.startColima(silent: true)
        }
        manager.checkForColimaUpdate { [weak self] newVersion in
            guard let version = newVersion else { return }
            self?.store.updateVersion = version
        }
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
        content.title = "Colima Desktop"
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
        content.title = "Colima Desktop"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: L.t("Colima + Docker dans votre barre de menus.",
                            "Colima + Docker in your menu bar."),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]),
        ])
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
