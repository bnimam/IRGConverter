import Foundation

/// One control point on a tone curve, in normalized 0…1 input/output space.
public struct CurvePoint: Equatable, Codable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

/// An editable tone curve, evaluated with monotone cubic interpolation.
///
/// Plain Catmull-Rom or a natural spline overshoots between control points,
/// which on a tone curve shows up as banding and reversals — a curve that dips
/// darker where the user asked for brighter. Fritsch-Carlson tangent limiting
/// guarantees the result is monotone wherever the control points are.
public struct ToneCurve: Equatable, Codable, Sendable {
    public var points: [CurvePoint]

    public static let identityPoints = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    public init(points: [CurvePoint] = ToneCurve.identityPoints) {
        self.points = points
    }

    public var isIdentity: Bool {
        points.count == ToneCurve.identityPoints.count
            && zip(points, ToneCurve.identityPoints).allSatisfy {
                abs($0.x - $1.x) < 1e-6 && abs($0.y - $1.y) < 1e-6
            }
    }

    /// Control points cleaned up for evaluation: sorted, de-duplicated on x, and
    /// anchored at both ends so the curve always spans the full range.
    public var normalized: [CurvePoint] {
        var sorted = points.sorted { $0.x < $1.x }
        var deduped: [CurvePoint] = []
        for p in sorted where deduped.last.map({ p.x - $0.x > 1e-4 }) ?? true {
            deduped.append(p)
        }
        sorted = deduped
        if sorted.isEmpty { return ToneCurve.identityPoints }
        if sorted[0].x > 1e-4 { sorted.insert(CurvePoint(x: 0, y: sorted[0].y), at: 0) }
        if sorted[sorted.count - 1].x < 1 - 1e-4 {
            sorted.append(CurvePoint(x: 1, y: sorted[sorted.count - 1].y))
        }
        return sorted
    }

    public func value(at input: Float) -> Float {
        let pts = normalized
        let x = min(max(input, 0), 1)
        guard pts.count > 1 else { return pts.first?.y ?? x }

        let n = pts.count
        var secants = [Float](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            secants[i] = (pts[i + 1].y - pts[i].y) / (pts[i + 1].x - pts[i].x)
        }

        var tangents = [Float](repeating: 0, count: n)
        tangents[0] = secants[0]
        tangents[n - 1] = secants[n - 2]
        for i in 1..<(n - 1) { tangents[i] = (secants[i - 1] + secants[i]) / 2 }

        // Fritsch-Carlson limiting keeps the interpolant monotone.
        for i in 0..<(n - 1) {
            if secants[i] == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
            } else {
                let alpha = tangents[i] / secants[i]
                let beta = tangents[i + 1] / secants[i]
                let magnitude = (alpha * alpha + beta * beta).squareRoot()
                if magnitude > 3 {
                    let scale = 3 / magnitude
                    tangents[i] = scale * alpha * secants[i]
                    tangents[i + 1] = scale * beta * secants[i]
                }
            }
        }

        var segment = 0
        while segment < n - 2, x > pts[segment + 1].x { segment += 1 }
        let p0 = pts[segment], p1 = pts[segment + 1]
        let h = p1.x - p0.x
        let t = h > 0 ? (x - p0.x) / h : 0
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        let y = h00 * p0.y + h10 * h * tangents[segment] + h01 * p1.y + h11 * h * tangents[segment + 1]
        return min(max(y, 0), 1)
    }

    /// `size` samples of the curve, scaled to 0…255 for use as a lookup table.
    public func lookupTable(size: Int = 256) -> [Float] {
        (0..<size).map { value(at: Float($0) / Float(size - 1)) * 255 }
    }
}

/// Master plus per-channel tone curves.
public struct ToneCurves: Equatable, Codable, Sendable {
    public var master = ToneCurve()
    public var red = ToneCurve()
    public var green = ToneCurve()
    public var blue = ToneCurve()

    public init() {}

    public var isIdentity: Bool {
        master.isIdentity && red.isIdentity && green.isIdentity && blue.isIdentity
    }

    /// One composed table per output channel: master first, then the channel's
    /// own curve, so only a single lookup is needed per pixel per channel.
    func composedTables(size: Int = 256) -> [[Float]] {
        let masterTable = master.lookupTable(size: size)
        return [red, green, blue].map { channel in
            (0..<size).map { i -> Float in
                let afterMaster = masterTable[i] / 255
                return channel.value(at: afterMaster) * 255
            }
        }
    }
}

/// Unsharp mask over the finished image.
///
/// Applied last, after the tone curves, because what it amplifies is the edge
/// contrast of the picture as rendered — sharpening before a curve that lifts the
/// shadows five times over would put five times the halo there.
public struct Sharpening: Equatable, Codable, Sendable {
    /// How much of the detail layer to add back. 0 is off, which is the default —
    /// sharpening is a per-image decision, not something to bake into a look.
    public var amount: Float = 0

    /// Gaussian radius, in pixels **of the full-resolution image**.
    ///
    /// Small values sharpen fine texture; large ones turn into local contrast. The
    /// unit is deliberately the exported file's pixels rather than the rendered
    /// ones, so the number means the same thing whatever the preview is set to.
    public var radius: Float = 1.0

