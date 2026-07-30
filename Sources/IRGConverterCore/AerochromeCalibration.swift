import Foundation

/// The shipped defaults, and the measurements of the frame they were fitted on.
///
/// `AerochromeProcessor.autoTune` transfers this calibration onto a new image
/// rather than re-fitting from nothing, so these constants are the anchor the
/// whole derivation is expressed relative to.
public enum AerochromeCalibration {
    /// Infrared level of the brightest vegetation on the reference frame.
    public static let vegetationIR = 0.231
    /// Measured infrared leakage into each visible channel on that frame.
    public static let crosstalkRed = 1.97
    public static let crosstalkGreen = 0.33

    public static let gammaBy = 2.15
    public static let subtractIRRed = 0.30
    public static let gammaRx = 0.50
    public static let gammaGx = 1.30
    public static let subtractIRGreen = 0.10
    public static let overallGamma = 1.85

    /// Where vegetation ends up in the infrared group under the above.
    public static var vegetationSignal: Double { pow(vegetationIR, 1 / gammaBy) }
    public static var crosstalkLoadRed: Double { crosstalkRed * vegetationIR }
    public static var crosstalkLoadGreen: Double { crosstalkGreen * vegetationIR }
}
