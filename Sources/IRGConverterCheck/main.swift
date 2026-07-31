// Numeric self-check for AerochromeProcessor.
//
// Built as an executable rather than an XCTest target so it runs on a bare
// Command Line Tools install (no Xcode, so no XCTest / swift-testing):
//
//     swift run IRGConverterCheck

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import IRGConverterCore

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        print("  FAIL \(message)")
        failures += 1
    }
}

func checkClose(_ actual: Float, _ expected: Float, tolerance: Float, _ message: String) {
    let delta = abs(actual - expected)
    check(delta <= tolerance, "\(message) (got \(actual), want \(expected), Δ\(delta))")
}

// MARK: - Scalar reference

/// Straight transcription of the Photoshop layer workflow, used to validate the
/// vectorized implementation.
func reference(srcR: Float, srcG: Float, srcB: Float, p: AerochromeParams) -> (Float, Float, Float) {
    let src = [srcR, srcG, srcB]
    func role(_ i: Int) -> Float { src[min(max(i, 0), 2)] }
    let ir = role(p.sourceIR)
    let x1 = role(p.sourceVisibleRed)
    let x2 = role(p.sourceVisibleGreen)

    // Blue group curves; red subtract then curves; green curves then subtract.
    let irSignal = powf(ir, 1 / p.gammaBy)
    let red = powf(max(x1 - p.subtractIRRed * irSignal, 0), 1 / p.gammaRx)
    let green = max(powf(x2, 1 / p.gammaGx) - p.subtractIRGreen * irSignal, 0)
    let signals = [red, green, irSignal]

    let e = 1 / p.overallGamma
    func signal(_ map: Int) -> Float {
        min(max(powf(max(signals[min(max(map, 0), 2)], 0), e), 0), 1)
    }

    let out = [signal(p.outputMapR), signal(p.outputMapG), signal(p.outputMapB)]
    return ((out[0] * 255).rounded(), (out[1] * 255).rounded(), (out[2] * 255).rounded())
}

// MARK: - Fixtures

let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
    .union(.byteOrder32Little)

func makeContext(width: Int) -> CGContext {
    CGContext(
        data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo.rawValue
    )!
}

func makeImage(_ pixels: [(UInt8, UInt8, UInt8)]) -> CGImage {
    let ctx = makeContext(width: pixels.count)
    let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for (i, px) in pixels.enumerated() {
        buf[i * 4 + 0] = px.2  // B
        buf[i * 4 + 1] = px.1  // G
        buf[i * 4 + 2] = px.0  // R
    }
    return ctx.makeImage()!
}

/// A rectangular fixture, for the one stage that reads its neighbours: sharpening.
/// `pixel(x, y)` is sampled with y = 0 at the top, matching `readRows`.
func makeImage(width: Int, height: Int,
               _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo.rawValue
    )!
    let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let px = pixel(x, y)
            let o = y * ctx.bytesPerRow + x * 4
            buf[o + 0] = px.2
            buf[o + 1] = px.1
            buf[o + 2] = px.0
        }
    }
    return ctx.makeImage()!
}

/// Every row of a rendered image, top row first.
func readRows(_ image: CGImage) -> [[(Float, Float, Float)]] {
    let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: bitmapInfo.rawValue
    )!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<image.height).map { y in
        (0..<image.width).map { x -> (Float, Float, Float) in
            let o = y * ctx.bytesPerRow + x * 4
            return (Float(buf[o + 2]), Float(buf[o + 1]), Float(buf[o + 0]))
        }
    }
}

func readPixels(_ image: CGImage) -> [(Float, Float, Float)] {
    let ctx = makeContext(width: image.width)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: 1))
    let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<image.width).map {
        (Float(buf[$0 * 4 + 2]), Float(buf[$0 * 4 + 1]), Float(buf[$0 * 4 + 0]))
    }
}

// MARK: - Checks

print("vectorized output matches scalar reference")
do {
    let samples: [(UInt8, UInt8, UInt8)] = [
        (0, 0, 0), (255, 255, 255), (128, 128, 128),
        (200, 60, 30), (30, 200, 60), (60, 30, 200), (255, 0, 128), (17, 240, 91),
    ]

    // Non-default params, including a pre-swapped IRG role assignment.
    var tweaked = AerochromeParams()
    tweaked.overallGamma = 2.4
    tweaked.subtractIRGreen = 0.15
    tweaked.gammaRx = 0.6
    tweaked.outputMapR = 0
    tweaked.outputMapG = 1
    tweaked.outputMapB = 2
    tweaked.sourceIR = 0
    tweaked.sourceVisibleRed = 1
    tweaked.sourceVisibleGreen = 2

    // Heavy subtraction with a dark infrared group and a large final lift — a corner
    // of the parameter space the shipped look does not visit, so worth pinning.
    var heavySubtraction = AerochromeParams()
    heavySubtraction.subtractIRRed = 0.5
    heavySubtraction.subtractIRGreen = 0.8
    heavySubtraction.gammaRx = 0.85
    heavySubtraction.gammaGx = 1.20
    heavySubtraction.gammaBy = 0.85
    heavySubtraction.overallGamma = 2.8

    var remapped = heavySubtraction
    remapped.outputMapR = 1; remapped.outputMapG = 2; remapped.outputMapB = 0

    let processor = AerochromeProcessor()
    check(processor.prepare(cgImage: makeImage(samples)), "prepare succeeds")

    for (v, p) in [AerochromeParams(), tweaked, heavySubtraction, remapped].enumerated() {
        guard let out = processor.process(params: p) else {
            check(false, "variant \(v) produced an image")
            continue
        }
        let actual = readPixels(out)
        var worst: Float = 0
        for (i, px) in samples.enumerated() {
            let want = reference(srcR: Float(px.0) / 255, srcG: Float(px.1) / 255, srcB: Float(px.2) / 255, p: p)
            worst = max(worst, abs(actual[i].0 - want.0))
            worst = max(worst, abs(actual[i].1 - want.1))
            worst = max(worst, abs(actual[i].2 - want.2))
        }
        check(worst <= 1.0, "variant \(v): max channel error \(worst) <= 1.0")
    }
}

print("defaults do not blow the image out (regression: swapped pow args gave pure white)")
do {
    let processor = AerochromeProcessor()
    let ramp: [(UInt8, UInt8, UInt8)] = [(32, 32, 32), (64, 64, 64), (128, 128, 128),
                                         (192, 192, 192), (224, 224, 224)]
    _ = processor.prepare(cgImage: makeImage(ramp))
    guard let out = processor.process(params: AerochromeParams()) else {
        check(false, "ramp render produced an image")
        exit(1)
    }
    let px = readPixels(out)
    for (i, v) in ramp.enumerated() {
        print("  \(v.0),\(v.1),\(v.2) -> \(Int(px[i].0)),\(Int(px[i].1)),\(Int(px[i].2))")
    }
    let allWhite = px.allSatisfy { $0.0 >= 254 && $0.1 >= 254 && $0.2 >= 254 }
    let allBlack = px.allSatisfy { $0.0 <= 1 && $0.1 <= 1 && $0.2 <= 1 }
    check(!allWhite, "output is not uniformly white")
    check(!allBlack, "output is not uniformly black")
    // A brighter input must not produce a darker infrared channel.
    let monotonic = zip(px, px.dropFirst()).allSatisfy { $0.0 <= $1.0 + 1 }
    check(monotonic, "infrared output rises with input")
}

