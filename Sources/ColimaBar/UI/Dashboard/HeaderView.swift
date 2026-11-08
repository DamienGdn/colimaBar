import SwiftUI
import AppKit
import ColimaBarCore

struct HeaderView: View {
    @EnvironmentObject var store: AppStore

    private var state: ColimaAppState { store.state }

    private var isRunning: Bool { if case .running = state.colima { return true } else { return false } }
    private var isTransitioning: Bool { if case .transitioning = state.colima { return true } else { return false } }

    var body: some View {
        HStack(spacing: 14) {
            BrandLogo(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                BrandWordmark(size: 20)
                Text(state.profileSummary)
                    .font(.system(size: 11.5)).foregroundColor(.tkOnBrand.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 12)
            StatePill(state: state.colima)
            if let usage = state.usage {
                HeaderGauge(label: "CPU", value: String(format: "%.0f%%", usage.cpuPercent),
                            fraction: usage.cpuPercent / Double(max(state.cpus ?? 1, 1)) / 100)
                    .frame(width: 110)
                HeaderGauge(label: "RAM", value: "\(usage.memUsedFormatted) / \(String(format: "%.0f", usage.memTotalGiB)) GB",
                            fraction: usage.memUsedPercent / 100)
                    .frame(width: 150)
            }
            Button {
                isRunning ? store.stopColima() : store.startColima()
            } label: {
                Label(isRunning ? L.t("Arrêter", "Stop") : L.t("Démarrer", "Start"),
                      systemImage: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.tkOnBrand.opacity(0.14)))
                    .overlay(Capsule().stroke(Color.tkOnBrand.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain).foregroundColor(.tkOnBrand)
            .disabled(isTransitioning)
            .opacity(isTransitioning ? 0.5 : 1)

            iconButton("arrow.clockwise", L.t("Rafraîchir", "Refresh")) { store.refreshVisible() }

            Menu {
                Button(L.t("Réglages…", "Settings…")) { SettingsWindowController.shared.show(store: store) }
                Button(L.t("À propos", "About")) { (NSApp.delegate as? AppDelegate)?.showAbout() }
                Divider()
                Button(L.t("Quitter", "Quit")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.tkOnBrand)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.tkOnBrand.opacity(0.12)))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(L.t("Menu", "Menu"))
        }
        // Left inset clears the traffic lights (header runs under the transparent title bar).
        .padding(.leading, 86).padding(.trailing, 18)
        .frame(height: 64)
        .background(Theme.headerGradient)
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundColor(.tkOnBrand)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.tkOnBrand.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).help(label)
    }
}
