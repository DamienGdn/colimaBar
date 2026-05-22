// Sources/ColimaBar/DashboardWindowController.swift
import AppKit
import ColimaBarCore

final class DashboardWindowController: NSWindowController {
    private let dashboardVC: DashboardViewController

    init(manager: ColimaManager) {
        dashboardVC = DashboardViewController()
        dashboardVC.manager = manager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Colima Desktop"
        window.center()
        window.contentViewController = dashboardVC
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func showDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(state: ColimaAppState) {
        dashboardVC.update(state: state)
    }
}

extension DashboardWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
