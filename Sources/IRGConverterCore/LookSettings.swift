import Foundation

/// The three high-level dials that drive the transform.
///
/// This replaces the old auto-tune. That measured the image — picking the infrared
/// channel by a correlation score, estimating crosstalk from percentile ratios, and
/// transferring a calibration onto the result. It was removed because it did not
/// work well enough to trust: the channel score was fooled by any image where two
/// channels happened to be proportional, the crosstalk estimate assumed the
/// brightest infrared in the frame was pure vegetation, and every attempt to derive
/// the six transform controls from those measurements landed somewhere wrong —
/// foliage yellow, or the sky orange, or the shadows lifted flat.
///
/// What is left is deterministic and inspectable: a pure function of these dials
/// and the calibration, with no dependence on the image at all. The same settings
/// give the same numbers on every frame, which is what makes a preset mean
/// something. When it is wrong the fix is to move a slider, and the info popovers
/// say which way.
public struct LookSettings: Equatable, Codable, Sendable {
    /// How hard to push the conversion, 0 to 1.
    ///
    /// Moves the infrared curve and both subtractions together — brightness and
    /// purity at once, because that is what "more Aerochrome" means. The range is
    /// deliberately wide: 0 is barely converted and 1 is well past tasteful, so the
    /// useful settings are somewhere inside rather than at the top.
    public var strength: Float = 0.5

    /// Pushes foliage between pure red and magenta-pink, −1 to 1.
    ///
    /// Works by leaving more or less infrared in the green group. Negative is
    /// purer red, positive is more magenta.
    public var magenta: Float = 0

    /// Overall density, −1 to 1. Negative renders lighter, positive denser.
    public var density: Float = 0

    public static let strengthRange: ClosedRange<Float> = 0...1
    public static let magentaRange: ClosedRange<Float> = -1...1
    public static let densityRange: ClosedRange<Float> = -1...1

    public init(strength: Float = 0.5, magenta: Float = 0, density: Float = 0) {
        self.strength = strength
        self.magenta = magenta
        self.density = density
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LookSettings()
        strength = (try? c.decode(Float.self, forKey: .strength)) ?? d.strength
        magenta = (try? c.decode(Float.self, forKey: .magenta)) ?? d.magenta
        density = (try? c.decode(Float.self, forKey: .density)) ?? d.density
    }

    // MARK: - Derived transform values

    private var clampedStrength: Double { Double(min(max(strength, 0), 1)) }

    /// Where the infrared group's curve sits.
    ///
    /// Spans a much wider range than the old auto-tune's, which only moved the
    /// vegetation anchor by ±0.15 and so barely changed the picture across the
    /// whole slider. 0.5 reproduces the calibration exactly.
    public var gammaBy: Float {
        let s = clampedStrength
        let calibrated = AerochromeCalibration.gammaBy
        // Geometric either side of the calibration, so equal slider distances feel
        // equal — gamma is multiplicative.
        let span = 3.2
        return Float(calibrated * pow(span, (s - 0.5) * 2))
    }

    /// Multiplier on the calibrated subtractions. Exactly 1 at the midpoint, so
    /// strength 0.5 reproduces the calibration, and spanning 0.15…1.85 either side
    /// — a factor of twelve from end to end.
    private var subtractionScale: Double {
        1 + 1.7 * (clampedStrength - 0.5)
    }

    /// Opacity of the Subtract layer on the red group.
    public var subtractIRRed: Float {
        Float(min(max(AerochromeCalibration.subtractIRRed * subtractionScale, 0), 2))
    }

    /// Opacity of the Subtract layer on the green group, including the magenta lean.
    public var subtractIRGreen: Float {
        let base = AerochromeCalibration.subtractIRGreen * subtractionScale
        // Positive magenta leaves infrared in the green group, so it subtracts
        // less. The base is large because the calibrated green subtraction is only
        // 0.10 — a smaller factor moved the blue output too little to see.
        let lean = pow(9.0, -Double(min(max(magenta, -1), 1)))
        return Float(min(max(base * lean, 0), 2))
    }

    /// The final curves layer.
    public var overallGamma: Float {
        let calibrated = AerochromeCalibration.overallGamma
        let lean = pow(2.2, -Double(min(max(density, -1), 1)))
        return Float(min(max(calibrated * lean, 0.25), 4))
    }

    /// Write the derived values into a parameter set.
    ///
    /// Only the four controls the dials actually drive are touched. The two visible
    /// group curves are left alone deliberately: no dial moves them, so resetting
    /// them here would silently undo a hand adjustment every time a Look slider
    /// was nudged.
    public func applied(to params: AerochromeParams) -> AerochromeParams {
        var p = params
        p.gammaBy = gammaBy
        p.subtractIRRed = subtractIRRed
        p.subtractIRGreen = subtractIRGreen
        p.overallGamma = overallGamma
        return p
    }
}
