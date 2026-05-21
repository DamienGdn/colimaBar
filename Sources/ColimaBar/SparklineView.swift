import AppKit

final class SparklineView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var color: NSColor = .systemBlue

    override func draw(_ dirtyRect: NSRect) {
        guard values.count >= 2 else { return }
        let maxVal = values.max() ?? 1.0
        guard maxVal > 0 else { return }

        let w = bounds.width
        let h = bounds.height
        let step = w / CGFloat(values.count - 1)

        func point(at i: Int) -> CGPoint {
            CGPoint(x: CGFloat(i) * step, y: CGFloat(values[i] / maxVal) * h)
        }

        // Filled area
        let area = NSBezierPath()
        area.move(to: CGPoint(x: 0, y: 0))
        for i in values.indices { area.line(to: point(at: i)) }
        area.line(to: CGPoint(x: w, y: 0))
        area.close()
        color.withAlphaComponent(0.25).setFill()
        area.fill()

        // Line
        let line = NSBezierPath()
        line.move(to: point(at: 0))
        for i in 1..<values.count { line.line(to: point(at: i)) }
        line.lineWidth = 1.5
        color.setStroke()
        line.stroke()
    }
}
