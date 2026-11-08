import SwiftUI
import ColimaBarCore

/// Right-hand panel: selected container, selected stack (grouped mode) or a hint.
struct DetailPanel: View {
    @EnvironmentObject var store: AppStore
    let mode: ContainersTableView.Mode

    var body: some View {
        Group {
            if let name = store.selectedContainer,
               let c = store.state.containers.first(where: { $0.name == name }) {
                ContainerDetailView(container: c).id(c.name)
            } else if mode == .grouped, let name = store.selectedStack,
                      let stack = store.stack(named: name) {
                StackDetailView(stack: stack)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox").font(.system(size: 28)).foregroundColor(.tkText3)
                    Text(L.t("Sélectionnez un container pour voir le détail",
                             "Select a container to see details"))
                        .multilineTextAlignment(.center).foregroundColor(.tkText2)
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .background(Color.tkSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.tkBorder))
    }
}

/// Shared building blocks of the detail panels.
enum DetailUI {
    static func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func title(_ name: String, running: Bool, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                StatusDot(color: running ? .tkGreen : .tkText3)
                Text(name).font(.system(size: 15, weight: .bold)).foregroundColor(.tkText)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Text(subtitle).font(.system(size: 12)).foregroundColor(.tkText2)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }

    static func action(_ title: String, _ symbol: String, disabled: Bool = false,
                       run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
    }

    static func spark(_ label: String, value: String, values: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).foregroundColor(.tkText2)
                Spacer()
                Text(value).fontWeight(.semibold).foregroundColor(.tkText).monospacedDigit()
            }
            .font(.system(size: 12))
            Sparkline(values: values, color: color)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.tkSurface2))
        }
    }

    static func kv<Value: View>(_ key: String, @ViewBuilder _ value: () -> Value) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(key).foregroundColor(.tkText3).gridColumnAlignment(.leading)
            value().foregroundColor(.tkText).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5))
    }
}

struct StackDetailView: View {
    @EnvironmentObject var store: AppStore
    let stack: StackGroup

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                DetailUI.section {
                    DetailUI.title(stack.name, running: stack.status != .stopped,
                                   subtitle: stack.containers.count == 1 ? "1 container" : "\(stack.containers.count) containers")
                    StatusBadge.forStack(stack.status)
                }
                Divider()
                DetailUI.section {
                    DetailUI.action(L.t("Éditer le compose", "Edit compose file"), "doc.text",
                                    disabled: !StackActions.hasComposeFile(stack)) {
                        store.route = .composeEditor(stack: stack.name)
                    }
                    HStack(spacing: 8) {
                        DetailUI.action(L.t("Tout démarrer", "Start all"), "play.fill",
                                        disabled: stack.status == .allRunning) { StackActions.startAll(stack.name, store) }
                        DetailUI.action(L.t("Tout arrêter", "Stop all"), "stop.fill",
                                        disabled: stack.status == .stopped) { StackActions.stopAll(stack.name, store) }
                    }
                }
                .controlSize(.small)
                Divider()
                DetailUI.section {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                        DetailUI.kv("CPU") {
                            MetricText(stack.status == .stopped ? nil : stack.cpuPercent, format: ContainersTableView.percent)
                        }
                        DetailUI.kv(L.t("Mémoire", "Memory")) {
                            MetricText(stack.status == .stopped ? nil : stack.memUsedMiB, format: ContainersTableView.mebibytes)
                        }
                    }
                }
                Divider()
                DetailUI.section {
                    ForEach(stack.containers, id: \.name) { c in
                        Button { store.selectedContainer = c.name; store.selectedStack = nil } label: {
                            HStack(spacing: 7) {
                                StatusDot(color: c.isRunning ? .tkGreen : .tkText3)
                                Text(c.name).foregroundColor(.tkText).lineLimit(1)
                                Spacer(minLength: 4)
                                StatusBadge.forContainer(c)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
