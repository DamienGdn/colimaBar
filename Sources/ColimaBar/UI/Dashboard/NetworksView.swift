import SwiftUI
import ColimaBarCore

struct NetworksView: View {
    @EnvironmentObject var store: AppStore
    @State private var selection: String?
    @State private var confirmPrune = false

    private struct Row: Identifiable { let network: DockerNetwork; var id: String { network.id } }
    private var rows: [Row] { store.networks.map(Row.init) }
    private var loading: Bool { store.loadingLists.contains(.networks) && !store.loadedLists.contains(.networks) }

    var body: some View {
        ResourceSection {
            Spacer(minLength: 8)
            Button { confirmPrune = true } label: {
                Label(L.t("Purger les réseaux…", "Prune networks…"), systemImage: "sparkles")
            }
        } content: {
            if rows.isEmpty {
                ResourceEmpty(symbol: "network", title: L.t("Aucun réseau", "No networks"), hint: "", loading: loading)
            } else {
                Table(rows, selection: $selection) {
                    TableColumn(L.t("Nom", "Name")) { Text($0.network.name).foregroundColor(.tkText) }.width(min: 140, ideal: 240)
                    TableColumn(L.t("Pilote", "Driver")) { Text($0.network.driver).foregroundColor(.tkText2) }.width(min: 70, ideal: 110)
                    TableColumn(L.t("Portée", "Scope")) { Text($0.network.scope).foregroundColor(.tkText2) }.width(min: 60, ideal: 90)
                    TableColumn("ID") { Text($0.network.id).font(ResourceFont.mono).foregroundColor(.tkText2) }.width(min: 90, ideal: 130)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first {
                        Button(L.t("Copier l'ID", "Copy ID")) {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(id, forType: .string)
                        }
                    }
                }
            }
        }
        .onAppear { store.loadIfNeeded(.networks) }
        .confirmationDialog(L.t("Supprimer les réseaux inutilisés ?", "Prune networks?"), isPresented: $confirmPrune) {
            Button(L.t("Supprimer", "Prune"), role: .destructive) { store.pruneNetworks() }
        } message: {
            Text(L.t("Supprime les réseaux utilisés par aucun container. Irréversible.",
                     "Removes networks not used by any container. Irreversible."))
        }
    }
}