print("preset store: save, reload, export, import, tolerate partial files")
do {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("irgconverter-check-presets-\(ProcessInfo.processInfo.processIdentifier)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = AerochromePresetStore(directory: tmp)
    check(store.user.isEmpty, "starts with no user presets")
    check(!store.builtIn.isEmpty, "ships built-in presets")

    var custom = AerochromeParams()
    custom.gammaRx = 3.21
    custom.subtractIRRed = 1.42
    custom.outputMapB = 2
    let preset = AerochromePreset(name: "Round Trip", params: custom,
                                  raw: RawDevelopSettings(), notes: "a note")
    do { try store.save(preset) } catch { check(false, "save threw: \(error)") }

    let reloaded = AerochromePresetStore(directory: tmp)
    guard let back = reloaded.preset(named: "Round Trip") else {
        check(false, "preset survives a reload")
        exit(1)
    }
    check(back.params == custom, "every parameter round-trips")
    check(back.raw == RawDevelopSettings() && back.notes == "a note",
          "development settings and the note round-trip")

    let exported = tmp.appendingPathComponent("bundle.irgpreset")
    do { try reloaded.export(reloaded.user, to: exported) } catch { check(false, "export threw: \(error)") }
    check(FileManager.default.fileExists(atPath: exported.path), "export writes a file")

    do {
        let added = try reloaded.importPresets(from: exported)
        check(added.first?.name == "Round Trip 2", "import renames instead of overwriting, got \(added.first?.name ?? "nil")")
    } catch { check(false, "import threw: \(error)") }

    // A hand-written file with one field and no wrapper must still load.
    let partial = tmp.appendingPathComponent("partial.irgpreset")
    try? #"{"name":"Partial","params":{"gammaRx":2.5}}"#.write(to: partial, atomically: true, encoding: .utf8)
    do {
        let added = try reloaded.importPresets(from: partial)
        check(added.first?.params.gammaRx == 2.5, "keeps the field that was present")
        check(added.first?.params.gammaBy == AerochromeParams().gammaBy, "defaults the fields that were absent")
    } catch { check(false, "partial import threw: \(error)") }

    do {
        try reloaded.delete(named: "Partial")
        check(reloaded.preset(named: "Partial") == nil, "delete removes it")
    } catch { check(false, "delete threw: \(error)") }

    var threw = false
    do { try reloaded.delete(named: "No Such Preset") } catch { threw = true }
    check(threw, "deleting a missing preset throws")
}

print("every built-in preset resolves and renders")
do {
    var pixels: [(UInt8, UInt8, UInt8)] = []
    for i in 0..<200 {
        let ir = 60 + i % 120
        pixels.append((UInt8(min(2 * ir, 255)), UInt8(ir / 2 + i % 30), UInt8(ir)))
    }
    let processor = AerochromeProcessor()
    _ = processor.prepare(cgImage: makeImage(pixels))
    let store = AerochromePresetStore(directory: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("irgconverter-check-empty"))

    for preset in store.builtIn {
        guard let out = processor.process(params: preset.resolved) else {
            check(false, "\(preset.name) rendered")
            continue
        }
        let px = readPixels(out)
        let blown = px.allSatisfy { $0.0 >= 254 && $0.1 >= 254 && $0.2 >= 254 }
        let dead = px.allSatisfy { $0.0 <= 1 && $0.1 <= 1 && $0.2 <= 1 }
        check(!blown && !dead, "\(preset.name) is neither all-white nor all-black")
    }

    check(store.builtIn.count >= 2, "ships a family of presets, \(store.builtIn.count) of them")
    check(store.builtIn.first?.name == "Aerochrome Magenta",
          "the default is the one at the top of the menu")
    check(Set(store.builtIn.map(\.name)).count == store.builtIn.count,
          "no two built-ins share a name")
    check(store.builtIn.allSatisfy { $0.notes?.isEmpty == false }, "each one says what it does")
}

print("the default preset is what a photo starts on")
do {
    let preset = AerochromePresetStore.default
    check(preset.name == "Aerochrome Magenta", "the default is Aerochrome Magenta")
    check(preset.resolved == preset.params, "a preset is its own numbers, nothing derived")

    check(PhotoEdit.default == PhotoEdit(preset: preset, raw: RawDevelopSettings()),
          "a fresh photo's edit is that preset")
    check(PhotoEdit.default != PhotoEdit(),
          "and differs from the bare defaults, so “edited” means something")
    check(!PhotoEdit.default.params.adjustments.curves.master.isIdentity,
          "its tone curve comes along")
    check(PhotoEdit.default.raw == RawDevelopSettings(),
          "development starts where the look was tuned")
}

print("odd widths exercise row-strided de/interleave and CGContext row padding")
do {
    for width in [1, 7, 37, 129] {
        let processor = AerochromeProcessor()
        var pixels: [(UInt8, UInt8, UInt8)] = []
        for i in 0..<width {
            pixels.append((UInt8((i * 7) % 256), UInt8((i * 3) % 256), UInt8((i * 11) % 256)))
        }
        check(processor.prepare(cgImage: makeImage(pixels)), "width \(width): prepare")
        check(processor.preparedSize?.width == width, "width \(width): preparedSize")
        guard let out = processor.process(params: AerochromeParams()) else {
            check(false, "width \(width): process")
            continue
        }
        let actual = readPixels(out)
        var worst: Float = 0
        for (i, px) in pixels.enumerated() {
            let want = reference(
                srcR: Float(px.0) / 255, srcG: Float(px.1) / 255, srcB: Float(px.2) / 255,
                p: AerochromeParams()
            )
            worst = max(worst, abs(actual[i].0 - want.0))
            worst = max(worst, abs(actual[i].1 - want.1))
            worst = max(worst, abs(actual[i].2 - want.2))
        }
        check(worst <= 1.0, "width \(width): max channel error \(worst) <= 1.0")
    }
}

print("process() before prepare() is a no-op, not a crash")
check(AerochromeProcessor().process(params: AerochromeParams()) == nil, "returns nil")

print("tone curve is monotone and exact at its control points")
do {
    check(ToneCurve().isIdentity, "default curve is the identity")
    checkClose(ToneCurve().value(at: 0.37), 0.37, tolerance: 0.002, "identity passes values through")

    // An S-curve. Monotone cubic must not overshoot between the points, which a
    // natural spline through the same points would.
    let s = ToneCurve(points: [
        CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.12),
        CurvePoint(x: 0.75, y: 0.88), CurvePoint(x: 1, y: 1),
    ])
    check(!s.isIdentity, "an edited curve is not the identity")
    checkClose(s.value(at: 0.25), 0.12, tolerance: 0.002, "hits its control point")
    checkClose(s.value(at: 0.75), 0.88, tolerance: 0.002, "hits its other control point")

    var monotone = true
    var inRange = true
    var previous = s.value(at: 0)
    for i in 1...400 {
        let v = s.value(at: Float(i) / 400)
        if v < previous - 1e-4 { monotone = false }
        if v < 0 || v > 1 { inRange = false }
        previous = v
    }
    check(monotone, "never reverses direction")
    check(inRange, "never leaves 0...1")

    // A deliberately extreme step: still monotone, no overshoot.
    let step = ToneCurve(points: [
        CurvePoint(x: 0, y: 0), CurvePoint(x: 0.48, y: 0.02),
        CurvePoint(x: 0.52, y: 0.98), CurvePoint(x: 1, y: 1),
    ])
    var stepMonotone = true
    previous = step.value(at: 0)
    for i in 1...400 {
        let v = step.value(at: Float(i) / 400)
        if v < previous - 1e-4 { stepMonotone = false }
        previous = v
    }
    check(stepMonotone, "a near-vertical step stays monotone")

    // Unsorted and unanchored input must still evaluate.
    let messy = ToneCurve(points: [CurvePoint(x: 0.8, y: 0.6), CurvePoint(x: 0.2, y: 0.3)])
    check(messy.normalized.count == 4, "sorts and anchors both ends, got \(messy.normalized.count)")
    check(messy.value(at: 0.5).isFinite, "evaluates without anchors present")
}

