import SwiftUI
import AppKit
import ColimaBarCore

/// "Colima" + gradient "Bar".
struct BrandWordmark: View {
    let size: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            Text("Colima").foregroundColor(.white)
            Text("Bar").foregroundStyle(Theme.wordmarkGradient)
        }
        .font(.system(size: size, weight: .bold))
    }
}

/// Rounded app icon.
struct BrandLogo: View {
    let size: CGFloat
    var body: some View {
        Group {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Color.tkAccent
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

/// Header pill: "Colima · Running".
struct StatePill: View {
    let state: ColimaRunningState

    private var label: String {
        switch state {
        case .running: return L.t("En marche", "Running")
        case .stopped: return L.t("Arrêté", "Stopped")
        case .transitioning: return L.t("Démarrage…", "Starting…")
        case .unknown: return L.t("Inconnu", "Unknown")
        }
    }
    private var dot: Color {
        switch state {
        case .running: return Color(nsColor: Theme.Header.running)
        case .transitioning: return Color(nsColor: Theme.Header.transitioning)
        default: return Color.tkText3
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(color: dot)
            Text("Colima · \(label)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
    }
}

enum BadgeKind { case success, warning, danger, neutral }

struct StatusBadge: View {
    let text: String
    let kind: BadgeKind

    private var fg: Color {
        switch kind {
        case .success: return .tkGreen
        case .warning: return .tkAmber
        case .danger: return .tkRed
        case .neutral: return .tkText2
        }
    }
    private var bg: Color {
        switch kind {
        case .success: return .tkGreenSoft
        case .warning: return .tkAmberSoft
        case .danger: return .tkRedSoft
        case .neutral: return .tkSurface2
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(bg))
            .lineLimit(1)
    }

    static func forContainer(_ c: DockerContainer) -> StatusBadge {
        if let h = c.health {
            switch h {
            case .healthy: return StatusBadge(text: "healthy", kind: .success)
            case .unhealthy: return StatusBadge(text: "unhealthy", kind: .danger)
            case .starting: return StatusBadge(text: "starting", kind: .warning)
            }
        }
        switch c.state {
        case .running: return StatusBadge(text: "Running", kind: .success)
        case .restarting: return StatusBadge(text: "Restarting", kind: .warning)
        case .paused: return StatusBadge(text: "Paused", kind: .warning)
        case .dead: return StatusBadge(text: "Dead", kind: .danger)
        case .exited: return StatusBadge(text: "Exited", kind: .neutral)
        case .created: return StatusBadge(text: "Created", kind: .neutral)
        case .removing: return StatusBadge(text: "Removing", kind: .warning)
        case .unknown: return StatusBadge(text: "Unknown", kind: .neutral)
        }
    }

    static func forStack(_ s: StackStatus) -> StatusBadge {
        switch s {
        case .allRunning: return StatusBadge(text: L.t("Tout démarré", "All running"), kind: .success)
        case let .partial(running, total):
            return StatusBadge(text: L.t("\(running)/\(total) démarrés", "\(running)/\(total) running"), kind: .warning)
        case .stopped: return StatusBadge(text: L.t("Arrêté", "Stopped"), kind: .neutral)
        }
    }
}

/// Thin gauge on the header band.
struct HeaderGauge: View {
    let label: String
    let value: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 6)
                Text(value).foregroundColor(.white).monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Theme.wordmarkGradient)
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 4)
        }
    }
}

/// Clickable host port, opens http://localhost:<port>.
struct PortChip: View {
    let port: Int
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
        } label: {
            Text(String(port))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.tkAccent)
                .underline(hovering)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.tkAccentSoft))
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityLabel(L.t("Ouvrir localhost:\(port)", "Open localhost:\(port)"))
        .help("http://localhost:\(port)")
    }
}

/// Line chart with gradient fill.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count >= 2 {
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let lo = min(values.min() ?? 0, 0)
        let hi = max(values.max() ?? 1, lo + 1)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step,
                    y: size.height - CGFloat((v - lo) / (hi - lo)) * (size.height - 2) - 1)
        }
    }
}

/// Numeric text, "—" when nil.
struct MetricText: View {
    let value: Double?
    let format: (Double) -> String

    init(_ value: Double?, format: @escaping (Double) -> String = { String(format: "%.1f", $0) }) {
        self.value = value
        self.format = format
    }

    var body: some View {
        Text(value.map(format) ?? "—").monospacedDigit()
    }
}
