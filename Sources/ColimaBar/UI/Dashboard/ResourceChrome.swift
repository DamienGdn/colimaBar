import SwiftUI
import ColimaBarCore

/// Shared layout of the Images / Volumes / Networks sections: toolbar above a bordered table surface.
struct ResourceSection<Toolbar: View, Content: View>: View {
    @ViewBuilder let toolbar: Toolbar
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) { toolbar }.buttonStyle(.bordered)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tkSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.tkBorder))
        }
        .padding(16)
    }
}

/// Loading / empty placeholder shown instead of a table.
struct ResourceEmpty: View {
    let symbol: String
    let title: String
    let hint: String
    let loading: Bool

    var body: some View {
        VStack(spacing: 8) {
            if loading {
                ProgressView()
                Text(L.t("Chargement…", "Loading…")).foregroundColor(.tkText2)
            } else {
                Image(systemName: symbol).font(.system(size: 30)).foregroundColor(.tkText3)
                Text(title).font(.headline).foregroundColor(.tkText)
                Text(hint).foregroundColor(.tkText2)
            }
        }
    }
}

enum ResourceFont {
    static let mono = Font.system(size: 12, design: .monospaced)
}
