import SwiftUI
import AppKit
import ColimaBarCore

/// Status-bar mini panel: brand band, warnings, stacks & containers, quick actions.
/// Every string is computed in `body`, so a language switch shows on the next render.
struct StatusPopoverView: View {
    @EnvironmentObject var store: AppStore
    /// Closes the hosting popover.
    let close: () -> Void

    @State private var installingPortainer = false

    static let width: CGFloat = 340
    private static let rowHeight: CGFloat = 28
    private static let listMaxHeight: CGFloat = 260

    private var state: ColimaAppState { store.state }
    private var isRunning: Bool { state.colima == .running }
    private var busy: Bool {
        if store.transition != nil { return true }
        if case .transitioning = state.colima { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            banners
            list
            footer
        }
        .frame(width: Self.width)
        .background(Color.tkSurface)
    }

    // MARK: - Header band

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BrandLogo(size: 24)
                BrandWordmark(size: 15)
                Spacer(minLength: 6)
                StatePill(state: state.colima)
            }
            Text(state.profileSummary)
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
                .lineLimit(1).truncationMode(.tail)
            gauges
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.headerGradient)
    }

    private var gauges: some View {
        let usage = isRunning && !busy ? state.usage : nil
        let cpuFraction = usage.map { $0.cpuPercent / Double(max(state.cpus ?? 1, 1)) / 100 } ?? 0
        return HStack(spacing: 12) {
            HeaderGauge(label: "CPU", value: usage.map { String(format: "%.0f%%", $0.cpuPercent) } ?? "—",
                        fraction: cpuFraction)
            HeaderGauge(label: "RAM",
                        value: usage.map { "\($0.memUsedFormatted) / \(String(format: "%.0f", $0.memTotalGiB)) GB" } ?? "—",
                        fraction: (usage?.memUsedPercent ?? 0) / 100)
        }
        .opacity(usage == nil ? 0.4 : 1)
    }

    // MARK: - Warnings

    @ViewBuilder private var banners: some View {
        let showPortainer = isRunning && !state.portainerExists
        if showPortainer || store.updateVersion != nil || store.lastError != nil {
            VStack(spacing: 6) {
                if showPortainer {
                    PopoverBanner(icon: "exclamationmark.triangle.fill", tint: .tkAmber, fill: .tkAmberSoft,
                                  text: L.t("Portainer n'est pas installé", "Portainer is not installed"),
                                  action: L.t("Installer Portainer", "Install Portainer"),
                                  busy: installingPortainer) {
                        installingPortainer = true
                        // On success stay busy until the refreshed state hides the banner.
                        store.installPortainer { ok in if !ok { installingPortainer = false } }
                    }
                }
                if let version = store.updateVersion {
                    PopoverBanner(icon: "arrow.triangle.2.circlepath", tint: .tkAccent, fill: .tkAccentSoft,
                                  text: L.t("Nouvelle version disponible", "New version available"),
                                  action: L.t("Mettre à jour Colima \(version)", "Update Colima \(version)")) {
                        store.upgradeColima()
                        close()
                    }
                }
                if let error = store.lastError {
                    ErrorBanner(message: error) { store.lastError = nil }
                }
            }
            .padding(.horizontal, 10).padding(.top, 10)
        }
    }

    // MARK: - Stacks & containers

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("Stacks & containers", "Stacks & containers").uppercased())
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.tkText3)
                .padding(.horizontal, 6)
            if isRunning {
                rows
            } else if busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.transition ?? L.t("Patientez…", "Please wait…"))
                        .font(.system(size: 12)).foregroundColor(.tkText2)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            } else {
                placeholder(L.t("Colima est arrêté", "Colima is stopped"))
            }
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)
    }

    @ViewBuilder private var rows: some View {
        let groups = ContainerGrouping.group(state.containers, stats: state.containerStats)
        let count = groups.stacks.count + groups.standalone.count
        if count == 0 {
            placeholder(L.t("Aucun container", "No containers"))
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(groups.stacks, id: \.name) { stack in
                        PopoverRow(icon: "square.stack.3d.up", title: stack.name,
                                   badge: .forStack(stack.status), height: Self.rowHeight) {
                            reveal(container: nil, stack: stack.name)
                        }
                    }
                    ForEach(groups.standalone, id: \.id) { container in
                        PopoverRow(icon: "shippingbox", title: container.name,
                                   badge: .forContainer(container), height: Self.rowHeight) {
                            reveal(container: container.name, stack: nil)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(count) * Self.rowHeight, Self.listMaxHeight))
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12)).foregroundColor(.tkText3)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                isRunning ? store.stopColima() : store.startColima()
            } label: {
                HStack(spacing: 5) {
                    if busy {
                        ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: isRunning ? "stop.fill" : "play.fill").font(.system(size: 10))
                    }
                    Text(busy ? (store.transition ?? "…") : isRunning ? L.t("Arrêter", "Stop") : L.t("Démarrer", "Start"))
                        .lineLimit(1)
                }
            }
            .buttonStyle(PopoverButtonStyle(primary: false))
            .disabled(busy)

            Button { store.refreshVisible() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(PopoverButtonStyle(primary: false))
            .accessibilityLabel(L.t("Rafraîchir", "Refresh")).help(L.t("Rafraîchir", "Refresh"))

            Button { openDashboard() } label: {
                Text(L.t("Ouvrir le Dashboard", "Open Dashboard")).lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PopoverButtonStyle(primary: true))
            .keyboardShortcut("d")
            .help("⌘D")

            Menu {
                Button(L.t("Réglages…", "Settings…")) {
                    close()
                    SettingsWindowController.shared.show(store: store)
                }
                Button(L.t("À propos", "About")) {
                    close()
                    (NSApp.delegate as? AppDelegate)?.showAbout()
                }
                Divider()
                Button(L.t("Quitter", "Quit")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape.fill").foregroundColor(.tkText2)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 26, height: 26)
            .accessibilityLabel(L.t("Menu", "Menu"))
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(10)
        .overlay(alignment: .top) { Rectangle().fill(Color.tkBorder).frame(height: 1) }
    }

    // MARK: - Navigation

    private func openDashboard() {
        close()
        (NSApp.delegate as? AppDelegate)?.dashboardWindowController.showDashboard()
    }

    private func reveal(container: String?, stack: String?) {
        close()
        store.reveal(container: container, stack: stack)   // also brings the dashboard up
    }
}
