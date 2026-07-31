// Command-line converter.
//
// Exists so something other than the GUI can drive the transform — the Lightroom
// plugin shells out to this. Also useful for batch work from a shell.
//
//   irgconvert --input in.ORF --output out.heic --strength 0.5

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
    var look = LookSettings()
    var raw = RawDevelopSettings()
    var monochrome: MonochromeSource = .off
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
  --strength <0..1>     Look strength. Default 0.5.
  --magenta <-1..1>     Foliage between pure red and magenta. Default 0.
  --density <-1..1>     Overall density. Default 0.
  --sharpen <0..2>      Unsharp mask amount. 0 (default) is off.
  --sharpen-radius <px> Radius in pixels. Default 1.0.
  --sharpen-threshold   Leave detail below this many levels of 255 alone. Default 0.
  --mono <mode>         off | infrared | visibleRed | visibleGreen | luminance
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
        case "--strength": o.look.strength = float("--strength")
        case "--magenta": o.look.magenta = float("--magenta")
        case "--density": o.look.density = float("--density")
        case "--headroom": o.raw.exposure = float("--headroom")
        case "--temperature":
            o.raw.temperature = float("--temperature")
            explicitBalance = true
        case "--tint":
            o.raw.tint = float("--tint")
            explicitBalance = true
        case "--mono":
            let name = next("--mono")
            guard let mode = MonochromeSource(rawValue: name) else {
                fail("--mono: unknown mode '\(name)'")
            }
            o.monochrome = mode
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

var params = preset.resolved
var look = preset.look
// A development flag given on the command line beats the preset's, which is the
// only way to override it — every preset now carries development settings.
var raw = options.raw
if let presetRaw = preset.raw, options.raw == RawDevelopSettings() { raw = presetRaw }

// A dial given on the command line beats the preset's, and takes over the four
// controls it drives even on a preset whose numbers are otherwise literal.
let dialDefaults = LookSettings()
var dialGiven = false
if options.look.strength != dialDefaults.strength {
    look.strength = options.look.strength
    dialGiven = true
}
if options.look.magenta != dialDefaults.magenta {
    look.magenta = options.look.magenta
    dialGiven = true
}
if options.look.density != dialDefaults.density {
    look.density = options.look.density
    dialGiven = true
}
if preset.usesLook || dialGiven { params = look.applied(to: params) }

if options.monochrome != .off { params.monochrome = options.monochrome }
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
              + "strength \(String(format: "%.2f", look.strength))"
              + (options.preset.map { "  preset \($0)" } ?? ""))
    }
} catch {
    fail(error.localizedDescription)
}