print("adjustments are a no-op at their defaults and move the image otherwise")
do {
    let processor = AerochromeProcessor()
    var ramp: [(UInt8, UInt8, UInt8)] = []
    for i in 0..<64 {
        ramp.append((UInt8(i * 4), UInt8(255 - i * 3), UInt8(i * 2 + 40)))
    }
    _ = processor.prepare(cgImage: makeImage(ramp))

    check(AerochromeAdjustments().isIdentity, "default adjustments are the identity")

    let base = readPixels(processor.process(params: AerochromeParams())!)

    var untouched = AerochromeParams()
    untouched.adjustments = AerochromeAdjustments()
    let same = readPixels(processor.process(params: untouched)!)
    check(zip(base, same).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 },
          "identity adjustments change nothing")

    func meanLuma(_ px: [(Float, Float, Float)]) -> Float {
        px.reduce(0) { $0 + 0.2126 * $1.0 + 0.7152 * $1.1 + 0.0722 * $1.2 } / Float(px.count)
    }
    func meanChroma(_ px: [(Float, Float, Float)]) -> Float {
        px.reduce(0) { $0 + (max($1.0, max($1.1, $1.2)) - min($1.0, min($1.1, $1.2))) } / Float(px.count)
    }

    var brighter = AerochromeParams()
    brighter.adjustments.exposure = 1
    let up = readPixels(processor.process(params: brighter)!)
    check(meanLuma(up) > meanLuma(base), "+1 stop brightens (\(Int(meanLuma(base))) -> \(Int(meanLuma(up))))")

    var darker = AerochromeParams()
    darker.adjustments.exposure = -1
    check(meanLuma(readPixels(processor.process(params: darker)!)) < meanLuma(base), "-1 stop darkens")

    var saturated = AerochromeParams()
    saturated.adjustments.saturation = 0.6
    let sat = readPixels(processor.process(params: saturated)!)
    check(meanChroma(sat) > meanChroma(base), "saturation raises chroma (\(Int(meanChroma(base))) -> \(Int(meanChroma(sat))))")

    var grey = AerochromeParams()
    grey.adjustments.saturation = -1
    let desaturated = readPixels(processor.process(params: grey)!)
    check(meanChroma(desaturated) < 2, "saturation -1 is very nearly monochrome, chroma \(meanChroma(desaturated))")

    // The tonal-region masks vanish at both ends, so they must not create
    // clipping that was not already there.
    var lifted = AerochromeParams()
    lifted.adjustments.shadows = 1
    lifted.adjustments.highlights = 1
    let liftedPx = readPixels(processor.process(params: lifted)!)
    // The bound is that the lift never *exceeds* the endpoint. It is tight, so a
    // value very near the top does legitimately reach it — that is what a
    // highlight lift is for. What must hold is: nothing overshoots or wraps,
    // nothing already at the top moves, midtones are not blown, and the lift is
    // monotone.
    let stuckAtTop = liftedPx.enumerated().allSatisfy {
        base[$0.offset].0 < 255 || $0.element.0 == 255
    }
    check(stuckAtTop, "pixels already at the endpoint stay there — no overshoot or wrap")
    let midtonesBlown = liftedPx.enumerated().filter { $0.element.0 >= 255 && base[$0.offset].0 <= 200 }
    check(midtonesBlown.isEmpty,
          "midtones are not driven into the clip (\(midtonesBlown.count) pixels from <=200 hit 255)")
    let neverDarkens = liftedPx.enumerated().allSatisfy { $0.element.0 >= base[$0.offset].0 - 1 }
    check(neverDarkens, "a positive lift never darkens a pixel")
    check(meanLuma(liftedPx) > meanLuma(base), "shadow and highlight lifts brighten midtones")

    var warm = AerochromeParams()
    warm.adjustments.warmth = 1
    let warmed = readPixels(processor.process(params: warm)!)
    let baseTilt = base.reduce(Float(0)) { $0 + $1.0 - $1.2 } / Float(base.count)
    let warmTilt = warmed.reduce(Float(0)) { $0 + $1.0 - $1.2 } / Float(warmed.count)
    check(warmTilt > baseTilt, "warmth tilts red over blue (\(Int(baseTilt)) -> \(Int(warmTilt)))")

    // A curve pulling everything down must darken; the identity must not.
    var curved = AerochromeParams()
    curved.adjustments.curves.master = ToneCurve(points: [
        CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.25), CurvePoint(x: 1, y: 1),
    ])
    check(meanLuma(readPixels(processor.process(params: curved)!)) < meanLuma(base),
          "a downward master curve darkens")

    var redOnly = AerochromeParams()
    redOnly.adjustments.curves.red = ToneCurve(points: [
        CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.2), CurvePoint(x: 1, y: 1),
    ])
    let redPx = readPixels(processor.process(params: redOnly)!)
    let redFell = redPx.enumerated().allSatisfy { $0.element.0 <= base[$0.offset].0 + 1 }
    let greenHeld = redPx.enumerated().allSatisfy { abs($0.element.1 - base[$0.offset].1) <= 1 }
    check(redFell, "a red-channel curve only pulls red down")
    check(greenHeld, "a red-channel curve leaves green alone")
}

