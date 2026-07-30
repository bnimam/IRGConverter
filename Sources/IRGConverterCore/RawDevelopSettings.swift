import Foundation

/// How a camera RAW file is developed before the transform sees it.
///
/// Defaults are measured, not guessed. On the sample frame, against the
/// alternatives:
///
/// | development | IR channel picked | visible agreement | IR leak | red clipped |
/// |---|---|---|---|---|
/// | as shot | green (wrong) | 0.904 | 0.754 | 9.8% |
/// | neutral, 0 EV | blue | 0.880 | 0.517 | 9.6% |
/// | **neutral, −1 EV** | **blue** | **0.944** | **0.496** | **0.8%** |
/// | 5500 K, −1 EV | blue | 0.935 | 0.566 | 1.0% |
/// | 2500 K, 0 EV | green (wrong) | 0.981 | 0.821 | 0.7% |
///
/// Two separate problems, two separate levers:
///
/// - **Balance.** A full-spectrum camera's as-shot white balance is calibrated
///   for visible light it can no longer see. Applied, it pushes red toward
///   clipping and crushes green, and the infrared channel can no longer be
///   identified — the measurement picks green instead of blue. Neutral balance
///   keeps the three channels on a common scale, which is what the transform
///   assumes. Notice that correcting this with a *colour temperature* does not
///   work: cooling the image far enough to stop red clipping also squashes the
///   channels together and loses the infrared channel entirely.
/// - **Level.** Clipping is a level problem, so it gets fixed with exposure.
///   One stop of headroom drops clipped red pixels from 9.6% to 0.8% and, as a
///   result, *raises* the agreement between the two recovered visible channels
///   from 0.880 to 0.944. Nothing is lost: the auto-tune normalizes from
///   percentiles, so it simply adapts to the darker input.
public struct RawDevelopSettings: Equatable, Codable, Sendable {
    /// Balance the three channels equally instead of applying a colour
    /// temperature. On by default — see the note above for why a temperature
    /// cannot substitute for this.
    public var useNeutralBalance: Bool = true

    /// Colour temperature in kelvin, used when `useNeutralBalance` is off.
    /// 5500 K is nominal daylight, which is what this app's subject matter —
    /// bright sun on healthy vegetation — is shot in.
    public var temperature: Float = 5500

    /// Green/magenta balance, used when `useNeutralBalance` is off.
    public var tint: Float = 0

    /// Highlight headroom in stops. Negative values protect the red channel,
    /// which is the first to clip on a yellow-filtered full-spectrum capture.
    public var exposure: Float = -1.0

    public static let temperatureRange: ClosedRange<Float> = 2000...12000
    public static let tintRange: ClosedRange<Float> = -150...150
    public static let exposureRange: ClosedRange<Float> = -3...1

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RawDevelopSettings()
        useNeutralBalance = (try? c.decode(Bool.self, forKey: .useNeutralBalance)) ?? d.useNeutralBalance
        temperature = (try? c.decode(Float.self, forKey: .temperature)) ?? d.temperature
        tint = (try? c.decode(Float.self, forKey: .tint)) ?? d.tint
        exposure = (try? c.decode(Float.self, forKey: .exposure)) ?? d.exposure
    }
}
