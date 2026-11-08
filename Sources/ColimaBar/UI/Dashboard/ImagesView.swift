import SwiftUI
import ColimaBarCore

struct ImagesView: View {
    @EnvironmentObject var store: AppStore
    @State private var selection: String?
    @State private var pullName = ""
    @State private var pulling = false
    @State private var pendingDelete: DockerImage?
    @State private var confirmPrune = false

    private static func rowID(_ i: DockerImage) -> String { "\(i.repository):\(i.tag):\(i.id)" }
    private struct Row: Identifiable { let image: DockerImage; var id: String { ImagesView.rowID(image) } }

    private var rows: [Row] { store.images.map(Row.init) }
    private var selected: DockerImage? { store.images.first { Self.rowID($0) == selection } }
    private var loading: Bool { store.loadingLists.contains(.images) && !store.loadedLists.contains(.images) }

    var body: some View {
        ResourceSection {
            toolbar
        } content: {
            if rows.isEmpty {
                ResourceEmpty(symbol: "square.stack.3d.down.right", title: L.t("Aucune image", "No images"),
                              hint: L.t("Téléchargez une image avec le champ ci-dessus.", "Pull an image with the field above."),
                              loading: loading)
            } else {
                table
            }
        }
        .onAppear { store.loadIfNeeded(.images) }
        .confirmationDialog(L.t("Supprimer l'image ?", "Delete image?"), isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { image in
            Button(L.t("Supprimer", "Delete"), role: .destructive) { store.deleteImage(Self.reference(image)) }
        } message: { image in
            Text(Self.reference(image))
        }
        .confirmationDialog(L.t("Supprimer les images orphelines ?", "Prune images?"), isPresented: $confirmPrune) {
            Button(L.t("Supprimer", "Prune"), role: .destructive) { store.pruneImagesList() }
        } message: {
            Text(L.t("Supprime les images sans tag (dangling). Irréversible.", "Removes dangling images. Irreversible."))
        }
    }

    /// Tagged images are removed by name (a shared ID would otherwise refuse), untagged ones by ID.
    private static func reference(_ i: DockerImage) -> String {
        i.repository == "<none>" || i.tag == "<none>" ? i.id : "\(i.repository):\(i.tag)"
    }

    private var toolbar: some View {
        Group {
            TextField(L.t("Image à télécharger (ex. nginx:latest)", "Image to pull (e.g. nginx:latest)"), text: $pullName)
                .textFieldStyle(.roundedBorder).frame(width: 300)
                .onSubmit(pull)
            Button(action: pull) { Label(L.t("Télécharger", "Pull"), systemImage: "arrow.down.circle") }
                .disabled(pulling || pullName.trimmingCharacters(in: .whitespaces).isEmpty)
            if pulling { ProgressView().controlSize(.small) }
            Spacer(minLength: 8)
            Button { pendingDelete = selected } label: { Label(L.t("Supprimer", "Delete"), systemImage: "trash") }
                .disabled(selected == nil)
            Button { confirmPrune = true } label: {
                Label(L.t("Purger les images…", "Prune images…"), systemImage: "sparkles")
            }
        }
    }

    private func pull() {
        let name = pullName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !pulling else { return }
        pulling = true
        store.pullImage(name) { pulling = false; pullName = "" }
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("Repository") { Text($0.image.repository).foregroundColor(.tkText) }.width(min: 140, ideal: 240)
            TableColumn("Tag") { Text($0.image.tag).foregroundColor(.tkText2) }.width(min: 70, ideal: 110)
            TableColumn("ID") { Text($0.image.id).font(ResourceFont.mono).foregroundColor(.tkText2) }.width(min: 90, ideal: 130)
            TableColumn("Size") { Text($0.image.size).font(ResourceFont.mono).foregroundColor(.tkText) }.width(min: 60, ideal: 90)
            TableColumn("Created") { Text($0.image.created).foregroundColor(.tkText2) }.width(min: 90, ideal: 130)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let image = store.images.first(where: { Self.rowID($0) == id }) {
                Button(L.t("Copier l'ID", "Copy ID")) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(image.id, forType: .string)
                }
                Divider()
                Button(L.t("Supprimer…", "Delete…"), role: .destructive) { pendingDelete = image }
            }
        }
        .onDeleteCommand { pendingDelete = selected }
    }
}
