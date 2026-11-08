import SwiftUI
import ColimaBarCore

/// Container table: stacks as collapsible rows (`.grouped`) or every container (`.flat`).
struct ContainersTableView: View {
    enum Mode { case grouped, flat }

    @EnvironmentObject var store: AppStore
    let mode: Mode
    @State private var collapsed: Set<String> = []

    private static let standaloneID = "standalone"

    private enum Kind {
        case stack(StackGroup)
        case standalone(StackGroup)
        case container(DockerContainer, child: Bool)
    }

    private struct Row: Identifiable {
        let id: String
        let kind: Kind
    }

    // MARK: Rows

    private var rows: [Row] {
        let groups = store.groups
        let searching = !store.search.trimmingCharacters(in: .whitespaces).isEmpty
        func isOpen(_ id: String) -> Bool { searching || !collapsed.contains(id) }
        func child(_ c: DockerContainer) -> Row { Row(id: "c:" + c.name, kind: .container(c, child: true)) }

        switch mode {
        case .flat:
            let all = (groups.stacks.flatMap(\.containers) + groups.standalone).sorted { $0.name < $1.name }
            return all.map { Row(id: "c:" + $0.name, kind: .container($0, child: false)) }
        case .grouped:
            var out: [Row] = []
            for stack in groups.stacks {
                let id = "s:" + stack.name
                out.append(Row(id: id, kind: .stack(stack)))
                if isOpen(id) { out += stack.containers.map(child) }
            }
            if !groups.standalone.isEmpty {
                out.append(Row(id: Self.standaloneID, kind: .standalone(summary(groups.standalone))))
                if isOpen(Self.standaloneID) { out += groups.standalone.map(child) }
            }
            return out
        }
    }

    private func summary(_ containers: [DockerContainer]) -> StackGroup {
        let running = containers.filter(\.isRunning).count
        let status: StackStatus = running == 0 ? .stopped
            : running == containers.count ? .allRunning
            : .partial(running: running, total: containers.count)
        let stats = containers.compactMap { store.state.containerStats[$0.name] }
        return StackGroup(name: "", containers: containers, status: status,
                          cpuPercent: stats.reduce(0) { $0 + $1.cpuPercent },
                          memUsedMiB: stats.reduce(0) { $0 + $1.memUsedMiB })
    }

    // MARK: Selection

    private var selection: Binding<String?> {
        Binding(
            get: {
                if let c = store.selectedContainer { return "c:" + c }
                if mode == .grouped, let s = store.selectedStack { return "s:" + s }
                return nil
            },
            set: { id in
                guard let id else { store.selectedContainer = nil; store.selectedStack = nil; return }
                if id.hasPrefix("c:") {
                    store.selectedContainer = String(id.dropFirst(2)); store.selectedStack = nil
                } else if id.hasPrefix("s:") {
                    store.selectedStack = String(id.dropFirst(2)); store.selectedContainer = nil
                } else {
                    store.selectedContainer = nil; store.selectedStack = nil
                }
            })
    }

    // MARK: Body

    var body: some View {
        let rows = self.rows
        if rows.isEmpty {
            emptyState
        } else {
            Table(rows, selection: selection) {
                TableColumn(L.t("Nom", "Name")) { nameCell($0) }.width(min: 160, ideal: 250)
                TableColumn("Image") { imageCell($0) }.width(min: 90, ideal: 170)
                TableColumn(L.t("Statut", "Status")) { statusCell($0) }.width(min: 90, ideal: 110)
                TableColumn("Ports") { portsCell($0) }.width(min: 70, ideal: 120)
                TableColumn("CPU") { cpuCell($0) }.width(min: 50, ideal: 64)
                TableColumn("RAM") { ramCell($0) }.width(min: 60, ideal: 80)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first { menu(for: id) }
            } primaryAction: { ids in
                if let id = ids.first, !id.hasPrefix("c:") { toggle(id) }
            }
        }
    }

