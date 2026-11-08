import SwiftUI
import ColimaBarCore

struct ContainerDetailView: View {
    @EnvironmentObject var store: AppStore
    let container: DockerContainer

    private static let policies = ["no", "always", "unless-stopped", "on-failure"]

    @State private var pendingPolicy: String?
    @State private var showEnv = false
    @State private var showInspect = false
    @State private var confirmRemove = false

    private var c: DockerContainer { container }
    private var stats: ResourceUsage? { store.state.containerStats[c.name] }
    private var currentPolicy: String { store.state.restartPolicies[c.name].flatMap { $0.isEmpty ? nil : $0 } ?? "no" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                DetailUI.section { DetailUI.title(c.name, running: c.isRunning, subtitle: c.image) }
                Divider()
                DetailUI.section { actions }
                if c.isRunning {
                    Divider()
                    DetailUI.section { sparklines }
                }
                Divider()
                DetailUI.section { info }
                Divider()
                DetailUI.section { restartPolicy }
                Divider()
                DetailUI.section { footer }
            }
        }
        .sheet(isPresented: $showEnv) { EnvSheet(name: c.name).environmentObject(store) }
        .sheet(isPresented: $showInspect) { InspectSheet(name: c.name).environmentObject(store) }
        .confirmationDialog(L.t("Supprimer « \(c.name) » ?", "Remove “\(c.name)”?"),
                            isPresented: $confirmRemove) {
            Button(c.isRunning ? L.t("Arrêter et supprimer", "Stop and remove") : L.t("Supprimer", "Remove"),
                   role: .destructive) {
                store.remove(c.name, force: c.isRunning)
            }
        } message: {
            Text(c.isRunning
                 ? L.t("Ce container est en cours d'exécution : il sera arrêté et supprimé de force (docker rm -f). Ses données hors volumes seront perdues.",
                       "This container is running: it will be stopped and force-removed (docker rm -f). Its data outside volumes will be lost.")
                 : L.t("Ses données hors volumes seront perdues.", "Its data outside volumes will be lost."))
        }
        .onChange(of: currentPolicy) { value in
            if value == pendingPolicy { pendingPolicy = nil }
        }
    }

    private var actions: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                DetailUI.action(L.t("Démarrer", "Start"), "play.fill", disabled: c.isRunning) { store.start(c.name) }
                DetailUI.action(L.t("Arrêter", "Stop"), "stop.fill", disabled: !c.isRunning) { store.stop(c.name) }
                DetailUI.action(L.t("Redémarrer", "Restart"), "arrow.clockwise", disabled: !c.isRunning) { store.restart(c.name) }
            }
            GridRow {
                DetailUI.action("Logs", "text.alignleft") { store.showLogs(for: c.name) }
                DetailUI.action("Shell", "terminal", disabled: !c.isRunning) { store.openShell(c.name) }
                DetailUI.action("Env", "list.bullet.rectangle") { showEnv = true }
            }
        }
        .controlSize(.small)
    }

    private var sparklines: some View {
        VStack(spacing: 14) {
            DetailUI.spark("CPU", value: stats.map { ContainersTableView.percent($0.cpuPercent) } ?? "—",
                           values: store.history.cpu[c.name]?.values ?? [],
                           color: Color(nsColor: Theme.Brand.teal))
            DetailUI.spark(L.t("Mémoire", "Memory"), value: memoryLabel,
                           values: store.history.mem[c.name]?.values ?? [],
                           color: .tkAccent)
        }
    }

    private var memoryLabel: String {
        guard let s = stats else { return "—" }
        let used = ContainersTableView.mebibytes(s.memUsedMiB)
        return s.memTotalGiB > 0 ? "\(used) / \(String(format: "%.1f GB", s.memTotalGiB))" : used
    }

    private var info: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
            DetailUI.kv(L.t("Statut", "Status")) { Text(c.status).textSelection(.enabled) }
            if let health = c.health {
                DetailUI.kv(L.t("Santé", "Health")) { Text(health.rawValue) }
            }
            DetailUI.kv("Ports") {
                if c.hostPortNumbers.isEmpty {
                    Text("—").foregroundColor(.tkText3)
                } else {
                    FlowPorts(ports: c.hostPortNumbers)
                }
            }
            if let project = c.composeProject {
                DetailUI.kv("Compose") {
                    Text("\(project) / \(c.labelValue(forKey: "com.docker.compose.service") ?? "—")")
                }
            }
            DetailUI.kv("ID") {
                Text(String(c.id.prefix(12)))
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }
        }
    }

    private var restartPolicy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("Politique de redémarrage", "Restart policy"))
                .font(.system(size: 12)).foregroundColor(.tkText2)
            Picker(L.t("Politique de redémarrage", "Restart policy"), selection: Binding(
                get: { pendingPolicy ?? currentPolicy },
                set: { policy in
                    guard policy != (pendingPolicy ?? currentPolicy) else { return }
                    pendingPolicy = policy
                    store.setRestartPolicy(policy, for: c.name) { ok in
                        if !ok { pendingPolicy = nil }
                    }
                })) {
                ForEach(Self.policies, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            DetailUI.action("Inspect", "magnifyingglass") { showInspect = true }
            Button(role: .destructive) { confirmRemove = true } label: {
                Label(L.t("Supprimer", "Remove"), systemImage: "trash")
                    .foregroundColor(.tkRed)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.small)
    }
}

/// Port chips that wrap onto a second line when needed.
private struct FlowPorts: View {
    let ports: [Int]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(stride(from: 0, to: ports.count, by: 3)), id: \.self) { start in
                HStack(spacing: 4) {
                    ForEach(ports[start..<min(start + 3, ports.count)], id: \.self) { PortChip(port: $0) }
                }
            }
        }
    }
}

/// Sheet hosting the AppKit env-vars table.
private struct EnvSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let name: String

    var body: some View {
        VStack(spacing: 0) {
            HostedVC(make: {
                let vc = EnvVarsViewController()
                vc.containerName = name
                store.fetchEnvVars(name) { [weak vc] vars in vc?.loadEnvVars(vars) }
                return vc
            })
            Divider()
            HStack {
                Spacer()
                Button(L.t("Fermer", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 400)
        .background(Color.tkBg)
    }
}
