// Sources/ColimaBar/DashboardWindowController.swift
import AppKit
import Combine
import ColimaBarCore

final class DashboardWindowController: NSWindowController {
    private let dashboardVC: DashboardViewController
    private var cancellables = Set<AnyCancellable>()

    init(store: AppStore) {
        dashboardVC = DashboardViewController()
        dashboardVC.manager = store.manager

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
        // Legacy AppKit dashboard keeps receiving state until the SwiftUI one replaces it.
        store.$state
            .sink { [weak self] state in self?.dashboardVC.update(state: state) }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func showDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension DashboardWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
