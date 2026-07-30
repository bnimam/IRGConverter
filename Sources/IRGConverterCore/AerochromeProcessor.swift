import Accelerate
import CoreGraphics
import CoreImage
import Foundation

/// Render the result as grey instead of false colour, and from which signal.
public enum MonochromeSource: String, CaseIterable, Equatable, Codable, Sendable {
    case off
    /// The infrared signal alone — classic black-and-white infrared.
    case infrared
    case visibleRed
    case visibleGreen
    /// Rec. 709 luminance of the false-colour composite, so the channel map and
    /// every curve still shape the result.
    case luminance

    public var label: String {
        switch self {
        case .off: return "Off (colour)"
        case .infrared: return "Infrared"
        case .visibleRed: return "Visible red"
        case .visibleGreen: return "Visible green"
        case .luminance: return "Composite luminance"
        }
    }

    /// Index into the signal triple: 0 = visible red, 1 = visible green,
    /// 2 = infrared. Nil for the modes that are not a single signal.
    var signalIndex: Int? {
        switch self {
        case .infrared: return 2
        case .visibleRed: return 0
        case .visibleGreen: return 1
        case .off, .luminance: return nil
        }
    }
}

/// Parameters for the IRG → Aerochrome transform.
///
/// The transform is the Photoshop layer workflow from `photoshop_method.md`:
///
/// - the blue group is infrared, with a curves adjustment on it;
/// - the red group has the infrared layer on top in **Subtract** at some opacity,
///   then a curves adjustment *above* that;
/// - the green group has a curves adjustment *below* the subtract;
/// - each group is channel-mixed to a single output — infrared to red, visible
///   red to green, visible green to blue — and screened together;
/// - a final curves layer lifts the whole thing.
///
/// Photoshop's Subtract clamps at zero and layer opacity scales the subtrahend,
/// so `base - opacity * blend` clamped at 0 is exact. Dragging the centre of a
/// Curves adjustment is a gamma move, so every curve here is `v ^ (1 / gamma)`
/// with gamma above 1 brightening. Screening channel-isolated groups is plain
/// recombination.
public struct AerochromeParams: Equatable, Codable, Sendable {
    /// Source channel (0 = red, 1 = green, 2 = blue) carrying infrared.
    ///
    /// Defaults to **blue**, which is where infrared lands on a yellow-filtered
    /// full-spectrum camera: the filter blocks visible blue but the Bayer array
    /// is transparent to IR, so the blue photosites see IR and almost nothing
    /// else. Red also sees a lot of IR, but mixed with visible red, which makes
    /// it useless as a reference. Set to 0 for a file already swapped into IRG
    /// order.
    public var sourceIR: Int = 2
    /// Source channel carrying visible red.
    public var sourceVisibleRed: Int = 0
    /// Source channel carrying visible green.
    public var sourceVisibleGreen: Int = 1

    /// Curves on the infrared (blue) group. Above 1 brightens.
    public var gammaBy: Float = 2.15

    /// Opacity of the Subtract layer on the red group.
    public var subtractIRRed: Float = 0.30
    /// Curves on the red group, applied *after* the subtract.
    public var gammaRx: Float = 0.50

    /// Curves on the green group, applied *before* the subtract.
    public var gammaGx: Float = 1.30
    /// Opacity of the Subtract layer on the green group.
    public var subtractIRGreen: Float = 0.10

    /// The final curves layer over the whole composite. Above 1 brightens.
    public var overallGamma: Float = 1.85

    /// Which signal drives each output channel: 0 = visible red, 1 = visible
    /// green, 2 = infrared. The default is the Aerochrome false-colour shift —
    /// infrared to red, visible red to green, visible green to blue.
    public var outputMapR: Int = 2
    public var outputMapG: Int = 0
    public var outputMapB: Int = 1

    public var monochrome: MonochromeSource = .off

    /// Ordinary photo edits applied after the transform. Left untouched by the
    /// auto-tune, so anything dialled in here survives pressing Auto.
    public var adjustments = AerochromeAdjustments()

    public init() {}