    private var emptyState: some View {
        let q = store.search.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 8) {
            Image(systemName: mode == .grouped ? "square.stack.3d.up" : "shippingbox")
                .font(.system(size: 30)).foregroundColor(.tkText3)
            if !q.isEmpty {
                Text(L.t("Aucun résultat pour « \(q) »", "Nothing matches “\(q)”"))
                    .font(.headline).foregroundColor(.tkText)
            } else {
                Text(L.t("Aucun container", "No containers")).font(.headline).foregroundColor(.tkText)
                Text(L.t("Lancez docker run ou docker compose up, ils apparaîtront ici.",
                         "Run docker run or docker compose up, they will show up here."))
                    .foregroundColor(.tkText2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    // MARK: Cells

    @ViewBuilder private func nameCell(_ row: Row) -> some View {
        switch row.kind {
        case .stack(let s): groupName(row.id, s.name)
        case .standalone: groupName(row.id, L.t("Containers indépendants", "Standalone containers"))
        case let .container(c, child):
            HStack(spacing: 7) {
                StatusDot(color: c.isRunning ? .tkGreen : .tkText3)
                Text(c.name).foregroundColor(.tkText).lineLimit(1).truncationMode(.middle)
                if child, let svc = c.labelValue(forKey: "com.docker.compose.service") {
                    Text(svc).font(.system(size: 11.5)).foregroundColor(.tkText3).lineLimit(1)
                }
            }
            .padding(.leading, child ? 22 : 0)
            .help(c.name)
        }
    }

    private func groupName(_ id: String, _ title: String) -> some View {
        let open = !store.search.trimmingCharacters(in: .whitespaces).isEmpty || !collapsed.contains(id)
        return HStack(spacing: 6) {
            Button { toggle(id) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .foregroundColor(.tkText2)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? L.t("Replier", "Collapse") : L.t("Déplier", "Expand"))
            Text(title).fontWeight(.semibold).foregroundColor(.tkText).lineLimit(1)
        }
    }

    @ViewBuilder private func imageCell(_ row: Row) -> some View {
        switch row.kind {
        case .stack(let s), .standalone(let s):
            Text(s.containers.count == 1 ? "1 container" : "\(s.containers.count) containers")
                .fontWeight(.semibold).foregroundColor(.tkText2)
        case .container(let c, _):
            Text(c.image).foregroundColor(.tkText2).lineLimit(1).truncationMode(.middle).help(c.image)
        }
    }

    @ViewBuilder private func statusCell(_ row: Row) -> some View {
        switch row.kind {
        case .stack(let s), .standalone(let s): StatusBadge.forStack(s.status)
        case .container(let c, _): StatusBadge.forContainer(c).help(c.status)
        }
    }

    @ViewBuilder private func portsCell(_ row: Row) -> some View {
        if case .container(let c, _) = row.kind {
            let ports = c.hostPortNumbers
            if ports.isEmpty {
                Text("—").foregroundColor(.tkText3)
            } else {
                HStack(spacing: 4) {
                    ForEach(ports.prefix(2), id: \.self) { PortChip(port: $0) }
                    if ports.count > 2 {
                        Text("…").foregroundColor(.tkText3).help(ports.map(String.init).joined(separator: ", "))
                    }
                }
            }
        }
    }

    @ViewBuilder private func cpuCell(_ row: Row) -> some View {
        Group {
            switch row.kind {
            case .stack(let s), .standalone(let s):
                MetricText(s.status == .stopped ? nil : s.cpuPercent, format: Self.percent).fontWeight(.semibold)
            case .container(let c, _):
                MetricText(store.state.containerStats[c.name]?.cpuPercent, format: Self.percent)
            }
        }
        .foregroundColor(.tkText)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder private func ramCell(_ row: Row) -> some View {
        Group {
            switch row.kind {
            case .stack(let s), .standalone(let s):
                MetricText(s.status == .stopped ? nil : s.memUsedMiB, format: Self.mebibytes).fontWeight(.semibold)
            case .container(let c, _):
                MetricText(store.state.containerStats[c.name]?.memUsedMiB, format: Self.mebibytes)
            }
        }
        .foregroundColor(.tkText)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    static func percent(_ v: Double) -> String { String(format: "%.1f%%", v) }
    static func mebibytes(_ v: Double) -> String {
        v >= 1024 ? String(format: "%.1f GB", v / 1024) : String(format: "%.0f MB", v)
    }

    // MARK: Context menu

    @ViewBuilder private func menu(for id: String) -> some View {
        if id.hasPrefix("s:"), let stack = store.groups.stacks.first(where: { "s:" + $0.name == id }) {
            Button(L.t("Éditer le compose", "Edit compose file")) {
                store.route = .composeEditor(stack: stack.name)
            }
            .disabled(!StackActions.hasComposeFile(stack))
            Divider()
            Button(L.t("Tout démarrer", "Start all")) { StackActions.startAll(stack, store) }
                .disabled(stack.status == .allRunning)
            Button(L.t("Tout arrêter", "Stop all")) { StackActions.stopAll(stack, store) }
                .disabled(stack.status == .stopped)
        } else if id.hasPrefix("c:"),
                  let c = store.state.containers.first(where: { "c:" + $0.name == id }) {
            Button(L.t("Démarrer", "Start")) { store.start(c.name) }.disabled(c.isRunning)
            Button(L.t("Arrêter", "Stop")) { store.stop(c.name) }.disabled(!c.isRunning)
            Button(L.t("Redémarrer", "Restart")) { store.restart(c.name) }.disabled(!c.isRunning)
            Divider()
            Button("Logs") { store.showLogs(for: c.name) }.disabled(!c.isRunning)
            Button("Shell") { store.openShell(c.name) }.disabled(!c.isRunning)
        }
    }
}
