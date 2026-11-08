// Sources/ColimaBar/DashboardWindowController.swift
import AppKit
import SwiftUI

final class DashboardWindowController: NSWindowController {
    init(store: AppStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Colima Desktop"
        // Brand header runs under a transparent title bar.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 900, height: 560)
        window.contentViewController = NSHostingController(
            rootView: DashboardRootView().environmentObject(store))
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()
        super.init(window: window)
        window.delegate = self
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
