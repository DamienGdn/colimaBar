//! Opacity curve for the "breathing" tray icon while Colima is transitioning.
//!
//! Same curve as `BreathingCurve.swift` in the macOS app.

use std::f64::consts::PI;

/// Duration of one full breath, in seconds.
pub const PERIOD_SECS: f64 = 1.6;
/// Lowest opacity reached (at half a period).
pub const MIN_ALPHA: f64 = 0.45;

/// Smooth sinusoid: 1.0 at t = 0, [`MIN_ALPHA`] at `PERIOD_SECS / 2`, periodic.
pub fn breathing_alpha(t_secs: f64) -> f64 {
    let mid = (1.0 + MIN_ALPHA) / 2.0;
    let amp = (1.0 - MIN_ALPHA) / 2.0;
    mid + amp * (2.0 * PI * t_secs / PERIOD_SECS).cos()
}

/// Copies straight (non-premultiplied) RGBA pixels, scaling only their alpha by `factor`.
pub fn scale_alpha(rgba: &[u8], factor: f64) -> Vec<u8> {
    let mut out = rgba.to_vec();
    for px in out.chunks_exact_mut(4) {
        px[3] = (f64::from(px[3]) * factor).round() as u8;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const EPS: f64 = 0.001;

    #[test]
    fn starts_opaque() {
        assert!((breathing_alpha(0.0) - 1.0).abs() < EPS);
    }

    #[test]
    fn min_at_half_period() {
        assert!((breathing_alpha(0.8) - 0.45).abs() < EPS);
    }

    #[test]
    fn periodic() {
        assert!((breathing_alpha(0.3) - breathing_alpha(1.9)).abs() < EPS);
    }

    #[test]
    fn stays_within_bounds() {
        let (lo, hi) = (0.45 - 1e-9, 1.0 + 1e-9);
        for step in 0..64 {
            let t = f64::from(step) * 0.05;
            let a = breathing_alpha(t);
            assert!((lo..=hi).contains(&a), "alpha({t}) = {a}");
        }
    }

    #[test]
    fn scale_alpha_only_touches_alpha() {
        let px: [u8; 8] = [10, 20, 30, 200, 1, 2, 3, 0];
        assert_eq!(scale_alpha(&px, 0.5), [10, 20, 30, 100, 1, 2, 3, 0]);
    }
}
