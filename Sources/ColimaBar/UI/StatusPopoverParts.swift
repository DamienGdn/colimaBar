import SwiftUI
import ColimaBarCore

// Building blocks of `StatusPopoverView`.

/// Clickable stack / container line.
struct PopoverRow: View {
    let icon: String
    let title: String
    let badge: StatusBadge
    let height: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(.tkText2).frame(width: 16)
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(.tkText)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                badge
            }
            .padding(.horizontal, 6)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.tkRowHover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDisappear { hovering = false }   // popover closed while hovered
        .help(L.t("Ouvrir dans le Dashboard", "Open in Dashboard"))
    }
}

/// Discreet clickable warning line.
struct PopoverBanner: View {
    let icon: String
    let tint: Color
    let fill: Color
    let text: String
    let action: String
    var busy = false
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text).foregroundColor(.tkText2).font(.system(size: 11))
                    Text(action).foregroundColor(tint).font(.system(size: 12, weight: .semibold))
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if busy {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(tint)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

/// Last error, dismissible.
struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.tkRed)
            Text(message).font(.system(size: 11.5)).foregroundColor(.tkText)
                .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.tkText2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Fermer", "Dismiss")).help(L.t("Fermer", "Dismiss"))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.tkRedSoft))
    }
}

struct PopoverButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(primary ? .tkOnBrand : .tkText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(primary ? Color.tkAccent : Color.tkSurface2))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? Color.tkAccent : Color.tkBorder))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