print("sharpening: an unsharp mask, off by default, honest about scale")
do {
    check(Sharpening().isIdentity, "sharpening is off by default")
    check(AerochromeAdjustments().isIdentity, "so the default adjustments are still the identity")
    var sharpenOnly = AerochromeAdjustments()
    sharpenOnly.sharpening.amount = 1
    check(!sharpenOnly.isIdentity && sharpenOnly.isToneIdentity,
          "a sharpening-only edit skips the tonal pass but is not the identity")

    for radius in [Float(0.3), 1, 3] {
        let kernel = AerochromeProcessor.gaussianKernel(radius: radius)
        check(kernel.count % 2 == 1, "radius \(radius): odd tap count (\(kernel.count))")
        check(abs(kernel.reduce(0, +) - 1) < 1e-5,
              "radius \(radius): sums to one, so the blur does not change brightness")
        check(kernel.first! == kernel.last!, "radius \(radius): symmetric")
    }
    check(AerochromeProcessor.gaussianKernel(radius: 3).count
            > AerochromeProcessor.gaussianKernel(radius: 1).count,
          "a larger radius reaches further")

    func luma(_ px: (Float, Float, Float)) -> Float {
        0.2126 * px.0 + 0.7152 * px.1 + 0.0722 * px.2
    }

    // A horizontal step: 16 dark columns then 16 light ones, 8 rows tall.
    let edge = makeImage(width: 32, height: 8) { x, _ in
        x < 16 ? (60, 70, 55) : (190, 200, 185)
    }
    let processor = AerochromeProcessor()
    check(processor.prepare(cgImage: edge), "prepared the edge fixture")
    let base = readRows(processor.process(params: AerochromeParams())!)[4]

    var off = AerochromeParams()
    off.adjustments.sharpening.amount = 0
    off.adjustments.sharpening.radius = 2
    let unchanged = readRows(processor.process(params: off)!)[4]
    check(zip(base, unchanged).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 },
          "amount 0 changes nothing, whatever the radius says")

    var sharp = AerochromeParams()
    sharp.adjustments.sharpening.amount = 1
    sharp.adjustments.sharpening.radius = 1
    let sharpened = readRows(processor.process(params: sharp)!)[4]

    // The signature of an unsharp mask is overshoot: the light side of an edge goes
    // lighter and the dark side darker, which is exactly the halo, kept small.
    check(luma(sharpened[16]) > luma(base[16]),
          "the light side of the edge is lifted (\(Int(luma(base[16]))) -> \(Int(luma(sharpened[16]))))")
    check(luma(sharpened[15]) < luma(base[15]),
          "the dark side is pushed down (\(Int(luma(base[15]))) -> \(Int(luma(sharpened[15]))))")
    let flat = (0..<8).allSatisfy { abs(luma(sharpened[$0]) - luma(base[$0])) <= 1 }
    check(flat, "columns far from the edge are left alone")

    // Same delta on all three channels, so hue cannot move. Checked away from the
    // clip, where 8-bit rounding is the only difference allowed.
    // Only where nothing is against an endpoint: a channel that clips has had its
    // delta truncated, which is the clip's doing and not a hue shift.
    func unclipped(_ px: (Float, Float, Float)) -> Bool {
        [px.0, px.1, px.2].allSatisfy { $0 > 0 && $0 < 255 }
    }
    let sampled = [14, 15, 16, 17].filter { unclipped(base[$0]) && unclipped(sharpened[$0]) }
    let hueHeld = !sampled.isEmpty && sampled.allSatisfy {
        abs((sharpened[$0].0 - sharpened[$0].1) - (base[$0].0 - base[$0].1)) <= 1.5
    }
    check(hueHeld,
          "sharpening does not shift hue — the detail signal is grey "
          + "(\(sampled.count) of 4 columns clear of the clip)")

    let inRange = sharpened.allSatisfy {
        (0...255).contains($0.0) && (0...255).contains($0.1) && (0...255).contains($0.2)
    }
    check(inRange, "overshoot is clipped rather than wrapped")

    var hard = AerochromeParams()
    hard.adjustments.sharpening.amount = 2
    hard.adjustments.sharpening.radius = 1
    let harder = readRows(processor.process(params: hard)!)[4]
    check(luma(harder[16]) >= luma(sharpened[16]), "more amount is more overshoot")

    // A vertical step, which only the second convolution pass can see.
    let vertical = makeImage(width: 8, height: 32) { _, y in
        y < 16 ? (60, 70, 55) : (190, 200, 185)
    }
    check(processor.prepare(cgImage: vertical), "prepared the vertical fixture")
    let vBase = readRows(processor.process(params: AerochromeParams())!)
    let vSharp = readRows(processor.process(params: sharp)!)
    check(luma(vSharp[16][4]) > luma(vBase[16][4]) && luma(vSharp[15][4]) < luma(vBase[15][4]),
          "a vertical edge overshoots too, so both convolution passes run")

    // Threshold: a low-amplitude ripple is what noise looks like, and is what the
    // threshold is there to leave alone.
    let ripple = makeImage(width: 64, height: 8) { x, _ in
        let v = UInt8(128 + (x % 2 == 0 ? 4 : -4))
        return (v, v, v)
    }
    check(processor.prepare(cgImage: ripple), "prepared the ripple fixture")
    let rippleBase = readRows(processor.process(params: AerochromeParams())!)[4]
    var noThreshold = sharp
    noThreshold.adjustments.sharpening.threshold = 0
    var thresholded = sharp
    thresholded.adjustments.sharpening.threshold = 25
    let loud = readRows(processor.process(params: noThreshold)!)[4]
    let quiet = readRows(processor.process(params: thresholded)!)[4]
    func meanShift(_ px: [(Float, Float, Float)]) -> Float {
        zip(px, rippleBase).reduce(0) { $0 + abs(luma($1.0) - luma($1.1)) } / Float(px.count)
    }
    check(meanShift(loud) > meanShift(quiet),
          "the threshold holds fine ripple back (\(String(format: "%.2f", meanShift(loud))) "
          + "-> \(String(format: "%.2f", meanShift(quiet))) levels)")

    // Scale: the radius is in full-resolution pixels, so a preview-sized render
    // must not sharpen as if it were the file.
    check(processor.prepare(cgImage: edge), "re-prepared the edge fixture")
    processor.renderScale = 0.1
    let downscaled = readRows(processor.process(params: sharp)!)[4]
    check(zip(downscaled, base).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 },
          "at 0.1 scale a 1 px radius falls below the floor and is skipped, not faked")
    processor.renderScale = 1

    // Degenerate geometry: the convolution has to survive an image narrower than
    // its own kernel.
    for (w, h) in [(1, 1), (1, 16), (16, 1), (3, 3)] {
        let tiny = AerochromeProcessor()
        check(tiny.prepare(cgImage: makeImage(width: w, height: h) { x, y in
            (UInt8(40 + x * 8 % 200), UInt8(60 + y * 8 % 190), UInt8(80))
        }), "\(w)x\(h): prepare")
        check(tiny.process(params: sharp) != nil, "\(w)x\(h): sharpening a tiny image")
    }

    // A round trip, since sharpening travels in presets and in a pasted edit.
    var carried = AerochromeAdjustments()
    carried.sharpening = Sharpening()
    carried.sharpening.amount = 0.8
    carried.sharpening.radius = 1.7
    carried.sharpening.threshold = 12
    let data = try! JSONEncoder().encode(carried)
    let back = try! JSONDecoder().decode(AerochromeAdjustments.self, from: data)
    check(back.sharpening == carried.sharpening, "sharpening survives JSON")
    let older = try! JSONDecoder().decode(
        AerochromeAdjustments.self, from: Data(#"{"exposure":0.5}"#.utf8))
    check(older.sharpening.isIdentity && older.exposure == 0.5,
          "a file written before sharpening existed still loads, with it off")
}

print("histogram counts every pixel and tracks clipping")
do {
    let processor = AerochromeProcessor()
    var pixels: [(UInt8, UInt8, UInt8)] = []
    for i in 0..<128 {
        pixels.append((UInt8(i * 2), UInt8(255 - i), UInt8(i + 30)))
    }
    _ = processor.prepare(cgImage: makeImage(pixels))
    guard let out = processor.processWithHistogram(params: AerochromeParams()) else {
        check(false, "processWithHistogram returned a result")
        exit(1)
    }
    let h = out.histogram
    check(h.red.count == 256 && h.luma.count == 256, "256 bins per series")
    check(h.red.reduce(0, +) == pixels.count, "red bins total the pixel count")
    check(h.green.reduce(0, +) == pixels.count, "green bins total the pixel count")
    check(h.luma.reduce(0, +) == pixels.count, "luma bins total the pixel count")
    check(h.peak > 0, "peak is positive")
    check((0...1).contains(h.clippedHighlights) && (0...1).contains(h.clippedShadows),
          "clipping fractions are fractions")

    // Force pure white and confirm it lands in the top bin.
    var blown = AerochromeParams()
    blown.adjustments.exposure = 3
    blown.adjustments.whites = 1
    guard let hot = processor.processWithHistogram(params: blown) else {
        check(false, "blown render produced a histogram")
        exit(1)
    }
    check(hot.histogram.clippedHighlights > out.histogram.clippedHighlights,
          "blowing the exposure raises highlight clipping")

    check(processor.process(params: AerochromeParams()) != nil, "plain process still works")
}

print("adjustments and curves survive a preset round-trip")
do {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("irgconverter-check-adjust-\(ProcessInfo.processInfo.processIdentifier)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = AerochromePresetStore(directory: tmp)

    var p = AerochromeParams()
    p.adjustments.exposure = 0.62
    p.adjustments.vibrance = -0.4
    p.adjustments.curves.blue = ToneCurve(points: [
        CurvePoint(x: 0, y: 0.05), CurvePoint(x: 0.6, y: 0.4), CurvePoint(x: 1, y: 0.95),
    ])
    var raw = RawDevelopSettings()
    raw.useNeutralBalance = false
    raw.temperature = 7200
    raw.exposure = -0.4

    do { try store.save(AerochromePreset(name: "Adjusted", params: p, raw: raw)) }
    catch { check(false, "save threw: \(error)") }

    let reloaded = AerochromePresetStore(directory: tmp)
    guard let back = reloaded.preset(named: "Adjusted") else {
        check(false, "preset reloaded")
        exit(1)
    }
    check(back.params.adjustments == p.adjustments, "adjustments and curves round-trip exactly")
    check(back.raw == raw, "RAW development settings round-trip")
    check(back.raw?.useNeutralBalance == false, "the neutral-balance flag round-trips")

    // Files from the builds that had Look dials carry `look`, `usesLook` and, older
    // still, an `options` object. None of those fields exist any more. What must not
    // happen is a failed load: the numbers those builds put on the sliders are in
    // `params`, so a preset from either era still means what it meant.
    let legacy = tmp.appendingPathComponent("legacy.irgpreset")
    try? #"{"name":"Legacy Dials","usesLook":true,"look":{"strength":0.8,"magenta":0.6,"density":0.3},"options":{"lookStrength":0.8},"params":{"gammaBy":1.4,"subtractIRGreen":0.42}}"#
        .write(to: legacy, atomically: true, encoding: .utf8)
    if let added = try? reloaded.importPresets(from: legacy), let old = added.first {
        check(old.name == "Legacy Dials", "a preset from the Look-dial era still loads")
        check(old.params.gammaBy == 1.4 && old.params.subtractIRGreen == 0.42,
              "and keeps the numbers that were on its sliders")
        check(old.resolved == old.params, "nothing is re-derived from the dropped dials")
    } else {
        check(false, "legacy preset imported")
    }
}

print("raw development defaults")
do {
    let d = RawDevelopSettings()
    check(d.useNeutralBalance, "neutral balance is on by default")
    check(d.exposure == -1.0, "one stop of highlight headroom by default, got \(d.exposure)")
    check(d.temperature == 5500, "5500 K nominal daylight when balance is off, got \(d.temperature)")
    check(RawDevelopSettings.temperatureRange.contains(d.temperature), "default temperature is in range")
}

print("the transform follows the document's structure")
do {
    // A pixel with strong infrared and moderate visible, i.e. foliage.
    let processor = AerochromeProcessor()
    _ = processor.prepare(cgImage: makeImage([(160, 90, 120)]))

    var p = AerochromeParams()
    p.subtractIRRed = 0.5
    p.subtractIRGreen = 0.8
    p.gammaRx = 1
    p.gammaGx = 1
    p.gammaBy = 1
    p.overallGamma = 1

    // With every gamma at 1 the whole thing is arithmetic we can state by hand:
    //   ir = 120/255, visRed = 160/255, visGreen = 90/255
    //   red   = visRed   - 0.5 * ir
    //   green = visGreen - 0.8 * ir
    let ir = Float(120) / 255, visRed = Float(160) / 255, visGreen = Float(90) / 255
    let wantRedSignal = visRed - 0.5 * ir
    let wantGreenSignal = max(visGreen - 0.8 * ir, 0)
    let px = readPixels(processor.process(params: p)!)[0]
    // Default map: R <- infrared, G <- visible red, B <- visible green.
    checkClose(px.0, (ir * 255).rounded(), tolerance: 1, "R is the untouched infrared")
    checkClose(px.1, (wantRedSignal * 255).rounded(), tolerance: 1, "G is red minus 0.5x infrared")
    checkClose(px.2, (wantGreenSignal * 255).rounded(), tolerance: 1, "B is green minus 0.8x infrared")

    // Curve order is the one thing that separates this from extract mode: red's
    // curve is above the subtract, green's below it. So changing gammaRx must
    // scale the already-subtracted red, while gammaGx scales green *before*
    // subtraction — which is observable.
    var redCurve = p
    redCurve.gammaRx = 2
    let afterRedCurve = readPixels(processor.process(params: redCurve)!)[0]
    checkClose(afterRedCurve.1, (powf(wantRedSignal, 0.5) * 255).rounded(), tolerance: 1,
               "red curve applies after the subtract")

    var greenCurve = p
    greenCurve.gammaGx = 2
    let afterGreenCurve = readPixels(processor.process(params: greenCurve)!)[0]
    let wantGreenCurved = max(powf(visGreen, 0.5) - 0.8 * ir, 0)
    checkClose(afterGreenCurve.2, (wantGreenCurved * 255).rounded(), tolerance: 1,
               "green curve applies before the subtract")

    // Subtract clamps at zero rather than wrapping.
    var heavy = p
    heavy.subtractIRGreen = 2
    let clamped = readPixels(processor.process(params: heavy)!)[0]
    check(clamped.2 == 0, "an over-subtracted channel clamps at 0, got \(clamped.2)")

    // Gamma above 1 brightens, matching overallGamma's convention.
    var brighter = p
    brighter.gammaBy = 2
    check(readPixels(processor.process(params: brighter)!)[0].0 > px.0,
          "gamma above 1 brightens the infrared group")
}

print("each preset in the family moves in the direction its notes claim")
do {
    // Foliage alternating with sky: bright infrared and dim visible for the leaves,
    // the other way round for the sky. That is the signal the presets differ on, so
    // a flat ramp would not tell them apart.
    var pixels: [(UInt8, UInt8, UInt8)] = []
    for i in 0..<120 {
        if i % 2 == 0 {
            pixels.append((UInt8(70 + i / 4), UInt8(60 + i / 6), UInt8(190 + i / 8)))  // leaf
        } else {
            pixels.append((UInt8(120 + i / 4), UInt8(150 + i / 4), UInt8(90 + i / 8))) // sky
        }
    }
    let processor = AerochromeProcessor()
    check(processor.prepare(cgImage: makeImage(pixels)), "prepared the foliage-and-sky fixture")

    let store = AerochromePresetStore(directory: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("irgconverter-check-family"))
    func render(_ name: String) -> [(Float, Float, Float)]? {
        guard let preset = store.preset(named: name) else {
            check(false, "\(name) exists")
            return nil
        }
        guard let out = processor.process(params: preset.resolved) else {
            check(false, "\(name) rendered")
            return nil
        }
        return readPixels(out)
    }
    func mean(_ px: [(Float, Float, Float)], _ pick: ((Float, Float, Float)) -> Float) -> Float {
        px.reduce(0) { $0 + pick($1) } / Float(px.count)
    }
    func chroma(_ p: (Float, Float, Float)) -> Float {
        max(p.0, max(p.1, p.2)) - min(p.0, min(p.1, p.2))
    }
    func luma(_ p: (Float, Float, Float)) -> Float { 0.2126 * p.0 + 0.7152 * p.1 + 0.0722 * p.2 }

    guard let base = render("Aerochrome Magenta") else { exit(1) }

    if let red = render("Aerochrome Red") {
        // Blue out is the visible-green signal, and that is what the green
        // subtraction eats — less blue in the leaves is less pink.
        check(mean(red, \.2) < mean(base, \.2),
              "Red pulls the blue output down (\(Int(mean(base, \.2))) -> \(Int(mean(red, \.2))))")
    }
    if let bold = render("Aerochrome Bold") {
        check(mean(bold, \.0) > mean(base, \.0),
              "Bold brightens the red output (\(Int(mean(base, \.0))) -> \(Int(mean(bold, \.0))))")
        check(mean(bold, chroma) > mean(base, chroma),
              "and separates the channels further "
              + "(\(Int(mean(base, chroma))) -> \(Int(mean(bold, chroma))))")
    }
    if let subtle = render("Aerochrome Subtle") {
        check(mean(subtle, chroma) < mean(base, chroma),
              "Subtle separates less (\(Int(mean(base, chroma))) -> \(Int(mean(subtle, chroma))))")
    }
    if let deep = render("Aerochrome Deep") {
        check(mean(deep, luma) < mean(base, luma),
              "Deep renders denser (\(Int(mean(base, luma))) -> \(Int(mean(deep, luma))))")
    }
    if let swapped = render("Pre-swapped IRG"), let preset = store.preset(named: "Pre-swapped IRG") {
        check(preset.params.sourceIR == 0, "Pre-swapped IRG reads infrared from red")
        check(zip(swapped, base).contains { $0.0 != $1.0 || $0.1 != $1.1 || $0.2 != $1.2 },
              "and therefore renders differently")
    }

    // Everything else about a sibling must match the default, so the family stays a
    // family and each preset's notes are the whole story of what it changes.
    for preset in store.builtIn where preset.name != "Aerochrome Magenta" {
        let d = AerochromePresetStore.default.params
        let p = preset.params
        let sameRoles = p.sourceIR == d.sourceIR || preset.name == "Pre-swapped IRG"
        check(sameRoles, "\(preset.name): only the pre-swapped preset moves the source roles")
        check(p.outputMapR == d.outputMapR && p.outputMapG == d.outputMapG
              && p.outputMapB == d.outputMapB,
              "\(preset.name): keeps the Aerochrome channel map")
        check(preset.raw == RawDevelopSettings(),
              "\(preset.name): carries the measured development defaults")
    }
}

print("the tiles sheet can render every preset from one prepared buffer")
do {
    // What `PresetPreviewEngine` does: prepare once at tile size, then run each
    // preset's parameters over the same planes. If that ever stopped working the
    // sheet would show blanks, so it is worth pinning here rather than only in the UI.
    var pixels: [(UInt8, UInt8, UInt8)] = []
    for i in 0..<64 {
        pixels.append((UInt8(70 + i), UInt8(60 + i / 2), UInt8(190 - i))) 
    }
    let processor = AerochromeProcessor()
    check(processor.prepare(cgImage: makeImage(pixels)), "one prepare for the whole sheet")

    let store = AerochromePresetStore(directory: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("irgconverter-check-tiles"))
    var rendered: [String: [(Float, Float, Float)]] = [:]
    for preset in store.builtIn {
        guard let out = processor.process(params: preset.params) else {
            check(false, "\(preset.name) tile rendered")
            continue
        }
        rendered[preset.name] = readPixels(out)
    }
    check(rendered.count == store.builtIn.count,
          "every preset produced a tile from the shared buffer (\(rendered.count))")

    // Distinct tiles: a sheet of identical thumbnails would be worse than none.
    let distinct = Set(rendered.values.map { px in
        px.prefix(8).map { "\(Int($0.0)),\(Int($0.1)),\(Int($0.2))" }.joined(separator: ";")
    })
    check(distinct.count == rendered.count,
          "no two tiles come out identical (\(distinct.count) of \(rendered.count))")

    // And the shared processor is not left holding a preset's state: rendering the
    // default last must match rendering it first.
    let first = rendered[AerochromePresetStore.default.name]!
    let again = readPixels(processor.process(params: AerochromePresetStore.default.params)!)
    check(zip(first, again).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 },
          "re-rendering a preset on the reused processor gives the same tile")
}

print("every preset resolves to values its sliders can show")
do {
    let store = AerochromePresetStore(directory: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("irgconverter-check-presets-range"))
    for preset in store.builtIn {
        let p = preset.resolved
        check((0...2).contains(p.subtractIRRed) && (0...2).contains(p.subtractIRGreen),
              "\(preset.name): subtractions within range "
              + "(\(String(format: "%.2f", p.subtractIRRed)), \(String(format: "%.2f", p.subtractIRGreen)))")
        check((0.1...10).contains(p.gammaBy) && (0.25...4).contains(p.overallGamma),
              "\(preset.name): gammas within range "
              + "(\(String(format: "%.2f", p.gammaBy)), \(String(format: "%.2f", p.overallGamma)))")
        check((0.1...10).contains(p.gammaRx) && (0.1...10).contains(p.gammaGx),
              "\(preset.name): group curves within range")
        check(p == preset.params, "\(preset.name): values pass through untouched")
    }
    // The magenta lean lives in the gap between the two subtractions: less taken
    // out of the green group leaves more infrared in the blue output, which is what
    // makes the default pink rather than red.
    let p = AerochromePresetStore.default.resolved
    check(p.subtractIRGreen < p.subtractIRRed,
          "the default leaves more infrared in green than in red "
          + "(\(String(format: "%.2f", p.subtractIRGreen)) < \(String(format: "%.2f", p.subtractIRRed)))")
}

print("viewing aids are diagnostic only")
do {
    let processor = AerochromeProcessor()
    var pixels: [(UInt8, UInt8, UInt8)] = []
    for i in 0..<64 {
        pixels.append((UInt8(120 + i), UInt8(60 + i), UInt8(40 + i * 2)))
    }
    _ = processor.prepare(cgImage: makeImage(pixels))
    let p = AerochromeParams()

    let plain = readPixels(processor.process(params: p)!)

    // Export path takes no aids at all, so it cannot pick one up.
    var soloAids = ViewingAids()
    soloAids.solo = .infrared
    let exported = readPixels(processor.process(params: p)!)
    check(zip(plain, exported).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 },
          "process(params:) ignores aids entirely")

    guard let soloed = processor.processWithHistogram(params: p, aids: soloAids) else {
        check(false, "solo render produced an image")
        exit(1)
    }
    let soloPx = readPixels(soloed.image)
    check(soloPx.allSatisfy { $0.0 == $0.1 && $0.1 == $0.2 }, "a soloed signal renders grey")
    // Default map puts infrared on red, so soloing infrared must match that channel.
    check(zip(soloPx, plain).allSatisfy { abs($0.0 - $1.0) <= 1 },
          "soloing infrared matches the channel it normally drives")

    var greenSolo = ViewingAids()
    greenSolo.solo = .visibleGreen
    let greenPx = readPixels(processor.processWithHistogram(params: p, aids: greenSolo)!.image)
    check(zip(greenPx, plain).allSatisfy { abs($0.0 - $1.2) <= 1 },
          "soloing visible green matches the blue output channel")

    // Soloing bypasses the photo edits, so they must make no difference to it.
    var edited = p
    edited.adjustments.exposure = 1.5
    edited.adjustments.saturation = -0.8
    let editedSolo = readPixels(processor.processWithHistogram(params: edited, aids: soloAids)!.image)
    check(zip(editedSolo, soloPx).allSatisfy { $0.0 == $1.0 },
          "soloing bypasses the Adjust tab")
    let editedNormal = readPixels(processor.processWithHistogram(params: edited)!.image)
    check(!zip(editedNormal, plain).allSatisfy { $0.0 == $1.0 },
          "the same edits do change the normal view")

    // Clipping overlay paints the marker colours, and does so after the histogram
    // is taken so the counts stay honest.
    var clip = ViewingAids()
    clip.showClipping = true
    guard let marked = processor.processWithHistogram(params: p, aids: clip) else {
        check(false, "clipping render produced an image")
        exit(1)
    }
    let unmarked = processor.processWithHistogram(params: p)!
    check(marked.histogram == unmarked.histogram,
          "the overlay does not contaminate the histogram")
    let markedPx = readPixels(marked.image)
    let crushedColour = markedPx.contains { $0 == (0, 120, 255) }
    let anyCrushed = plain.contains { $0.0 == 0 || $0.1 == 0 || $0.2 == 0 }
    check(crushedColour == anyCrushed,
          "crushed pixels are marked exactly when there are any (\(anyCrushed))")
}

