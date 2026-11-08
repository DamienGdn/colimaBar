import SwiftUI
import ColimaBarCore

/// Compose / Containers section: toolbar, table and detail panel.
struct ContainersSectionView: View {
    @EnvironmentObject var store: AppStore
    let mode: ContainersTableView.Mode

    @FocusState private var searchFocused: Bool
    @State private var confirmPrune = false
    @State private var busy = false

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            HStack(alignment: .top, spacing: 12) {
                ContainersTableView(mode: mode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.tkSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.tkBorder))
                DetailPanel(mode: mode)
                    .frame(width: 300)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(16)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.tkText3)
                TextField(L.t("Rechercher…", "Search…"), text: $store.search)
                    .textFieldStyle(.plain)
                    .foregroundColor(.tkText)
                    .focused($searchFocused)
                    .onExitCommand { store.search = "" }
                if !store.search.isEmpty {
                    Button { store.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.tkText3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("Effacer la recherche", "Clear search"))
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 300, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.tkSurface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(searchFocused ? Color.tkAccent : Color.tkBorder))
            .background(
                // ⌘F focuses the search field.
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0).accessibilityHidden(true)
            )

            Spacer(minLength: 8)

            if store.state.portainerExists {
                Button { store.openPortainer() } label: {
                    Label(L.t("Ouvrir Portainer", "Open Portainer"), systemImage: "arrow.up.right.square")
                }
            } else {
                Button {
                    busy = true
                    store.installPortainer { busy = false }
                } label: {
                    Label(L.t("Installer Portainer", "Install Portainer"), systemImage: "arrow.down.circle")
                }
                .disabled(busy)
            }
            Button { confirmPrune = true } label: {
                Label(L.t("Vider Docker…", "Prune Docker…"), systemImage: "trash")
            }
            .disabled(busy)
        }
        .buttonStyle(.bordered)
        .confirmationDialog(L.t("Vider Docker ?", "Prune Docker?"), isPresented: $confirmPrune) {
            Button(L.t("Vider", "Prune"), role: .destructive) {
                busy = true
                store.pruneDocker { busy = false }
            }
        } message: {
            Text(L.t("Supprime les containers arrêtés, réseaux inutilisés, images orphelines et le cache de build. Irréversible.",
                     "Removes stopped containers, unused networks, dangling images and build cache. Irreversible."))
        }
    }
}

/// Stack-wide actions shared by the table context menu and the stack detail.
enum StackActions {
    static func hasComposeFile(_ stack: StackGroup) -> Bool {
        stack.containers.contains { DockerComposeService.findComposeFile(for: $0) != nil }
    }
    static func startAll(_ stack: StackGroup, _ store: AppStore) {
        store.startAll(stack.containers.filter { !$0.isRunning }.map(\.name))
    }
    static func stopAll(_ stack: StackGroup, _ store: AppStore) {
        store.stopAll(stack.containers.filter(\.isRunning).map(\.name))
    }
}
