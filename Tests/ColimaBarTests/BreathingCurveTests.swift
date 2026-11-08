import Foundation
import ColimaBarCore

func test_breathing_startsOpaque() {
    check(abs(BreathingCurve.alpha(at: 0) - 1.0) < 0.001, "alpha(0) is 1.0")
}

func test_breathing_minAtHalfPeriod() {
    check(abs(BreathingCurve.alpha(at: 0.8) - 0.45) < 0.001, "alpha(period/2) is minAlpha")
}

func test_breathing_periodic() {
    check(abs(BreathingCurve.alpha(at: 0.3) - BreathingCurve.alpha(at: 1.9)) < 0.001, "periodic")
}

func test_breathing_bounds() {
    var t = 0.0
    while t < 3.2 {
        let a = BreathingCurve.alpha(at: t)
        check(a >= 0.45 - 1e-9 && a <= 1.0 + 1e-9, "alpha(\(t)) within bounds")
        t += 0.05
    }
}
