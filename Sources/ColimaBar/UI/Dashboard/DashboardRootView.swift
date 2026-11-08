import SwiftUI
import ColimaBarCore

struct DashboardRootView: View {
    @EnvironmentObject var store: AppStore

    private var colimaUp: Bool {
        switch store.state.colima {
        case .running, .transitioning: return true
        default: return false
        }
    }

    private var isDockerSection: Bool {
        switch store.section {
        case .logs, .snapshots: return false
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            NavigationSplitView {
                SidebarView()
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.tkBg)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.tkBg)
    }

    @ViewBuilder private var detail: some View {
        if isDockerSection && !colimaUp {
            stoppedView
        } else {
            switch store.section {
            case .logs:
                HostedVC(make: { store.modules.logs })
            case .snapshots:
                HostedVC(make: { store.modules.snapshots })
            default:
                placeholder(store.section.rawValue.capitalized)
            }
        }
    }

    private var stoppedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 36)).foregroundColor(.tkText3)
            Text(L.t("Colima est arrêté", "Colima is stopped"))
                .font(.system(size: 17, weight: .semibold)).foregroundColor(.tkText)
            Text(L.t("Démarrez Colima pour gérer vos conteneurs Docker.",
                     "Start Colima to manage your Docker containers."))
                .foregroundColor(.tkText2)
            Button(L.t("Démarrer", "Start")) { store.startColima() }
                .buttonStyle(.borderedProminent).tint(.tkAccent)
        }
    }

    private func placeholder(_ name: String) -> some View {
        Text(name).font(.title2).foregroundColor(.tkText3)
    }
}
