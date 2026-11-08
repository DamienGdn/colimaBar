import AppKit
import SwiftUI

/// Shared visual helpers: SF Symbols, status dots and brand colors.
enum Theme {

    /// Brand palette (matches design/AppIcon.svg).
    enum Brand {
        static let indigo = NSColor(srgbRed: 0.231, green: 0.298, blue: 0.792, alpha: 1)  // #3B4CCA
        static let teal   = NSColor(srgbRed: 0.071, green: 0.659, blue: 0.580, alpha: 1)  // #12A894
        static let orange = NSColor(srgbRed: 0.949, green: 0.420, blue: 0.114, alpha: 1)  // #F26B1D
        static let navy   = NSColor(srgbRed: 0.071, green: 0.102, blue: 0.290, alpha: 1)  // #121A4A
    }

    /// Fixed (non-adaptive) status colors for use on the dark header band.
    enum Header {
        static let running       = NSColor(srgbRed: 0.204, green: 0.820, blue: 0.478, alpha: 1)  // #34D17A
        static let transitioning = NSColor(srgbRed: 1.000, green: 0.702, blue: 0.251, alpha: 1)  // #FFB340
    }

    /// Header band gradient (indigo to navy).
    static let headerGradient = LinearGradient(
        colors: [Color(nsColor: Brand.indigo), Color(nsColor: Brand.navy)],
        startPoint: .leading, endPoint: .trailing)

    /// Wordmark gradient (teal to orange).
    static let wordmarkGradient = LinearGradient(
        colors: [Color(nsColor: Brand.teal), Color(nsColor: Brand.orange)],
        startPoint: .leading, endPoint: .trailing)

    static let radius: CGFloat = 10

    /// Design tokens, mirroring tauri/src/styles.css (light in :root, dark in prefers-color-scheme: dark).
    enum Tokens {
        private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                    green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: a)
        }
        private static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? light : dark
            }
        }

        static let bg          = dynamic(hex(0xF5F6FA), hex(0x0E1230))
        static let surface     = dynamic(hex(0xFFFFFF), hex(0x161B3F))
        static let surface2    = dynamic(hex(0xF0F2F8), hex(0x1C2250))
        static let border      = dynamic(hex(0xE1E4EE), hex(0x2A3166))
        static let text        = dynamic(hex(0x161A36), hex(0xEEF0FB))
        static let text2       = dynamic(hex(0x5B6188), hex(0xA9AFD6))
        static let text3       = dynamic(hex(0x9298B8), hex(0x6E75A3))
        static let accent      = dynamic(hex(0x3B4CCA), hex(0x7C8CFF))
        static let accentSoft  = dynamic(hex(0x3B4CCA, 0.10), hex(0x7C8CFF, 0.16))
        static let rowHover    = dynamic(hex(0xF4F5FB), hex(0x1B2150))
        static let rowSelected = dynamic(hex(0x3B4CCA, 0.10), hex(0x7C8CFF, 0.18))
        static let green       = dynamic(hex(0x1FA855), hex(0x34D17A))
        static let greenSoft   = dynamic(hex(0x1FA855, 0.12), hex(0x34D17A, 0.14))
        static let amber       = dynamic(hex(0xE08600), hex(0xFFB340))
        static let amberSoft   = dynamic(hex(0xE08600, 0.14), hex(0xFFB340, 0.14))
        static let red         = dynamic(hex(0xD93A3A), hex(0xFF6B6B))
        static let redSoft     = dynamic(hex(0xD93A3A, 0.12), hex(0xFF6B6B, 0.14))
    }

    /// Semantic status colors used across the menu, icon and tables.
    enum Status {
        static let running      = NSColor.systemGreen
        static let transitioning = NSColor.systemOrange
        static let stopped      = NSColor.tertiaryLabelColor
        static let warning      = NSColor.systemOrange
    }

    /// SF Symbol sized for menus and small buttons. Returns nil if the symbol
    /// is unavailable on the running macOS version.
    static func symbol(_ name: String,
                       _ description: String? = nil,
                       pointSize: CGFloat = 13,
                       weight: NSFont.Weight = .regular) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: description) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return image.withSymbolConfiguration(config) ?? image
    }

    /// Small filled circle used as a colored status indicator in menus.
    static func statusDot(_ color: NSColor, diameter: CGFloat = 8) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

extension NSMenuItem {
    /// Attaches an SF Symbol to the item and returns it (for fluent setup).
    @discardableResult
    func withSymbol(_ name: String) -> NSMenuItem {
        image = Theme.symbol(name, title)
        return self
    }
}

extension Color {
    static let tkBg          = Color(nsColor: Theme.Tokens.bg)
    static let tkSurface     = Color(nsColor: Theme.Tokens.surface)
    static let tkSurface2    = Color(nsColor: Theme.Tokens.surface2)
    static let tkBorder      = Color(nsColor: Theme.Tokens.border)
    static let tkText        = Color(nsColor: Theme.Tokens.text)
    static let tkText2       = Color(nsColor: Theme.Tokens.text2)
    static let tkText3       = Color(nsColor: Theme.Tokens.text3)
    static let tkAccent      = Color(nsColor: Theme.Tokens.accent)
    static let tkAccentSoft  = Color(nsColor: Theme.Tokens.accentSoft)
    static let tkRowHover    = Color(nsColor: Theme.Tokens.rowHover)
    static let tkRowSelected = Color(nsColor: Theme.Tokens.rowSelected)
    static let tkGreen       = Color(nsColor: Theme.Tokens.green)
    static let tkGreenSoft   = Color(nsColor: Theme.Tokens.greenSoft)
    static let tkAmber       = Color(nsColor: Theme.Tokens.amber)
    static let tkAmberSoft   = Color(nsColor: Theme.Tokens.amberSoft)
    static let tkRed         = Color(nsColor: Theme.Tokens.red)
    static let tkRedSoft     = Color(nsColor: Theme.Tokens.redSoft)
}

// MARK: - AppKit helpers (token-based, appearance-aware)

/// Layer-backed view whose fill/border are dynamic token colors, re-resolved on every appearance change.
final class ThemedView: NSView {
    var fill: NSColor? { didSet { needsDisplay = true } }
    var borderColor: NSColor? { didSet { needsDisplay = true } }
    var borderWidth: CGFloat = 0 { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }

    init(fill: NSColor? = nil, border: NSColor? = nil, radius: CGFloat = 0) {
        self.fill = fill
        self.borderColor = border
        self.borderWidth = border == nil ? 0 : 1
        self.cornerRadius = radius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = radius > 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = fill?.cgColor
            layer.borderColor = borderColor?.cgColor
        }
        layer.borderWidth = borderWidth
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

extension Theme {
    /// Surface card (rounded, bordered) wrapping a scroll view; the table/text inside draws on `surface`.
    static func card(wrapping scroll: NSScrollView) -> ThemedView {
        let card = ThemedView(fill: Tokens.surface, border: Tokens.border, radius: radius)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: card.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    /// Transparent table sitting on a card.
    static func styleTable(_ table: NSTableView) {
        table.backgroundColor = .clear
        table.gridColor = Tokens.border
        table.usesAlternatingRowBackgroundColors = false
        table.intercellSpacing = NSSize(width: 8, height: 2)
        table.rowHeight = 26
    }

    /// Token-colored label (system font unless a font is given).
    static func style(_ label: NSTextField, color: NSColor = Tokens.text,
                      font: NSFont = .systemFont(ofSize: 12)) {
        label.textColor = color
        label.font = font
    }

    /// Thin separator line using the border token.
    static func separator() -> ThemedView {
        let v = ThemedView(fill: Tokens.border)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }
}