    /// Decoded field-by-field with a fallback to the default, so a preset saved
    /// by an older or newer build still loads instead of failing outright.
    /// Presets written before the transform was narrowed to this one method still
    /// load; the fields that no longer exist are simply dropped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AerochromeParams()
        func float(_ key: CodingKeys, _ fallback: Float) -> Float {
            (try? c.decode(Float.self, forKey: key)) ?? fallback
        }
        func int(_ key: CodingKeys, _ fallback: Int) -> Int {
            (try? c.decode(Int.self, forKey: key)) ?? fallback
        }
        sourceIR = int(.sourceIR, d.sourceIR)
        sourceVisibleRed = int(.sourceVisibleRed, d.sourceVisibleRed)
        sourceVisibleGreen = int(.sourceVisibleGreen, d.sourceVisibleGreen)
        gammaBy = float(.gammaBy, d.gammaBy)
        subtractIRRed = float(.subtractIRRed, d.subtractIRRed)
        gammaRx = float(.gammaRx, d.gammaRx)
        gammaGx = float(.gammaGx, d.gammaGx)
        subtractIRGreen = float(.subtractIRGreen, d.subtractIRGreen)
        overallGamma = float(.overallGamma, d.overallGamma)
        outputMapR = int(.outputMapR, d.outputMapR)
        outputMapG = int(.outputMapG, d.outputMapG)
        outputMapB = int(.outputMapB, d.outputMapB)
        monochrome = (try? c.decode(MonochromeSource.self, forKey: .monochrome)) ?? d.monochrome
        adjustments = (try? c.decode(AerochromeAdjustments.self, forKey: .adjustments)) ?? d.adjustments
    }
}

/// Two-phase IRG processor.
///
/// `prepare(cgImage:)` decodes the source once and allocates every working
/// buffer; `process(params:)` can then be called repeatedly at interactive
/// rates. All state is instance-owned scratch space, so **a single instance is
/// not safe to use from more than one thread at a time** — give the live
/// preview and any full-resolution export their own instances.
public final class AerochromeProcessor {
    public init() {}

    private var n = 0
    private var width = 0
    private var height = 0

    /// Size of the prepared image against the original it was downsampled from:
    /// 1 for a full-resolution render, 1200/5184 for a preview of that frame.
    ///
    /// Only the unsharp mask reads it, because only the unsharp mask has a setting
    /// measured in pixels. Every other control is a per-pixel function and so is
    /// scale-free. Set it before `process`; an unknown scale should stay 1, which
    /// makes the preview sharper than the export rather than differently sized.
    public var renderScale: Float = 1

    /// Pixel dimensions currently loaded, or nil if `prepare` has not succeeded.
    public var preparedSize: (width: Int, height: Int)? {
        n > 0 ? (width, height) : nil
    }

    /// `1 - channel` for source red, green and blue, in that order. Cached at
    /// prepare time; `process` picks planes out of this by role, so changing the
    /// role assignment costs nothing.
    private var complements: [[Float]] = []

    private var lastHistogram: Histogram?

    // Pre-allocated working buffers
    private var irStraight: [Float] = []
    private var visRed: [Float] = []
    private var visGreen: [Float] = []
    private var redRaw: [Float] = []
    private var greenCurved: [Float] = []
    private var gammaFill: [Float] = []
    private var sr: [Float] = []
    private var sg: [Float] = []
    private var sb: [Float] = []
    private var tmp: [Float] = []
    private var tmp2: [Float] = []
    private var finalR: [Float] = []
    private var finalG: [Float] = []
    private var finalB: [Float] = []

    /// 8-bit BGRX, for the preview image handed to SwiftUI.
    private static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
        .union(.byteOrder32Little)
        .rawValue

