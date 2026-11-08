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
            if case .unknown = store.state.colima {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L.t("Chargement…", "Loading…")).foregroundColor(.tkText2)
                }
            } else {
                stoppedView
            }
        } else {
            switch store.section {
            case .compose:
                if case .composeEditor(let stack) = store.route {
                    composeEditor(stack: stack)
                } else {
                    ContainersSectionView(mode: .grouped)
                }
            case .containers:
                ContainersSectionView(mode: .flat)
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

    private func composeEditor(stack: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(L.t("← Retour", "← Back")) { store.route = .section }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("[", modifiers: .command)
                    .help(L.t("Retour au tableau (⌘[)", "Back to the table (⌘[)"))
                Text(stack).font(.system(size: 14, weight: .semibold)).foregroundColor(.tkText)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            HostedVC(make: {
                let vc = store.modules.composeEditor
                vc.showProject(named: stack)
                return vc
            })
            .id(stack)
        }
    }

    private func placeholder(_ name: String) -> some View {
        Text(name).font(.title2).foregroundColor(.tkText3)
    }
}