    /// Detail quieter than this, in levels out of 255, is left alone.
    ///
    /// Sharpening amplifies noise and sensor grain along with real edges, and a
    /// full-spectrum capture at −1 EV has plenty of both in the sky. The knee is
    /// smooth (`d² / (d² + threshold²)`) rather than a hard cut, which would put a
    /// visible boundary where the detail crosses it.
    public var threshold: Float = 0

    public static let amountRange: ClosedRange<Float> = 0...2
    public static let radiusRange: ClosedRange<Float> = 0.3...3
    public static let thresholdRange: ClosedRange<Float> = 0...25

    /// Below this radius, in rendered pixels, the blur and the image are the same
    /// thing and there is no detail layer to add back — so sharpening is skipped
    /// rather than faked. This is why a downsampled preview shows less sharpening
    /// than the export does, and the panel says as much.
    public static let minimumVisibleRadius: Float = 0.3

    public init() {}

    public var isIdentity: Bool { amount == 0 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Sharpening()
        amount = (try? c.decode(Float.self, forKey: .amount)) ?? d.amount
        radius = (try? c.decode(Float.self, forKey: .radius)) ?? d.radius
        threshold = (try? c.decode(Float.self, forKey: .threshold)) ?? d.threshold
    }
}

/// Ordinary photo edits, applied after the Aerochrome transform.
///
/// Deliberately separate from `AerochromeParams`' transform fields: the
/// auto-tune rewrites those from the image and leaves these alone, so a look you
/// dialled in survives pressing Auto or dragging Look Strength.
public struct AerochromeAdjustments: Equatable, Codable, Sendable {
    /// Stops. Applied first, as a straight multiply.
    public var exposure: Float = 0
    /// Gain about a 0.5 pivot, from -1 (flat) to +1 (double).
    public var contrast: Float = 0
    /// Endpoint moves. Positive opens the range, negative compresses it.
    public var whites: Float = 0
    public var blacks: Float = 0
    /// Tonal-region lifts. Their masks are scaled so that neither can push a
    /// pixel past black or white, which is why their maximum shift is a fairly
    /// gentle ~0.15 — see the derivation in `applyAdjustments`.
    public var highlights: Float = 0
    public var shadows: Float = 0
    /// Chroma scaling about luminance.
    public var saturation: Float = 0
    /// Saturation weighted by how unsaturated the pixel already is, so it lifts
    /// muted colour without pushing the already-vivid foliage further.
    public var vibrance: Float = 0
    /// Red/blue tilt.
    public var warmth: Float = 0
    /// Green/magenta tilt.
    public var tint: Float = 0

    public var curves = ToneCurves()

    public var sharpening = Sharpening()

    public init() {}

    /// True when nothing in the fused tone-and-colour pass would move a pixel.
    ///
    /// The curves and the unsharp mask each have their own pass, so they are not
    /// part of this — a sharpening-only edit should not drag 20 megapixels through
    /// a scalar loop that only multiplies by one.
    public var isToneIdentity: Bool {
        exposure == 0 && contrast == 0 && whites == 0 && blacks == 0
            && highlights == 0 && shadows == 0 && saturation == 0 && vibrance == 0
            && warmth == 0 && tint == 0
    }

    public var isIdentity: Bool {
        isToneIdentity && curves.isIdentity && sharpening.isIdentity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AerochromeAdjustments()
        func float(_ key: CodingKeys, _ fallback: Float) -> Float {
            (try? c.decode(Float.self, forKey: key)) ?? fallback
        }
        exposure = float(.exposure, d.exposure)
        contrast = float(.contrast, d.contrast)
        whites = float(.whites, d.whites)
        blacks = float(.blacks, d.blacks)
        highlights = float(.highlights, d.highlights)
        shadows = float(.shadows, d.shadows)
        saturation = float(.saturation, d.saturation)
        vibrance = float(.vibrance, d.vibrance)
        warmth = float(.warmth, d.warmth)
        tint = float(.tint, d.tint)
        curves = (try? c.decode(ToneCurves.self, forKey: .curves)) ?? d.curves
        sharpening = (try? c.decode(Sharpening.self, forKey: .sharpening)) ?? d.sharpening
    }
}

/// 256-bin distribution of the rendered output.
public struct Histogram: Equatable, Sendable {
    public var red: [Int]
    public var green: [Int]
    public var blue: [Int]
    public var luma: [Int]
    /// Largest bin across all four series, for scaling a plot.
    public var peak: Int
    /// Fraction of pixels at 0 and at 255, per channel.
    public var clippedShadows: Double
    public var clippedHighlights: Double

    public static let binCount = 256

    init(red: [Int], green: [Int], blue: [Int], luma: [Int], pixelCount: Int) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luma = luma
        // The extreme bins are excluded from the peak: a large flat region of
        // pure black would otherwise flatten the rest of the plot to nothing.
        let interior = [red, green, blue, luma].flatMap { $0.dropFirst().dropLast() }
        self.peak = max(interior.max() ?? 1, 1)
        let n = max(pixelCount, 1)
        self.clippedShadows = Double(red[0] + green[0] + blue[0]) / Double(3 * n)
        self.clippedHighlights = Double(red[255] + green[255] + blue[255]) / Double(3 * n)
    }
}
