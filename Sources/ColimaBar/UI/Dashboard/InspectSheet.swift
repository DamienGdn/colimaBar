import SwiftUI
import AppKit
import ColimaBarCore

/// Read-only `docker inspect` output, monospaced, with a copy button.
struct InspectSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let name: String

    private enum Phase { case loading, loaded(String), failed }
    @State private var phase: Phase = .loading
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.t("Inspection — \(name)", "Inspect — \(name)"))
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.tkText)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                if case .loaded(let json) = phase {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                        copied = true
                    } label: {
                        Label(copied ? L.t("Copié", "Copied") : L.t("Copier", "Copy"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }
            }
            .padding(12)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tkSurface)
            Divider()
            HStack {
                Spacer()
                Button(L.t("Fermer", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 680, height: 540)
        .background(Color.tkBg)
        .onAppear {
            store.inspect(name) { json in phase = json.map { .loaded($0) } ?? .failed }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
        case .failed:
            Text(L.t("Inspection impossible", "Inspect failed")).foregroundColor(.tkText2)
        case .loaded(let json):
            ScrollView([.vertical, .horizontal]) {
                Text(json)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(.tkText)
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}
