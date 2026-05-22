// Sources/ColimaBar/DashboardViewController.swift
import AppKit
import ColimaBarCore

final class DashboardViewController: NSSplitViewController {
    let sidebarVC = SidebarViewController()
    private let contentContainer = NSViewController()
    private var currentContentVC: NSViewController?

    var manager: ColimaManager?

    private lazy var containersVC: ContainersPanelViewController = {
        let vc = ContainersPanelViewController()
        wireContainersCallbacks(vc)
        return vc
    }()
    lazy var volumeVC: VolumeBrowserViewController = VolumeBrowserViewController()
    lazy var composeVC: ComposeEditorViewController = ComposeEditorViewController()
    lazy var logsVC: EnhancedLogsViewController = EnhancedLogsViewController()
    lazy var snapshotVC: SnapshotViewController = SnapshotViewController()
    private lazy var settingsVC: SettingsPanelViewController = {
        let vc = SettingsPanelViewController()
        wireSettingsCallbacks(vc)
        return vc
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebar.minimumThickness = 180
        sidebar.maximumThickness = 180
        addSplitViewItem(sidebar)

        contentContainer.view = NSView()
        addSplitViewItem(NSSplitViewItem(viewController: contentContainer))

        sidebarVC.onSelectionChange = { [weak self] index in
            self?.showContent(for: index)
        }
        showContent(for: 0)
    }

    func update(state: ColimaAppState) {
        if currentContentVC === containersVC {
            containersVC.update(containers: state.containers, usage: state.usage,
                                containerStats: state.containerStats,
                                restartPolicies: state.restartPolicies)
        }
        volumeVC.updateContainers(state.containers)
        composeVC.updateContainers(state.containers)
        logsVC.updateContainers(state.containers)
        if case .running = state.colima {
            settingsVC.isColimaRunning = true
        } else {
            settingsVC.isColimaRunning = false
        }
    }

    func selectSidebarItem(at index: Int) {
        guard index >= 0 && index < 6 else { return }
        sidebarVC.selectItem(at: index)
        showContent(for: index)
    }

    private func showContent(for index: Int) {
        let vc: NSViewController
        switch index {
        case 0: vc = containersVC
        case 1: vc = volumeVC
        case 2: vc = composeVC
        case 3: vc = logsVC
        case 4: vc = snapshotVC
        case 5: vc = settingsVC
        default: return
        }
        guard vc !== currentContentVC else { return }
        currentContentVC?.view.removeFromSuperview()
        currentContentVC?.removeFromParent()
        contentContainer.addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.view.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: contentContainer.view.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: contentContainer.view.bottomAnchor),
            vc.view.leadingAnchor.constraint(equalTo: contentContainer.view.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: contentContainer.view.trailingAnchor),
        ])
        currentContentVC = vc
    }

    private func wireContainersCallbacks(_ vc: ContainersPanelViewController) {
        guard let mgr = manager else { return }
        vc.onStart   = { name in mgr.startContainer(name) { _ in } }
        vc.onStop    = { name in mgr.stopContainer(name) { _ in } }
        vc.onRestart = { name in
            mgr.stopContainer(name) { result in
                if case .success = result { mgr.startContainer(name) { _ in } }
            }
        }
        vc.onLogs = { [weak self] name in
            self?.selectSidebarItem(at: 3)
            self?.logsVC.showLogs(for: name)
        }
        vc.onShell          = { _, _ in }
        vc.onFetchImages    = { completion in mgr.fetchImages(completion: completion) }
        vc.onDeleteImage    = { id, completion in mgr.deleteImage(id, completion: completion) }
        vc.onPullImage      = { name, completion in mgr.pullImage(name, completion: completion) }
        vc.onFetchVolumes   = { completion in mgr.fetchVolumes(completion: completion) }
        vc.onPruneVolumes   = { completion in mgr.pruneVolumes(completion: completion) }
        vc.onFetchNetworks  = { completion in mgr.fetchNetworks(completion: completion) }
        vc.onPruneNetworks  = { completion in mgr.pruneNetworks(completion: completion) }
        vc.onSetRestartPolicy = { policy, name, completion in
            mgr.setRestartPolicy(policy, container: name, completion: completion)
        }
        vc.onInspect        = { _ in }
        vc.onFetchEnvVars   = { name, completion in mgr.fetchEnvVars(container: name, completion: completion) }
    }

    private func wireSettingsCallbacks(_ vc: SettingsPanelViewController) {
        vc.isLoginItemEnabled = (NSApp.delegate as? AppDelegate)?.isLoginItemEnabled() ?? false
        vc.onApplyConfig     = { [weak self] in self?.restartColima() }
        vc.onResizeDisk      = { [weak self] in self?.restartColima() }
        vc.onToggleLoginItem = {
            (NSApp.delegate as? AppDelegate)?.toggleLoginItem()
        }
        vc.onSetLanguage = { _ in }
    }

    private func restartColima() {
        guard let mgr = manager else { return }
        mgr.stopColima(onTransition: { _ in }, completion: { result in
            if case .success = result {
                mgr.startColima(onTransition: { _ in }, completion: { _ in })
            }
        })
    }
}
