import AppKit

/// Shared visual helpers: SF Symbols, status dots and brand colors.
enum Theme {

    /// Brand palette (matches design/AppIcon.svg).
    enum Brand {
        static let indigo = NSColor(srgbRed: 0.231, green: 0.298, blue: 0.792, alpha: 1)  // #3B4CCA
        static let teal   = NSColor(srgbRed: 0.071, green: 0.659, blue: 0.580, alpha: 1)  // #12A894
        static let orange = NSColor(srgbRed: 0.949, green: 0.420, blue: 0.114, alpha: 1)  // #F26B1D
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
