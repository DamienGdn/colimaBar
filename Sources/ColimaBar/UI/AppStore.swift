import AppKit
import Combine
import ColimaBarCore

enum DashboardSection: String, CaseIterable, Identifiable {
    case compose, containers, images, volumes, networks, logs, snapshots
    var id: String { rawValue }
}

enum ContentRoute: Equatable {
    case section
    case volumeBrowser(volume: String)
    case composeEditor(stack: String)
}

/// Single source of observable state shared by the status bar, the dashboard and the popover.
final class AppStore: ObservableObject {
    let manager: ColimaManager
    let modules = ModuleControllers()

    @Published private(set) var state: ColimaAppState = .unknown
    @Published private(set) var history = MetricHistoryStore(capacity: 60)
    @Published var section: DashboardSection = .containers
    @Published var route: ContentRoute = .section
    @Published var selectedContainer: String?
    @Published var selectedStack: String?
    @Published var search: String = ""
    @Published var transition: String?
    @Published var updateVersion: String?
    @Published var lastError: String?
    @Published private(set) var images: [DockerImage] = []
    @Published private(set) var volumes: [DockerVolume] = []
    @Published private(set) var networks: [DockerNetwork] = []
    /// Sections whose list has been fetched at least once since Colima came up.
    @Published private(set) var loadedLists: Set<DashboardSection> = []
    @Published private(set) var loadingLists: Set<DashboardSection> = []
    private var reloadPending: Set<DashboardSection> = []
    private var listEpoch = 0

    init(manager: ColimaManager) {
        self.manager = manager
        manager.onStateChange = { [weak self] state in
            self?.apply(state)
        }
    }

    /// Containers grouped by compose stack, filtered by `search` (see `ContainerGrouping.filtered`).
    var groups: (stacks: [StackGroup], standalone: [DockerContainer]) {
        ContainerGrouping.filtered(state.containers, stats: state.containerStats, query: search)
    }

    /// Unfiltered stack (all its members, whatever the search).
    func stack(named name: String) -> StackGroup? {
        ContainerGrouping.stack(named: name, in: state.containers, stats: state.containerStats)
    }

    // MARK: - State

    func apply(_ state: ColimaAppState) {
        // A transient stats failure must not wipe the graphs while containers are running.
        let statsMissing = state.containerStats.isEmpty && state.containers.contains { $0.isRunning }
        if !statsMissing { history.record(state.containerStats) }
        if case .transitioning(let label) = state.colima { transition = label } else { transition = nil }
        self.state = state
        if state.colima != .running && (!loadedLists.isEmpty || !images.isEmpty || !volumes.isEmpty || !networks.isEmpty) {
            listEpoch += 1
            loadedLists = []
            images = []; volumes = []; networks = []
        }
        if state.colima == .running {
            // Drop selections whose container / stack is gone (removed, compose down…).
            let valid = ContainerGrouping.validSelection(container: selectedContainer, stack: selectedStack,
                                                         in: state.containers)
            if valid.container != selectedContainer { selectedContainer = valid.container }
            if valid.stack != selectedStack { selectedStack = valid.stack }
        }
        modules.updateContainers(state.containers)
    }

    /// Header refresh: global state plus the list of the visible section.
    func refreshVisible() {
        refresh()
        switch section {
        case .images: loadImages()
        case .volumes: loadVolumes()
        case .networks: loadNetworks()
        default: break
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let state = self.manager.fetchStateSync()
            DispatchQueue.main.async { self.apply(state) }
        }
    }

    // MARK: - Colima