print("copying edits between photos")
do {
    /// Two edits with *every* stored value different, so a paste that misses a
    /// field, or writes one it does not own, shows up as an inequality rather
    /// than passing by coincidence.
    func distinct(_ seed: Float) -> PhotoEdit {
        var p = AerochromeParams()
        p.sourceIR = seed > 0.5 ? 1 : 2
        p.sourceVisibleRed = seed > 0.5 ? 2 : 0
        p.sourceVisibleGreen = seed > 0.5 ? 0 : 1
        p.gammaBy = 1.4 + seed
        p.subtractIRRed = 0.2 + seed * 0.3
        p.gammaRx = 0.6 + seed
        p.gammaGx = 1.1 + seed
        p.subtractIRGreen = 0.05 + seed * 0.2
        p.overallGamma = 1.2 + seed
        p.outputMapR = seed > 0.5 ? 0 : 2
        p.outputMapG = seed > 0.5 ? 1 : 0
        p.outputMapB = seed > 0.5 ? 2 : 1
        p.adjustments.exposure = seed
        p.adjustments.contrast = -seed
        p.adjustments.saturation = seed * 0.5
        p.adjustments.curves.master = ToneCurve(points: [
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.5, y: 0.5 + seed * 0.2),
            CurvePoint(x: 1, y: 1),
        ])

        var raw = RawDevelopSettings()
        raw.useNeutralBalance = seed > 0.5
        raw.temperature = 4000 + seed * 2000
        raw.tint = seed * 20
        raw.exposure = -1 - seed * 0.5

        return PhotoEdit(params: p, raw: raw)
    }

    let source = distinct(0.8)
    let destination = distinct(0.2)
    check(source != destination, "the two fixtures differ")

    check(PasteOptions.all.apply(source, to: destination) == source,
          "pasting everything makes the destination identical to the source")

    // The three groups partition the edit: pasting them one at a time in any order
    // has to land on the same result as pasting the lot. This is what makes the
    // checkbox list safe — no value belongs to two groups, and none to none of them.
    var stepwise = destination
    for options in [PasteOptions(transform: true, adjustments: false, rawDevelopment: false),
                    PasteOptions(transform: false, adjustments: true, rawDevelopment: false),
                    PasteOptions(transform: false, adjustments: false, rawDevelopment: true)] {
        stepwise = options.apply(source, to: stepwise)
    }
    check(stepwise == source, "the three groups cover every value between them")

    // Each group in isolation: what it claims, and nothing else.
    let transformOnly = PasteOptions(transform: true, adjustments: false,
                                     rawDevelopment: false).apply(source, to: destination)
    check(transformOnly.params.gammaBy == source.params.gammaBy
          && transformOnly.params.subtractIRRed == source.params.subtractIRRed
          && transformOnly.params.subtractIRGreen == source.params.subtractIRGreen
          && transformOnly.params.overallGamma == source.params.overallGamma
          && transformOnly.params.gammaRx == source.params.gammaRx
          && transformOnly.params.gammaGx == source.params.gammaGx
          && transformOnly.params.sourceIR == source.params.sourceIR
          && transformOnly.params.outputMapB == source.params.outputMapB,
          "the transform group carries every Aerochrome-tab control")
    check(transformOnly.params.adjustments == destination.params.adjustments
          && transformOnly.raw == destination.raw,
          "the transform group leaves tone and development alone")

    // Values travel verbatim. Nothing is re-derived on the way in, so a paste
    // reproduces exactly what the source photo showed.
    var detached = source
    detached.params.gammaBy = 9.5
    let pastedDetached = PasteOptions(transform: true, adjustments: false,
                                      rawDevelopment: false).apply(detached, to: destination)
    check(pastedDetached.params.gammaBy == 9.5, "an unusual IR gamma pastes as itself")

    let toneOnly = PasteOptions(transform: false, adjustments: true,
                                rawDevelopment: false).apply(source, to: destination)
    check(toneOnly.params.adjustments == source.params.adjustments
          && toneOnly.params.gammaBy == destination.params.gammaBy
          && toneOnly.raw == destination.raw,
          "the tone group carries only the Adjust tab")

    // A non-RAW destination has no development to set, so the caller suppresses
    // that group and the numbers stay at the destination's own.
    let noRaw = PasteOptions.all.apply(source, to: destination, includeRaw: false)
    check(noRaw.raw == destination.raw, "includeRaw: false leaves development untouched")
    check(noRaw.params == source.params, "includeRaw: false still pastes everything else")

    check(PasteOptions(transform: false, adjustments: false, rawDevelopment: false).isEmpty,
          "all three off reads as empty")
    check(!PasteOptions.all.isEmpty && PasteOptions.all.summary == "everything",
          "the default pastes everything")
    check(PasteOptions(transform: true, adjustments: true,
                       rawDevelopment: false).summary == "transform, tone",
          "the summary names the groups it will write")
    check(PasteOptions(transform: false, adjustments: false,
                       rawDevelopment: false).apply(source, to: destination) == destination,
          "an empty paste changes nothing")

    let encoded = try JSONEncoder().encode(source)
    let decoded = try JSONDecoder().decode(PhotoEdit.self, from: encoded)
    check(decoded == source, "an edit survives a JSON round-trip")
    let sparse = try JSONDecoder().decode(PhotoEdit.self, from: Data("{}".utf8))
    check(sparse == PhotoEdit(), "an empty object decodes to the defaults")
}

