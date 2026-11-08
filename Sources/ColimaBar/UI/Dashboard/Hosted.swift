import SwiftUI
import AppKit
import ColimaBarCore

/// Hosts an AppKit view controller inside SwiftUI.
struct HostedVC<VC: NSViewController>: NSViewControllerRepresentable {
    let make: () -> VC
    var update: (VC) -> Void = { _ in }

    func makeNSViewController(context: Context) -> VC { make() }
    func updateNSViewController(_ vc: VC, context: Context) { update(vc) }
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