    func startColima() {
        delegate?.showSuccess(L.t("Démarrage de Colima…", "Starting Colima…"))
        manager.startColima(onTransition: { [weak self] state in
            self?.apply(state)
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let state):
                self.apply(state)
                self.lastError = nil
                let duration = Int(state.startDuration ?? 0)
                let running = state.containers.filter { $0.isRunning }.count
                self.delegate?.showSuccess(L.t(
                    "Colima démarré en \(duration)s — \(running) container(s) actif(s)",
                    "Colima started in \(duration)s — \(running) container(s) running"))
            case .failure(let error):
                self.fail(error)
                self.apply(.unknown)
            }
        })
    }

    func stopColima() {
        delegate?.showSuccess(L.t("Arrêt de Colima…", "Stopping Colima…"))
        manager.stopColima(onTransition: { [weak self] state in
            self?.apply(state)
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let state):
                self.apply(state)
                self.lastError = nil
                self.delegate?.showSuccess(L.t("Colima arrêté", "Colima stopped"))
            case .failure(let error):
                self.fail(error)
            }
        })
    }

    /// Stops then starts Colima to apply a new config (CPU / memory / disk).
    func restartColima() {
        if transition != nil { return }
        manager.stopColima(onTransition: { [weak self] state in
            self?.apply(state)
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.manager.startColima(onTransition: { [weak self] state in
                    self?.apply(state)
                }, completion: { [weak self] result in
                    switch result {
                    case .success(let state):
                        self?.apply(state)
                        self?.lastError = nil
                    case .failure(let error): self?.fail(error)
                    }
                })
            case .failure(let error):
                self.fail(error)
            }
        })
    }

    /// Makes `name` the active Colima instance and restarts polling on it.
    func switchInstance(to name: String) {
        guard name != ColimaConfig.activeInstanceName else { return }
        ColimaConfig.activeInstanceName = name
        manager.stopPolling()
        manager.startPolling()
    }

    // MARK: - Containers

    func start(_ name: String) { containerAction { self.manager.startContainer(name, completion: $0) } }
    func stop(_ name: String) { containerAction { self.manager.stopContainer(name, completion: $0) } }

    func restart(_ name: String) {
        manager.stopContainer(name) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.containerAction { self.manager.startContainer(name, completion: $0) }
            case .failure(let error): self.fail(error)
            }
        }
    }

    func remove(_ name: String, force: Bool) {
        // Selection is cleared by `apply` once the container is really gone.
        containerAction { self.manager.removeContainer(name, force: force, completion: $0) }
    }

    func startAll(_ names: [String]) { names.forEach(start) }
    func stopAll(_ names: [String]) { names.forEach(stop) }

    func setRestartPolicy(_ policy: String, for name: String, completion: @escaping (Bool) -> Void) {
        manager.setRestartPolicy(policy, container: name) { [weak self] result in
            switch result {
            case .success:
                self?.refresh()
                completion(true)
            case .failure(let error):
                self?.fail(error)
                completion(false)
            }
        }
    }

    func fetchEnvVars(_ name: String, completion: @escaping ([String]) -> Void) {
        manager.fetchEnvVars(container: name, completion: completion)
    }

    /// Opens the Logs section streaming this container.
    func showLogs(for name: String) {
        modules.logs.showLogs(for: name)
        route = .section
        section = .logs
    }

    func openShell(_ name: String) { TerminalLauncher.promptShell(container: name) }

    func pruneDocker(completion: (() -> Void)? = nil) {
        manager.pruneDocker { [weak self] result in
            switch result {
            case .success:
                self?.delegate?.showSuccess(L.t("Docker purgé avec succès", "Docker pruned successfully"))
                self?.refresh()
            case .failure(let error):
                self?.fail(error)
            }
            completion?()
        }
    }

    // MARK: - Images / volumes / networks

    /// A reload requested while a fetch is in flight is replayed once it ends (never dropped).
    private func load<T>(_ section: DashboardSection, _ fetch: @escaping (@escaping ([T]) -> Void) -> Void,
                         assign: @escaping (AppStore, [T]) -> Void) {
        if loadingLists.contains(section) { reloadPending.insert(section); return }
        loadingLists.insert(section)
        let epoch = listEpoch
        fetch { [weak self] items in
            guard let self else { return }
            self.loadingLists.remove(section)
            // Colima stopped (or restarted) meanwhile: the answer is stale.
            if epoch == self.listEpoch, self.state.colima == .running {
                assign(self, items)
                self.loadedLists.insert(section)
            }
            if self.reloadPending.remove(section) != nil, self.state.colima == .running {
                self.load(section, fetch, assign: assign)
            }
        }
    }

    func loadImages() { load(.images, manager.fetchImages) { $0.images = $1 } }
    func loadVolumes() { load(.volumes, manager.fetchVolumes) { $0.volumes = $1 } }
    func loadNetworks() { load(.networks, manager.fetchNetworks) { $0.networks = $1 } }

    /// Loads a section's list the first time it is shown.
    func loadIfNeeded(_ section: DashboardSection) {
        guard !loadedLists.contains(section) else { return }
        switch section {
        case .images: loadImages()
        case .volumes: loadVolumes()
        case .networks: loadNetworks()
        default: break
        }
    }

    func deleteImage(_ ref: String) {
        manager.deleteImage(ref) { [weak self] result in
            switch result {
            case .success: self?.loadImages()
            case .failure(let error): self?.fail(error)
            }
        }
    }

    func pullImage(_ name: String, completion: @escaping () -> Void) {
        delegate?.showSuccess(L.t("Téléchargement de \(name)…", "Pulling \(name)…"))
        manager.pullImage(name) { [weak self] result in
            switch result {
            case .success:
                self?.delegate?.showSuccess(L.t("\(name) téléchargée", "\(name) pulled"))
                self?.loadImages()
            case .failure(let error): self?.fail(error)
            }
            completion()
        }
    }

    func pruneImages() { prune(manager.pruneImages) { $0.loadImages() } }
    func pruneVolumes() { prune(manager.pruneVolumes) { $0.loadVolumes() } }
    func pruneNetworks() { prune(manager.pruneNetworks) { $0.loadNetworks() } }

    private func prune(_ run: (@escaping (Result<String, Error>) -> Void) -> Void,
                       then reload: @escaping (AppStore) -> Void) {
        run { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: reload(self); self.refresh()
            case .failure(let error): self.fail(error)
            }
        }
    }

    /// `nil` on failure (the error is already surfaced).
    func inspect(_ name: String, completion: @escaping (String?) -> Void) {
        manager.inspectContainer(name) { [weak self] result in
            switch result {
            case .success(let json): completion(json)
            case .failure(let error):
                self?.fail(error)
                completion(nil)
            }
        }
    }

    // MARK: - Portainer / upgrade

    func installPortainer(completion: (() -> Void)? = nil) {
        manager.installPortainer { [weak self] result in
            switch result {
            case .success: self?.openPortainer()
            case .failure(let error): self?.fail(error)
            }
            completion?()
        }
    }

    func openPortainer() {
        NSWorkspace.shared.open(URL(string: "https://localhost:9443")!)
    }

    func upgradeColima() {
        TerminalLauncher.run("brew upgrade colima")
    }

    // MARK: - Navigation

    func reveal(container: String?, stack: String?) {
        route = .section
        if let container {
            section = .containers
            selectedContainer = container
        } else if let stack {
            section = .compose
            selectedStack = stack
        }
        delegate?.dashboardWindowController.showDashboard()
    }

    // MARK: - Helpers

    private var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        delegate?.showError(error.localizedDescription)
    }

    private func containerAction(_ run: (@escaping (Result<Void, Error>) -> Void) -> Void) {
        run { [weak self] result in
            switch result {
            case .success: self?.refresh()
            case .failure(let error): self?.fail(error)
            }
        }
    }
}
