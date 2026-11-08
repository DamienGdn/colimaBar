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

    init(manager: ColimaManager) {
        self.manager = manager
        manager.onStateChange = { [weak self] state in
            self?.apply(state)
        }
    }

    var groups: (stacks: [StackGroup], standalone: [DockerContainer]) {
        let grouped = ContainerGrouping.group(state.containers, stats: state.containerStats)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return grouped }
        func matches(_ c: DockerContainer) -> Bool {
            c.name.lowercased().contains(q) || c.image.lowercased().contains(q)
        }
        let stacks = grouped.stacks.filter { $0.name.lowercased().contains(q) || $0.containers.contains(where: matches) }
        return (stacks, grouped.standalone.filter(matches))
    }

    // MARK: - State

    func apply(_ state: ColimaAppState) {
        // A transient stats failure must not wipe the graphs while containers are running.
        let statsMissing = state.containerStats.isEmpty && state.containers.contains { $0.isRunning }
        if !statsMissing { history.record(state.containerStats) }
        if case .transitioning(let label) = state.colima { transition = label } else { transition = nil }
        self.state = state
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
        containerAction { self.manager.removeContainer(name, force: force, completion: $0) }
        if selectedContainer == name { selectedContainer = nil }
    }

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

    func pruneImages() {
        manager.pruneImages { [weak self] result in
            switch result {
            case .success: self?.refresh()
            case .failure(let error): self?.fail(error)
            }
        }
    }

    func inspect(_ name: String, completion: @escaping (String) -> Void) {
        manager.inspectContainer(name) { [weak self] result in
            switch result {
            case .success(let json): completion(json)
            case .failure(let error): self?.fail(error)
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Terminal\" to do script \"brew upgrade colima\""]
        try? process.run()
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
