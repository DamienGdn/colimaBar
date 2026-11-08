import Foundation

/// Opacity curve for the "breathing" status icon while Colima is transitioning.
public enum BreathingCurve {
    /// Duration of one full breath, in seconds.
    public static let period: TimeInterval = 1.6
    /// Lowest opacity reached (at half a period).
    public static let minAlpha: Double = 0.45

    /// Smooth sinusoid: 1.0 at t = 0, `minAlpha` at `period / 2`, periodic.
    public static func alpha(at time: TimeInterval) -> Double {
        let mid = (1.0 + minAlpha) / 2
        let amp = (1.0 - minAlpha) / 2
        return mid + amp * cos(2 * Double.pi * time / period)
    }
}