    /// Reused across `prepare` calls; building one per image is wasteful.
    private lazy var ciContext: CIContext = {
        CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                            .cacheIntermediates: false])
    }()

    /// Decode `cgImage` into normalized float planes and size the scratch buffers.
    /// Returns false and leaves the processor unprepared if anything fails.
    @discardableResult
    public func prepare(cgImage: CGImage) -> Bool {
        // Reset first so a partial failure can never leave stale geometry
        // paired with wrongly-sized buffers.
        n = 0

        let w = cgImage.width
        let h = cgImage.height
        let count = w * h
        guard count > 0 else { return false }

        // Decoded at 16 bits, via CoreImage rather than a CGContext: drawing into a
        // 16-bit `CGContext` silently produces all zeros on this platform, which
        // was measured. `CIContext.render(toBitmap:format: .RGBA16)` is exact —
        // an 8-bit input of 200 comes back as 51400, i.e. 200 * 65535 / 255.
        //
        // Bit depth matters here rather than being box-ticking: the transform
        // lifts shadows hard, since the infrared group's curve is typically around
        // 2.2 and `v ^ (1/2.2)` stretches the bottom of the range by roughly five
        // times. An 8-bit decode puts banding in exactly the areas the look
        // depends on, and would cap a 16-bit export at 8 bits of real information
        // no matter what the file claimed.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        let words = 4 * count
        var interleaved = [UInt16](repeating: 0, count: words)
        let rowBytes = w * 8
        interleaved.withUnsafeMutableBytes { raw in
            ciContext.render(CIImage(cgImage: cgImage), toBitmap: raw.baseAddress!,
                             rowBytes: rowBytes,
                             bounds: CGRect(x: 0, y: 0, width: w, height: h),
                             format: .RGBA16, colorSpace: colorSpace)
        }

        let rowLen = vDSP_Length(w)
        let nLen = vDSP_Length(count)
        var negInvMax: Float = -1.0 / 65535.0
        var one: Float = 1
        var zero: Float = 0

        complements = []
        for wordOffset in [0, 1, 2] {
            var plane = [Float](repeating: 0, count: count)
            interleaved.withUnsafeBufferPointer { src in
            plane.withUnsafeMutableBufferPointer { p in
                for y in 0..<h {
                    vDSP_vfltu16(src.baseAddress! + y * w * 4 + wordOffset, 4,
                                 p.baseAddress! + y * w, 1, rowLen)
                }
                // Only 1 - x is ever needed downstream, so fold the /65535
                // normalization and the complement into one pass.
                vDSP_vsmsa(p.baseAddress!, 1, &negInvMax, &one, p.baseAddress!, 1, nLen)
                // vsmsa fuses the multiply-add, so a full-scale sample rounds to
                // a tiny *negative* complement instead of exactly zero.
                // `pow(negative, 2.2)` is NaN, which then survives clipping and
                // lands as garbage bytes in the output, so pin the range here.
                vDSP_vclip(p.baseAddress!, 1, &zero, &one, p.baseAddress!, 1, nLen)
            }
            }
            complements.append(plane)
        }

        let scratch = { [Float](repeating: 0, count: count) }
        irStraight = scratch(); visRed = scratch(); visGreen = scratch()
        redRaw = scratch(); greenCurved = scratch()
        gammaFill = scratch()
        sr = scratch(); sg = scratch(); sb = scratch()
        tmp = scratch(); tmp2 = scratch()
        finalR = scratch(); finalG = scratch(); finalB = scratch()

        width = w
        height = h
        n = count
        return true
    }

    public func process(params p: AerochromeParams) -> CGImage? {
        render(params: p, collectHistogram: false)?.image
    }

    /// Same render, plus the distribution of the result and any viewing aids.
    /// Used for the live preview; the export path skips both, so it neither pays
    /// for the extra pass nor risks baking a diagnostic overlay into a file.
    public func processWithHistogram(params p: AerochromeParams,
                                     aids: ViewingAids = ViewingAids())
        -> (image: CGImage, histogram: Histogram)?
    {
        guard let out = render(params: p, aids: aids, collectHistogram: true),
              let histogram = out.histogram
        else { return nil }
        return (out.image, histogram)
    }

    private func render(params p: AerochromeParams,
                        aids: ViewingAids = ViewingAids(),
                        collectHistogram: Bool)
        -> (image: CGImage, histogram: Histogram?)?
    {
        guard n > 0 else { return nil }
        let nLen = vDSP_Length(n)
        var count32 = Int32(n)

        build(p, count: &count32, nLen: nLen)

        // Channel mapping + the final curves layer. A soloed signal, or a
        // single-signal monochrome mode, replaces the map on all three outputs.
        var og: Float = 1.0 / max(p.overallGamma, 0.0001)
        vDSP_vfill(&og, &gammaFill, 1, nLen)
        let override = aids.solo.signalIndex ?? p.monochrome.signalIndex
        applyGamma(from: override ?? p.outputMapR, into: &finalR, count: &count32)
        applyGamma(from: override ?? p.outputMapG, into: &finalG, count: &count32)
        applyGamma(from: override ?? p.outputMapB, into: &finalB, count: &count32)

        // Luminance monochrome has to come after the map, since the map is what
        // decides which signal contributes how much light.
        if p.monochrome == .luminance, aids.solo == .off {
            flattenToLuminance(nLen: nLen)
        }

        // Soloing shows one signal as it came out of the transform, so the photo
        // edits are bypassed rather than layered on top of the diagnostic.
        let adjustments = aids.solo == .off ? p.adjustments : AerochromeAdjustments()
        applyAdjustments(adjustments, nLen: nLen)

        guard let image = makeImage(adjustments: adjustments,
                                    aids: aids,
                                    collectHistogram: collectHistogram,
                                    nLen: nLen)
        else { return nil }
        return (image, lastHistogram)
    }

    /// One-shot convenience. Re-prepares, so do not call this on an instance
    /// that is driving a live preview.
    public func process(cgImage: CGImage, params: AerochromeParams) -> CGImage? {
        guard prepare(cgImage: cgImage) else { return nil }
        return process(params: params)
    }

    // MARK: - Transform

    /// The Photoshop layer stack, in the document's order:
    ///
    ///     irSignal = ir ^ (1 / gammaBy)                                       // blue group curves
    ///     redSig   = max(visRed - subIRRed * irSignal, 0) ^ (1 / gammaRx)     // Subtract, then curves
    ///     greenSig = max(visGreen ^ (1 / gammaGx) - subIRGreen * irSignal, 0) // curves, then Subtract
    ///
    /// The curve order is the part that matters and is easy to get wrong: red's
    /// curves adjustment sits *above* its Subtract layer, green's *below*.
    private func build(_ p: AerochromeParams, count: inout Int32, nLen: vDSP_Length) {
        var negOne: Float = -1
        var one: Float = 1
        var zero: Float = 0

        // The cached planes hold 1 - channel; this workflow wants the channels.
        vDSP_vsmsa(plane(p.sourceIR), 1, &negOne, &one, &irStraight, 1, nLen)
        vDSP_vsmsa(plane(p.sourceVisibleRed), 1, &negOne, &one, &visRed, 1, nLen)
        vDSP_vsmsa(plane(p.sourceVisibleGreen), 1, &negOne, &one, &visGreen, 1, nLen)

        power(base: irStraight, exponent: 1 / max(p.gammaBy, 0.0001),
              into: &sb, count: &count, nLen: nLen)

        // Red: Subtract layer first, then the curve above it.
        var subR = p.subtractIRRed
        vDSP_vsmul(sb, 1, &subR, &tmp, 1, nLen)
        vDSP_vsub(tmp, 1, visRed, 1, &tmp2, 1, nLen)
        vDSP_vthr(tmp2, 1, &zero, &redRaw, 1, nLen)
        power(base: redRaw, exponent: 1 / max(p.gammaRx, 0.0001),
              into: &sr, count: &count, nLen: nLen)

        // Green: the curve sits below the Subtract layer, so it goes first.
        power(base: visGreen, exponent: 1 / max(p.gammaGx, 0.0001),
              into: &greenCurved, count: &count, nLen: nLen)
        var subG = p.subtractIRGreen
        vDSP_vsmul(sb, 1, &subG, &tmp, 1, nLen)
        vDSP_vsub(tmp, 1, greenCurved, 1, &tmp2, 1, nLen)
        vDSP_vthr(tmp2, 1, &zero, &sg, 1, nLen)
    }

    private func flattenToLuminance(nLen: vDSP_Length) {
        var wr: Float = 0.2126, wg: Float = 0.7152, wb: Float = 0.0722
        vDSP_vsmul(finalR, 1, &wr, &tmp, 1, nLen)
        vDSP_vsma(finalG, 1, &wg, tmp, 1, &tmp2, 1, nLen)
        vDSP_vsma(finalB, 1, &wb, tmp2, 1, &tmp, 1, nLen)
        var unity: Float = 1
        vDSP_vsmul(tmp, 1, &unity, &finalR, 1, nLen)
        vDSP_vsmul(tmp, 1, &unity, &finalG, 1, nLen)
        vDSP_vsmul(tmp, 1, &unity, &finalB, 1, nLen)
    }

    // MARK: - Output

    /// Clip to range, scale to 0…255 and apply the tone curves. Leaves the result
    /// in `finalR`/`finalG`/`finalB` as floats, so both the 8-bit preview and the
    /// 16-bit export paths can take it from here without recomputing anything.
    private func finishPlanes(adjustments: AerochromeAdjustments, nLen: vDSP_Length) {
        var zero: Float = 0
        var one: Float = 1
        var scale255: Float = 255

        vDSP_vclip(finalR, 1, &zero, &one, &tmp, 1, nLen)
        vDSP_vsmul(tmp, 1, &scale255, &finalR, 1, nLen)
        vDSP_vclip(finalG, 1, &zero, &one, &tmp, 1, nLen)
        vDSP_vsmul(tmp, 1, &scale255, &finalG, 1, nLen)
        vDSP_vclip(finalB, 1, &zero, &one, &tmp, 1, nLen)
        vDSP_vsmul(tmp, 1, &scale255, &finalB, 1, nLen)

        applyCurves(adjustments.curves, nLen: nLen)
        sharpen(adjustments.sharpening, nLen: nLen)
    }

    private func makeImage(adjustments: AerochromeAdjustments,
                           aids: ViewingAids,
                           collectHistogram: Bool,
                           nLen: vDSP_Length) -> CGImage? {
        finishPlanes(adjustments: adjustments, nLen: nLen)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let dstCtx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: Self.bitmapInfo
              ),
              let dstData = dstCtx.data
        else { return nil }

        let dst = dstData.assumingMemoryBound(to: UInt8.self)
        let dstStride = dstCtx.bytesPerRow
        let rowLen = vDSP_Length(width)
        finalR.withUnsafeBufferPointer { fr in
            finalG.withUnsafeBufferPointer { fg in
                finalB.withUnsafeBufferPointer { fb in
                    for y in 0..<height {
                        let row = dst + y * dstStride
                        let off = y * width
                        vDSP_vfixru8(fb.baseAddress! + off, 1, row + 0, 4, rowLen)
                        vDSP_vfixru8(fg.baseAddress! + off, 1, row + 1, 4, rowLen)
                        vDSP_vfixru8(fr.baseAddress! + off, 1, row + 2, 4, rowLen)
                    }
                }
            }
        }

        // Histogram before the overlay, so the marker colours are not counted as
        // if they were image data.
        lastHistogram = collectHistogram ? buildHistogram(dst: dst, stride: dstStride) : nil
        if aids.showClipping { markClipping(dst: dst, stride: dstStride) }
        return dstCtx.makeImage()
    }

    /// Paint pixels whose darkest channel has been crushed to zero, or whose
    /// brightest has been pushed to full. Blown wins where both apply, since a
    /// blown highlight is the less recoverable of the two.
    private func markClipping(dst: UnsafeMutablePointer<UInt8>, stride: Int) {
        let crushed = ViewingAids.crushedMarker
        let blown = ViewingAids.blownMarker
        for y in 0..<height {
            let row = dst + y * stride
            for x in 0..<width {
                let o = x * 4
                let b = row[o + 0], g = row[o + 1], r = row[o + 2]
                let marker: (r: UInt8, g: UInt8, b: UInt8)?
                if r == 255 || g == 255 || b == 255 {
                    marker = blown
                } else if r == 0 || g == 0 || b == 0 {
                    marker = crushed
                } else {
                    marker = nil
                }
                if let marker {
                    row[o + 0] = marker.b
                    row[o + 1] = marker.g
                    row[o + 2] = marker.r
                }
            }
        }
    }

    private func buildHistogram(dst: UnsafeMutablePointer<UInt8>, stride: Int) -> Histogram {
        let bins = Histogram.binCount
        var red = [Int](repeating: 0, count: bins)
        var green = [Int](repeating: 0, count: bins)
        var blue = [Int](repeating: 0, count: bins)
        var luma = [Int](repeating: 0, count: bins)

        for y in 0..<height {
            let row = dst + y * stride
            for x in 0..<width {
                let o = x * 4
                let b = Int(row[o + 0])
                let g = Int(row[o + 1])
                let r = Int(row[o + 2])
                red[r] += 1
                green[g] += 1
                blue[b] += 1
                // Integer Rec. 709 weights, /10000.
                luma[min((2126 * r + 7152 * g + 722 * b) / 10_000, bins - 1)] += 1
            }
        }
        return Histogram(red: red, green: green, blue: blue, luma: luma,
                         pixelCount: width * height)
    }

    // MARK: - Adjustments

    /// Ordinary photo edits, in one fused pass over the three output planes.
    ///
    /// Deliberately a scalar loop rather than fifteen `vDSP` passes: saturation
    /// and vibrance need all three channels of a pixel at once, the tonal masks
    /// are cheap polynomials, and a single pass touches each pixel's memory once
    /// instead of fifteen times. It is skipped entirely when nothing is set.
    private func applyAdjustments(_ a: AerochromeAdjustments, nLen: vDSP_Length) {
        guard !a.isToneIdentity else { return }

        let exposureGain = powf(2, a.exposure)
        // Endpoint remap: positive opens the range, negative compresses it.
        let lo = -a.blacks * 0.2
        let hi = 1 - a.whites * 0.2
        let invSpan = 1 / max(hi - lo, 0.05)
        let contrastGain = 1 + a.contrast
        // Coefficient magnitude is capped at 1 so the lifts can never take a
        // value *past* an endpoint. Combined, the two terms need
        // `k1*c*(1-c) + k2*c^2 <= 1`, which at k1 = k2 = 1 reduces to `c <= 1`
        // and so holds exactly. Note the bound is tight rather than slack: a
        // value close to the top does get taken all the way to it, which is what
        // a highlight lift is supposed to do. The cost of the cap is a maximum
        // shift of 4/27 ≈ 0.15 rather than something showier — stack exposure or
        // a curve on top if more is wanted.
        let shadowAmount = min(max(a.shadows, -1), 1)
        let highlightAmount = min(max(a.highlights, -1), 1)
        let warmR = 1 + a.warmth * 0.2
        let warmB = 1 - a.warmth * 0.2
        let tintG = 1 - a.tint * 0.2
        let tintRB = 1 + a.tint * 0.1
        let saturation = 1 + a.saturation
        let vibrance = a.vibrance

        @inline(__always) func tone(_ input: Float) -> Float {
            var v = (input * exposureGain - lo) * invSpan
            if shadowAmount != 0 || highlightAmount != 0 {
                let c = min(max(v, 0), 1)
                let oneMinus = 1 - c
                v += shadowAmount * c * oneMinus * oneMinus
                v += highlightAmount * c * c * oneMinus
            }
            return (v - 0.5) * contrastGain + 0.5
        }

        let count = Int(nLen)
        finalR.withUnsafeMutableBufferPointer { rp in
            finalG.withUnsafeMutableBufferPointer { gp in
                finalB.withUnsafeMutableBufferPointer { bp in
                    for i in 0..<count {
                        var r = tone(rp[i]) * warmR * tintRB
                        var g = tone(gp[i]) * tintG
                        var b = tone(bp[i]) * warmB * tintRB

                        if saturation != 1 || vibrance != 0 {
                            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                            var factor = saturation
                            if vibrance != 0 {
                                let chroma = max(r, max(g, b)) - min(r, min(g, b))
                                factor *= 1 + vibrance * (1 - min(max(chroma, 0), 1))
                            }
                            r = luma + (r - luma) * factor
                            g = luma + (g - luma) * factor
                            b = luma + (b - luma) * factor
                        }

                        rp[i] = r
                        gp[i] = g
                        bp[i] = b
                    }
                }
            }
        }
    }

    /// Apply the composed tone curves by interpolated table lookup. Inputs are
    /// already scaled to 0…255, so a 256-entry table is a natural fit.
    private func applyCurves(_ curves: ToneCurves, nLen: vDSP_Length) {
        guard !curves.isIdentity else { return }
        let tables = curves.composedTables(size: Histogram.binCount)
        var scale: Float = 1
        var offset: Float = 0
        let entries = vDSP_Length(Histogram.binCount)

        for (index, table) in tables.enumerated() {
            table.withUnsafeBufferPointer { lut in
                let apply: (UnsafeMutablePointer<Float>) -> Void = { plane in
                    vDSP_vtabi(plane, 1, &scale, &offset, lut.baseAddress!, entries,
                               plane, 1, nLen)
                }
                switch index {
                case 0: finalR.withUnsafeMutableBufferPointer { apply($0.baseAddress!) }
                case 1: finalG.withUnsafeMutableBufferPointer { apply($0.baseAddress!) }
                default: finalB.withUnsafeMutableBufferPointer { apply($0.baseAddress!) }
                }
            }
        }
    }

    // MARK: - Sharpening

    /// Unsharp mask on the luminance of the finished planes.
    ///
    /// Luminance rather than each channel separately: one blur instead of three,
    /// and adding a grey detail signal to all three channels raises edge contrast
    /// without moving hue. Per-channel sharpening does move it, which on the
    /// near-saturated reds this look produces shows up as coloured fringing.
    ///
    /// Planes are 0…255 here, and the result is clipped back into that range —
    /// overshoot is what sharpening *is*, and `vDSP_vfixru8` downstream does not
    /// saturate.
    private func sharpen(_ s: Sharpening, nLen: vDSP_Length) {
        guard !s.isIdentity, n > 0 else { return }

        // The radius is in full-resolution pixels, so a preview needs it scaled to
        // the pixels it actually has. Below the floor there is no detail layer left
        // to add back; see `Sharpening.minimumVisibleRadius`.
        let radius = s.radius * max(renderScale, 0)
        guard radius >= Sharpening.minimumVisibleRadius else { return }

        // Luminance into `tmp`, blurred via `tmp2`, landing in `sr`. All three are
        // free by now: the transform's signal planes were consumed by `applyGamma`,
        // and `finishPlanes` has finished with its scratch. Two buffers for the
        // blur because vImage will not convolve in place.
        var wr: Float = 0.2126, wg: Float = 0.7152, wb: Float = 0.0722
        vDSP_vsmul(finalR, 1, &wr, &tmp, 1, nLen)
        vDSP_vsma(finalG, 1, &wg, tmp, 1, &tmp2, 1, nLen)
        vDSP_vsma(finalB, 1, &wb, tmp2, 1, &tmp, 1, nLen)

        guard blur(radius: radius) else { return }

        let amount = s.amount
        let thresholdSquared = max(s.threshold, 0) * max(s.threshold, 0)
        let count = n
        tmp.withUnsafeBufferPointer { luma in
        sr.withUnsafeBufferPointer { blurred in
        finalR.withUnsafeMutableBufferPointer { rp in
        finalG.withUnsafeMutableBufferPointer { gp in
        finalB.withUnsafeMutableBufferPointer { bp in
            for i in 0..<count {
                var detail = luma[i] - blurred[i]
                if thresholdSquared > 0 {
                    let squared = detail * detail
                    detail *= squared / (squared + thresholdSquared)
                }
                let add = amount * detail
                rp[i] = min(max(rp[i] + add, 0), 255)
                gp[i] = min(max(gp[i] + add, 0), 255)
                bp[i] = min(max(bp[i] + add, 0), 255)
            }
        }
        }
        }
        }
        }
    }

    /// Gaussian blur `tmp` into `sr`, using `tmp2` between the two passes.
    ///
    /// Separable: a 1×k pass then a k×1 pass, which is 2k multiplies per pixel
    /// instead of k². At radius 1 that is 14 against 49.
    private func blur(radius: Float) -> Bool {
        let kernel = Self.gaussianKernel(radius: radius)
        let taps = UInt32(kernel.count)
        let flags = vImage_Flags(kvImageEdgeExtend)
        var ok = false

        tmp.withUnsafeMutableBufferPointer { source in
        tmp2.withUnsafeMutableBufferPointer { middle in
        sr.withUnsafeMutableBufferPointer { destination in
            func buffer(_ p: UnsafeMutableBufferPointer<Float>) -> vImage_Buffer {
                vImage_Buffer(data: p.baseAddress,
                              height: vImagePixelCount(height),
                              width: vImagePixelCount(width),
                              rowBytes: width * MemoryLayout<Float>.size)
            }
            var src = buffer(source)
            var mid = buffer(middle)
            var dst = buffer(destination)

            let horizontal = vImageConvolve_PlanarF(&src, &mid, nil, 0, 0, kernel,
                                                    1, taps, 0, flags)
            let vertical = vImageConvolve_PlanarF(&mid, &dst, nil, 0, 0, kernel,
                                                  taps, 1, 0, flags)
            ok = horizontal == kvImageNoError && vertical == kvImageNoError
        }
        }
        }
        return ok
    }

    /// Normalized 1-D Gaussian, an odd number of taps.
    ///
    /// Cut off at three sigma, where the tail is under 1% of the peak, and capped
    /// so a large radius cannot turn into an unbounded kernel.
    static func gaussianKernel(radius: Float) -> [Float] {
        let sigma = max(radius, 0.05)
        let reach = min(max(Int((sigma * 3).rounded(.up)), 1), 32)
        var kernel = (-reach...reach).map { offset -> Float in
            let x = Float(offset) / sigma
            return expf(-0.5 * x * x)
        }
        let sum = kernel.reduce(0, +)
        if sum > 0 {
            for i in kernel.indices { kernel[i] /= sum }
        }
        return kernel
    }

    // MARK: - Helpers

    private func plane(_ role: Int) -> [Float] {
        complements[min(max(role, 0), 2)]
    }

    /// `vvpowf(z, y, x, n)` computes `z = x ^ y` — the *second* argument is the
    /// exponent and the third is the base. Passing them in the intuitive
    /// (base, exponent) order silently computes `gamma ^ signal`, which pins
    /// every output near 1.0 and blows the image out to white.
    private func power(base: [Float], exponent: Float, into out: inout [Float],
                       count: inout Int32, nLen: vDSP_Length) {
        var e = exponent
        vDSP_vfill(&e, &gammaFill, 1, nLen)
        vvpowf(&out, gammaFill, base, &count)
    }

    /// `gammaFill` must already hold `1 / overallGamma`. Exponent second, base
    /// third — see `power(base:exponent:into:count:nLen:)`.
    private func applyGamma(from map: Int, into out: inout [Float], count: inout Int32) {
        switch map {
        case 0: vvpowf(&out, gammaFill, sr, &count)
        case 1: vvpowf(&out, gammaFill, sg, &count)
        default: vvpowf(&out, gammaFill, sb, &count)
        }
    }

    // MARK: - 16-bit export

    /// Render at 16 bits per channel.
    ///
    /// The transform runs in `Float` throughout, so this is a real 16-bit result
    /// rather than 8-bit data widened — provided the source had the depth, which
    /// is why `prepare` decodes at 16 bits and why the load path keeps 16 bits
    /// through development, orientation and downscaling.
    public func render16(params p: AerochromeParams) -> RenderedImage16? {
        guard n > 0 else { return nil }
        let nLen = vDSP_Length(n)
        var count32 = Int32(n)

        build(p, count: &count32, nLen: nLen)

        var og: Float = 1.0 / max(p.overallGamma, 0.0001)
        vDSP_vfill(&og, &gammaFill, 1, nLen)
        let override = p.monochrome.signalIndex
        applyGamma(from: override ?? p.outputMapR, into: &finalR, count: &count32)
        applyGamma(from: override ?? p.outputMapG, into: &finalG, count: &count32)
        applyGamma(from: override ?? p.outputMapB, into: &finalB, count: &count32)
        if p.monochrome == .luminance { flattenToLuminance(nLen: nLen) }

        applyAdjustments(p.adjustments, nLen: nLen)
        finishPlanes(adjustments: p.adjustments, nLen: nLen)

        // Planes are 0…255 floats here. Scale to the 16-bit range, optionally
        // taking them back to linear light first.
        var pixels = [UInt16](repeating: 0, count: n * 3)
        let pixelCount = n
        pixels.withUnsafeMutableBufferPointer { out in
            finalR.withUnsafeBufferPointer { r in
                finalG.withUnsafeBufferPointer { g in
                    finalB.withUnsafeBufferPointer { b in
                        let planes = [r, g, b]
                        for channel in 0..<3 {
                            let plane = planes[channel]
                            for i in 0..<pixelCount {
                                let v = min(max(plane[i] / 255, 0), 1)
                                out[i * 3 + channel] = UInt16((v * 65535).rounded())
                            }
                        }
                    }
                }
            }
        }
        return RenderedImage16(pixels: pixels, width: width, height: height)
    }
}

/// A finished render at 16 bits per channel, interleaved RGB.
public struct RenderedImage16 {
    public var pixels: [UInt16]
    public var width: Int
    public var height: Int

    /// Public so a caller can hand `ImageIOSupport.write` a buffer it built itself —
    /// which is how the format checks compare a known ramp against what came back.
    public init(pixels: [UInt16], width: Int, height: Int) {
        self.pixels = pixels
        self.width = width
        self.height = height
    }
}
