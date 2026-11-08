import SwiftUI
import AppKit
import ColimaBarCore

/// Hosts an AppKit view controller inside SwiftUI.
struct HostedVC<VC: NSViewController>: NSViewControllerRepresentable {
    let make: () -> VC
    var update: (VC) -> Void = { _ in }

    func makeNSViewController(context: Context) -> VC {
        let vc = make()
        // Cached controllers may still be attached to a previous hosting parent.
        Self.detach(vc)
        return vc
    }
    func updateNSViewController(_ vc: VC, context: Context) { update(vc) }

    static func dismantleNSViewController(_ vc: VC, coordinator: ()) { detach(vc) }

    private static func detach(_ vc: VC) {
        if vc.isViewLoaded { vc.view.removeFromSuperview() }
        vc.removeFromParent()
    }
}

/// Single instances of the AppKit modules so they keep their state across navigations.
final class ModuleControllers {
    lazy var logs = EnhancedLogsViewController()
    lazy var snapshots = SnapshotViewController()
    lazy var composeEditor = ComposeEditorViewController()
    lazy var volumeBrowser = VolumeBrowserViewController()

    func updateContainers(_ containers: [DockerContainer]) {
        logs.updateContainers(containers)
        composeEditor.updateContainers(containers)
        volumeBrowser.updateContainers(containers)
    }
}
