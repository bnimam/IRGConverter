// Command-line converter.
//
// Exists so something other than the GUI can drive the transform — the Lightroom
// plugin shells out to this. Also useful for batch work from a shell.
//
//   irgconvert --input in.ORF --output out.heic --preset "Aerochrome Bold"

import AppKit
import CoreImage
import Foundation
import ImageIO
import IRGConverterCore
import UniformTypeIdentifiers

// MARK: - Argument parsing

struct Options {
    var input: URL?
    var output: URL?
    var preset: String?
    var raw = RawDevelopSettings()
    /// Transform controls given on the command line, applied over the preset's.
    /// Nil means "leave the preset's value alone" — 0 is a legitimate setting for
    /// a subtraction, so absence cannot be spelled with a number.
    var gammaBy: Float?
    var subtractIRRed: Float?
    var gammaRx: Float?
    var gammaGx: Float?
    var subtractIRGreen: Float?
    var overallGamma: Float?
    /// Nil unless a `--sharpen*` flag was given, so a preset's own sharpening is
    /// left alone otherwise.
    var sharpening: Sharpening?
    var listPresets = false
    var quiet = false
    /// Set by `--ir-channel`; nil leaves whatever the preset chose.
    var irChannel: Int?
}

let usage = """
irgconvert — convert an IRG photograph to the Kodak Aerochrome look

USAGE
  irgconvert --input <file> --output <file.heic> [options]
  irgconvert --list-presets

OPTIONS
  --input <path>        Source image. RAW, or anything Core Graphics can decode.
  --output <path>       Destination. Always written as HEIC.
  --preset <name>       Start from a named preset. See --list-presets.
                        Default: “Aerochrome Magenta”, as in the app.
  --ir-gamma <0.1..10>  Curve on the infrared group. The strongest single control.
  --red-subtract <0..2> How much infrared comes out of the red group.
  --red-gamma <0.1..10> Curve on the red group, above its subtract.
  --green-gamma         Curve on the green group, below its subtract.
  --green-subtract      How much infrared comes out of the green group. Lower
                        leaves foliage pinker, higher takes it toward pure red.
  --output-gamma        The final curve over the composite. Lower is denser.
  --sharpen <0..2>      Unsharp mask amount. 0 (default) is off.
  --sharpen-radius <px> Radius in pixels. Default 1.0.
  --sharpen-threshold   Leave detail below this many levels of 255 alone. Default 0.
  --ir-channel <r|g|b>  Which source channel holds infrared. Default b.
  --headroom <stops>    RAW highlight headroom. Default -1.0.
  --temperature <K>     RAW colour temperature. Implies non-neutral balance.
  --tint <-150..150>    RAW tint. Implies non-neutral balance.
  --quiet               Suppress the summary line.
  --version             Print the version and exit.
  --help                This text.

Values given on the command line override the preset's.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("irgconvert: " + message + "\n").utf8))
    exit(2)
}

func parse(_ arguments: [String]) -> Options {
    var o = Options()
    var i = 0
    func next(_ flag: String) -> String {
        i += 1
        guard i < arguments.count else { fail("\(flag) needs a value") }
        return arguments[i]
    }
    func float(_ flag: String) -> Float {
        let raw = next(flag)
        guard let v = Float(raw) else { fail("\(flag): '\(raw)' is not a number") }
        return v
    }

    var explicitBalance = false
    while i < arguments.count {
        switch arguments[i] {
        case "--input", "-i": o.input = URL(fileURLWithPath: next("--input"))
        case "--output", "-o": o.output = URL(fileURLWithPath: next("--output"))
        case "--preset", "-p": o.preset = next("--preset")
        case "--ir-gamma": o.gammaBy = float("--ir-gamma")
        case "--red-subtract": o.subtractIRRed = float("--red-subtract")
        case "--red-gamma": o.gammaRx = float("--red-gamma")
        case "--green-gamma": o.gammaGx = float("--green-gamma")
        case "--green-subtract": o.subtractIRGreen = float("--green-subtract")
        case "--output-gamma": o.overallGamma = float("--output-gamma")
        case "--headroom": o.raw.exposure = float("--headroom")
        case "--temperature":
            o.raw.temperature = float("--temperature")
            explicitBalance = true
        case "--tint":
            o.raw.tint = float("--tint")
            explicitBalance = true
        case "--ir-channel":
            let name = next("--ir-channel").lowercased()
            guard let index = ["r": 0, "g": 1, "b": 2][name] else {
                fail("--ir-channel: expected r, g or b")
            }
            o.irChannel = index
        case "--sharpen":
            o.sharpening = o.sharpening ?? Sharpening()
            o.sharpening?.amount = float("--sharpen")
        case "--sharpen-radius":
            o.sharpening = o.sharpening ?? Sharpening()
            o.sharpening?.radius = float("--sharpen-radius")
        case "--sharpen-threshold":
            o.sharpening = o.sharpening ?? Sharpening()
            o.sharpening?.threshold = float("--sharpen-threshold")
        case "--list-presets": o.listPresets = true
        case "--quiet", "-q": o.quiet = true
        case "--version":
            print("irgconvert \(IRGConverterVersion.current)")
            exit(0)
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            fail("unknown option '\(arguments[i])'")
        }
        i += 1
    }
    if explicitBalance { o.raw.useNeutralBalance = false }
    return o
}

let options = parse(Array(CommandLine.arguments.dropFirst()))
let store = AerochromePresetStore()

if options.listPresets {
    for preset in store.all {
        let kind = store.user.contains(where: { $0.name == preset.name }) ? "yours" : "built-in"
        print("\(preset.name)  [\(kind)]")
        if let notes = preset.notes { print("    \(notes)") }
    }
    exit(0)
}

guard let input = options.input else { fail("--input is required (see --help)") }
guard let output = options.output else { fail("--output is required (see --help)") }
guard FileManager.default.fileExists(atPath: input.path) else {
    fail("no such file: \(input.path)")
}

// MARK: - Resolve settings

// No --preset means the default one, so the command line and the app start a photo
// from the same place.
let preset: AerochromePreset
if let name = options.preset {
    guard let found = store.preset(named: name) else {
        let known = store.all.map(\.name).joined(separator: ", ")
        fail("unknown preset '\(name)'. Known: \(known)")
    }
    preset = found
} else {
    preset = AerochromePresetStore.default
}

var params = preset.params
// A development flag given on the command line beats the preset's, which is the
// only way to override it — every preset carries development settings.
var raw = options.raw
if let presetRaw = preset.raw, options.raw == RawDevelopSettings() { raw = presetRaw }

// Transform controls given on the command line, over the preset's.
if let v = options.gammaBy { params.gammaBy = v }
if let v = options.subtractIRRed { params.subtractIRRed = v }
if let v = options.gammaRx { params.gammaRx = v }
if let v = options.gammaGx { params.gammaGx = v }
if let v = options.subtractIRGreen { params.subtractIRGreen = v }
if let v = options.overallGamma { params.overallGamma = v }

// Full resolution here, so the radius is already in the units it is defined in and
// the processor's `renderScale` stays 1.
if let sharpening = options.sharpening { params.adjustments.sharpening = sharpening }
if let ir = options.irChannel {
    params.sourceIR = ir
    let others = [0, 1, 2].filter { $0 != ir }
    params.sourceVisibleRed = others[0]
    params.sourceVisibleGreen = others[1]
}

// MARK: - Convert

do {
    let source = try ImageIOSupport.load(url: input, raw: raw)
    let processor = AerochromeProcessor()
    guard processor.prepare(cgImage: source),
          let rendered = processor.render16(params: params)
    else { fail("could not process \(input.lastPathComponent)") }

    try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try ImageIOSupport.write(rendered, to: output)

    if !options.quiet {
        print("\(input.lastPathComponent) -> \(output.lastPathComponent)  "
              + "\(rendered.width)x\(rendered.height)  "
              + "preset \(preset.name)  "
              + "IR gamma \(String(format: "%.2f", params.gammaBy))")
    }
} catch {
    fail(error.localizedDescription)
}