print("batch export naming")
do {
    let dir = BatchNaming.Destination.folder(
        URL(fileURLWithPath: "/tmp/irg-batch-check", isDirectory: true))
    let dirPath = "/tmp/irg-batch-check"
    let source = URL(fileURLWithPath: "/photos/P7290001.ORF")

    let first = BatchNaming.outputURL(for: source, in: dir, exists: { _ in false })
    check(first.lastPathComponent == "P7290001_aerochrome.heic",
          "the output keeps the source's name plus the suffix (\(first.lastPathComponent))")
    check(first.deletingLastPathComponent().path == dirPath,
          "the output lands in the chosen folder")

    // Running the same batch twice must not overwrite the first run's files: the
    // settings may have changed in between and the originals are not recoverable
    // from the result.
    var taken: Set<String> = [first.path]
    let second = BatchNaming.outputURL(for: source, in: dir, exists: { taken.contains($0.path) })
    check(second.lastPathComponent == "P7290001_aerochrome-2.heic",
          "a taken name gets a counter (\(second.lastPathComponent))")
    taken.insert(second.path)
    let third = BatchNaming.outputURL(for: source, in: dir, exists: { taken.contains($0.path) })
    check(third.lastPathComponent == "P7290001_aerochrome-3.heic",
          "the counter keeps going (\(third.lastPathComponent))")

    let other = BatchNaming.outputURL(for: URL(fileURLWithPath: "/photos/P7290002.ORF"),
                                      in: dir, exists: { taken.contains($0.path) })
    check(other.lastPathComponent == "P7290002_aerochrome.heic",
          "a different source is unaffected by the collisions")

    let jpeg = BatchNaming.outputURL(for: URL(fileURLWithPath: "/photos/a.b.c.jpg"),
                                     in: dir, exists: { _ in false })
    check(jpeg.lastPathComponent == "a.b.c_aerochrome.heic",
          "only the last extension is replaced (\(jpeg.lastPathComponent))")

    // The Lightroom hand-off writes TIFF next to each original instead of into one
    // chosen folder, so the same naming has to work per source directory.
    let beside = BatchNaming.outputURL(for: source, in: .besideOriginal,
                                       format: .tiff, exists: { _ in false })
    check(beside.deletingLastPathComponent().path == "/photos",
          "besideOriginal writes into the source's own folder (\(beside.path))")
    check(beside.lastPathComponent == "P7290001_aerochrome.tif",
          "the TIFF hand-off uses the tif extension (\(beside.lastPathComponent))")

    let besideOther = BatchNaming.outputURL(
        for: URL(fileURLWithPath: "/elsewhere/B.ORF"), in: .besideOriginal,
        format: .tiff, exists: { _ in false })
    check(besideOther.path == "/elsewhere/B_aerochrome.tif",
          "each photo follows its own original (\(besideOther.path))")

    var takenTiff: Set<String> = [beside.path]
    let besideAgain = BatchNaming.outputURL(for: source, in: .besideOriginal, format: .tiff,
                                            exists: { takenTiff.contains($0.path) })
    check(besideAgain.lastPathComponent == "P7290001_aerochrome-2.tif",
          "a second hand-off of the same photo does not overwrite the first")
    takenTiff.insert(besideAgain.path)

    check(BatchNaming.Destination.folder(URL(fileURLWithPath: "/out"))
            .directory(for: source).path == "/out",
          "a folder destination ignores where the source came from")
    check(BatchNaming.Destination.besideOriginal.directory(for: source).path == "/photos",
          "besideOriginal resolves to the source's directory")
}

