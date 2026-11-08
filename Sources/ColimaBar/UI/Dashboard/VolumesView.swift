import SwiftUI
import ColimaBarCore

struct VolumesView: View {
    @EnvironmentObject var store: AppStore
    @State private var selection: String?
    @State private var confirmPrune = false

    private struct Row: Identifiable { let volume: DockerVolume; var id: String { volume.name } }
    private var rows: [Row] { store.volumes.map(Row.init) }
    private var loading: Bool { store.loadingLists.contains(.volumes) && !store.loadedLists.contains(.volumes) }

    var body: some View {
        ResourceSection {
            Spacer(minLength: 8)
            Button { if let selection { browse(selection) } } label: {
                Label(L.t("Parcourir", "Browse"), systemImage: "folder")
            }
            .disabled(selection == nil)
            Button { confirmPrune = true } label: {
                Label(L.t("Purger les volumes…", "Prune volumes…"), systemImage: "sparkles")
            }
        } content: {
            if rows.isEmpty {
                ResourceEmpty(symbol: "externaldrive", title: L.t("Aucun volume", "No volumes"), hint: "", loading: loading)
            } else {
                Table(rows, selection: $selection) {
                    TableColumn(L.t("Nom", "Name")) { Text($0.volume.name).foregroundColor(.tkText).lineLimit(1) }
                        .width(min: 160, ideal: 280)
                    TableColumn(L.t("Pilote", "Driver")) { Text($0.volume.driver).foregroundColor(.tkText2) }.width(min: 60, ideal: 90)
                    TableColumn(L.t("Taille", "Size")) { Text($0.volume.size).font(ResourceFont.mono).foregroundColor(.tkText) }
                        .width(min: 60, ideal: 90)
                    TableColumn(L.t("Utilisé par", "Used by")) {
                        Text($0.volume.containers.isEmpty ? "—" : $0.volume.containers.joined(separator: ", "))
                            .foregroundColor(.tkText2).lineLimit(1)
                    }.width(min: 120, ideal: 220)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first {
                        Button(L.t("Parcourir", "Browse")) { browse(id) }
                        Button(L.t("Copier le nom", "Copy name")) {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(id, forType: .string)
                        }
                    }
                }
            }
        }
        .onAppear { store.loadIfNeeded(.volumes) }
        .confirmationDialog(L.t("Supprimer les volumes inutilisés ?", "Prune volumes?"), isPresented: $confirmPrune) {
            Button(L.t("Supprimer", "Prune"), role: .destructive) { store.pruneVolumes() }
        } message: {
            Text(L.t("Supprime les volumes utilisés par aucun container. Les données sont perdues. Irréversible.",
                     "Removes volumes not used by any container. Their data is lost. Irreversible."))
        }
    }

    private func browse(_ name: String) { store.route = .volumeBrowser(volume: name) }
}

/// The AppKit file browser positioned on one volume, with a way back to the table.
struct VolumeBrowserRoute: View {
    @EnvironmentObject var store: AppStore
    let volume: String

    private var users: [String] { store.volumes.first { $0.name == volume }?.containers ?? [] }
    private var runningUsers: [String] {
        let running = Set(store.state.containers.filter(\.isRunning).map(\.name))
        return users.filter(running.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(L.t("← Retour", "← Back")) { store.route = .section }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("[", modifiers: .command)
                    .help(L.t("Retour au tableau (⌘[)", "Back to the table (⌘[)"))
                Text(volume).font(.system(size: 14, weight: .semibold)).foregroundColor(.tkText).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            if runningUsers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 30)).foregroundColor(.tkText3)
                    Text(L.t("Aucun container en cours d'exécution n'utilise ce volume",
                             "No running container uses this volume"))
                        .font(.headline).foregroundColor(.tkText)
                    Text(L.t("Le contenu d'un volume se parcourt via un container qui le monte. Démarrez-en un.",
                             "A volume is browsed through a container that mounts it. Start one."))
                        .foregroundColor(.tkText2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HostedVC(make: { store.modules.volumeBrowser })
                    .onAppear { position() }
                    .onChange(of: volume) { _ in position() }
            }
        }
    }

    /// Deferred out of the view update (the browser reloads and runs docker commands).
    private func position() {
        let volume = volume, users = runningUsers, docker = store.manager.dockerPath
        DispatchQueue.main.async { [weak store] in
            store?.modules.volumeBrowser.showVolume(volume, usedBy: users, dockerPath: docker)
        }
    }
}
