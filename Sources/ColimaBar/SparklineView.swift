import AppKit

/// Mini area chart used for per-container CPU / RAM history.
final class SparklineView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        // Subtle track so an empty / flat chart still reads as a chart
        let track = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        track.fill()

        guard values.count >= 2 else { return }
        let maxVal = values.max() ?? 1.0
        guard maxVal > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        track.addClip()

        let inset: CGFloat = 2          // keep the stroke from being clipped at the top
        let w = bounds.width
        let h = bounds.height - inset * 2
        let step = w / CGFloat(values.count - 1)

        func point(at i: Int) -> CGPoint {
            CGPoint(x: CGFloat(i) * step, y: inset + CGFloat(values[i] / maxVal) * h)
        }

        // Filled area with a vertical fade
        let area = NSBezierPath()
        area.move(to: CGPoint(x: 0, y: 0))
        for i in values.indices { area.line(to: point(at: i)) }
        area.line(to: CGPoint(x: w, y: 0))
        area.close()
        if let gradient = NSGradient(starting: color.withAlphaComponent(0.35),
                                     ending: color.withAlphaComponent(0.03)) {
            gradient.draw(in: area, angle: -90)
        }

        // Line
        let line = NSBezierPath()
        line.move(to: point(at: 0))
        for i in 1..<values.count { line.line(to: point(at: i)) }
        line.lineWidth     = 1.5
        line.lineJoinStyle = .round
        line.lineCapStyle  = .round
        color.setStroke()
        line.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }
}