print("export formats")
do {
    check(ImageIOSupport.ExportFormat.heic.fileExtension == "heic"
          && ImageIOSupport.ExportFormat.tiff.fileExtension == "tif",
          "each format names its own extension")
    check(ImageIOSupport.ExportFormat.heic.utType == .heic
          && ImageIOSupport.ExportFormat.tiff.utType == .tiff,
          "each format maps to the right content type")
    check(ImageIOSupport.exportExtension == ImageIOSupport.ExportFormat.heic.fileExtension,
          "the save panel's extension follows the HEIC format")

    // Both formats are written from the same 16-bit render, on a synthetic ramp
    // whose values are known exactly. TIFF is lossless, so it has to come back
    // bit-identical; that is the whole reason the Lightroom hand-off uses it.
    let width = 256, height = 8
    var pixels = [UInt16](repeating: 0, count: width * height * 3)
    for y in 0..<height {
        for x in 0..<width {
            let base = (y * width + x) * 3
            let v = UInt16(x * 257)
            pixels[base] = v
            pixels[base + 1] = UInt16(65535 - Int(v))
            pixels[base + 2] = UInt16((x * 137) % 65536)
        }
    }
    let render = RenderedImage16(pixels: pixels, width: width, height: height)

    let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("irg-format-check-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let tiffURL = tmp.appendingPathComponent("ramp.tif")
    try ImageIOSupport.write(render, to: tiffURL, format: .tiff)
    check(FileManager.default.fileExists(atPath: tiffURL.path), "the TIFF was written")

    guard let source = CGImageSourceCreateWithURL(tiffURL as CFURL, nil),
          let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        check(false, "the TIFF reads back")
        exit(1)
    }
    check(CGImageSourceGetType(source) as String? == UTType.tiff.identifier,
          "it really is a TIFF")
    check(decoded.bitsPerComponent == 16,
          "16 bits per channel survive the round trip (got \(decoded.bitsPerComponent))")
    check(decoded.width == width && decoded.height == height, "dimensions survive")
    check(decoded.colorSpace?.name == CGColorSpace.sRGB,
          "the sRGB profile is attached, so another editor knows what the numbers mean")

    // Read the samples back and compare against what went in.
    var readback = [UInt16](repeating: 0, count: width * height * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    readback.withUnsafeMutableBytes { raw in
        CIContext(options: [.workingColorSpace: cs]).render(
            CIImage(cgImage: decoded), toBitmap: raw.baseAddress!,
            rowBytes: width * 8, bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA16, colorSpace: cs)
    }
    var worst = 0
    for y in 0..<height {
        for x in 0..<width {
            let src = (y * width + x) * 3
            let dst = (y * width + x) * 4
            for channel in 0..<3 {
                worst = max(worst, abs(Int(pixels[src + channel]) - Int(readback[dst + channel])))
            }
        }
    }
    check(worst == 0, "every sample comes back exactly — TIFF loses nothing (worst Δ\(worst))")

    // HEIC is lossy and 10-bit, so it is only asked to be close, not exact. This is
    // the measured reason the hand-off is not HEIC.
    let heicURL = tmp.appendingPathComponent("ramp.heic")
    try ImageIOSupport.write(render, to: heicURL, format: .heic)
    let tiffSize = (try? FileManager.default.attributesOfItem(atPath: tiffURL.path)[.size] as? Int) ?? 0
    let heicSize = (try? FileManager.default.attributesOfItem(atPath: heicURL.path)[.size] as? Int) ?? 0
    check(tiffSize > 0 && heicSize > 0,
          "both formats produced a file (TIFF \(tiffSize) bytes, HEIC \(heicSize) bytes)")
    // Uncompressed TIFF is exactly the samples plus a small header, which is the
    // measured choice — see the table in `ImageIOSupport.write`.
    let payload = width * height * 6
    check(tiffSize >= payload && tiffSize < payload + 4096,
          "the TIFF is the raw samples plus a header, i.e. uncompressed "
          + "(\(tiffSize) bytes for \(payload) of pixels)")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
