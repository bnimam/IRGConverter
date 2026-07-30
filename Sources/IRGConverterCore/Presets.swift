import Foundation

/// A named set of settings.
///
/// A preset carries the three `LookSettings` dials plus everything the look does
/// not own — source channels, output map, black and white, photo edits. Applying it
/// computes the transform numbers from the dials, so a preset is reproducible and
/// its sliders always show the values in use.
public struct AerochromePreset: Equatable, Codable, Identifiable, Sendable {
    public var name: String
    public var params: AerochromeParams
    public var look: LookSettings
    /// Whether the look dials drive the transform, or `params` is taken verbatim.
    ///
    /// Almost every preset is look-driven, which is what makes it reproducible.
    /// The exception is a preset whose whole point is a specific set of numbers —
    /// the document's own starting values, say, which no combination of dials
    /// produces.
    public var usesLook: Bool = true

    /// RAW development settings, applied only when the loaded file is RAW.
    /// Optional so presets written before this existed still load, and so a
    /// preset can deliberately leave development alone.
    public var raw: RawDevelopSettings?

    /// A one-line note shown in the UI. Optional.
    public var notes: String?

    public var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, params, look, usesLook, raw, notes
        // Read-only, for files written before the look dials replaced the
        // measurement-based auto-tune.
        case legacyOptions = "options"
        case legacyGreenSubtractScale = "greenSubtractScale"
        case legacyOutputGamma = "outputGamma"
    }

    public init(name: String,
                params: AerochromeParams = AerochromeParams(),
                look: LookSettings = LookSettings(),
                usesLook: Bool = true,
                raw: RawDevelopSettings? = nil,
                notes: String? = nil) {
        self.name = name
        self.params = params
        self.look = look
        self.usesLook = usesLook
        self.raw = raw
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        params = (try? c.decode(AerochromeParams.self, forKey: .params)) ?? AerochromeParams()
        raw = try? c.decode(RawDevelopSettings.self, forKey: .raw)
        notes = try? c.decode(String.self, forKey: .notes)
        usesLook = (try? c.decode(Bool.self, forKey: .usesLook)) ?? true

        if let current = try? c.decode(LookSettings.self, forKey: .look) {
            look = current
        } else {
            // Files written against the measurement-based auto-tune stored an
            // `options` object with a `lookStrength`, and sometimes carried the
            // leans as their own fields. Map what maps; the rest was derived from
            // the image and cannot be recovered, so `params` stands in for it.
            var recovered = LookSettings()
            if let legacy = try? c.decode(LegacyOptions.self, forKey: .legacyOptions) {
                recovered.strength = legacy.lookStrength ?? recovered.strength
                if let green = legacy.greenSubtractionScale ?? (try? c.decode(
                    Float.self, forKey: .legacyGreenSubtractScale)) {
                    recovered.magenta = Self.magentaLean(fromScale: green)
                }
                if let gammaScale = legacy.outputGammaScale {
                    recovered.density = Self.densityLean(fromScale: gammaScale)
                }
            } else if let green = try? c.decode(Float.self, forKey: .legacyGreenSubtractScale) {
                recovered.magenta = Self.magentaLean(fromScale: green)
            }
            if let gamma = try? c.decode(Float.self, forKey: .legacyOutputGamma) {
                recovered.density = Self.densityLean(
                    fromScale: gamma / Float(AerochromeCalibration.overallGamma))
            }
            look = recovered
        }
    }

    /// The shape of the `options` object older files carried.
    private struct LegacyOptions: Decodable {
        var lookStrength: Float?
        var greenSubtractionScale: Float?
        var outputGammaScale: Float?
    }

    /// The old leans were multipliers; the new ones are signed and exponential.
    /// `scale = 4 ^ -magenta`, so invert it.
    private static func magentaLean(fromScale scale: Float) -> Float {
        guard scale > 0 else { return 1 }
        return min(max(-log(scale) / log(4) * -1, -1), 1) * -1
    }

    /// `scale = 2.2 ^ -density`.
    private static func densityLean(fromScale scale: Float) -> Float {
        guard scale > 0 else { return 0 }
        return min(max(-log(scale) / log(2.2), -1), 1)
    }

    /// Written without the legacy keys — they are read for compatibility but
    /// never emitted, so a file saved today has one place per setting.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(params, forKey: .params)
        try c.encode(look, forKey: .look)
        try c.encode(usesLook, forKey: .usesLook)
        try c.encodeIfPresent(raw, forKey: .raw)
        try c.encodeIfPresent(notes, forKey: .notes)
    }

    /// The parameters this preset produces: its own settings with the look dials
    /// applied over the transform controls.
    ///
    /// A pure function, so applying a preset and then re-applying its look is a
    /// no-op and every slider shows the value actually in use.
    public var resolved: AerochromeParams {
        usesLook ? look.applied(to: params) : params
    }
}

/// On-disk wrapper, so a file can hold one preset or a whole collection and
/// still be version-checked.
public struct AerochromePresetFile: Codable, Sendable {
    public static let currentVersion = 1

    public var formatVersion: Int
    public var presets: [AerochromePreset]

    public init(presets: [AerochromePreset]) {
        self.formatVersion = Self.currentVersion
        self.presets = presets
    }

    public init(from decoder: Decoder) throws {
        // Accept a wrapped collection, a bare array, or a single bare preset, so
        // hand-written and hand-edited files both work.
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let presets = try? c.decode([AerochromePreset].self, forKey: .presets) {
            formatVersion = (try? c.decode(Int.self, forKey: .formatVersion)) ?? Self.currentVersion
            self.presets = presets
            return
        }
        if let array = try? decoder.singleValueContainer().decode([AerochromePreset].self) {
            formatVersion = Self.currentVersion
            presets = array
            return
        }
        let single = try decoder.singleValueContainer().decode(AerochromePreset.self)
        formatVersion = Self.currentVersion
        presets = [single]
    }
}

public enum PresetError: LocalizedError {
    case emptyName
    case noPresetsInFile
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Preset name cannot be empty"
        case .noPresetsInFile: return "No presets found in that file"
        case .notFound(let name): return "No saved preset named “\(name)”"
        }
    }
}

/// Built-in looks plus the user's own, saved as individual JSON files.
public final class AerochromePresetStore {
    public static let fileExtension = "irgpreset"

    public private(set) var user: [AerochromePreset] = []

    /// Where the user's own presets live. Injectable so tests do not write into
    /// the real Application Support folder.
    public let directory: URL

    public var builtIn: [AerochromePreset] { Self.builtInPresets }
    public var all: [AerochromePreset] { builtIn + user }

    /// The preset every photo starts on. See `defaultPreset` below.
    public static var `default`: AerochromePreset { defaultPreset }

    /// `~/Library/Application Support/IRGConverter/Presets`
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("IRGConverter/Presets", isDirectory: true)
    }

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        reload()
    }

    public func preset(named name: String) -> AerochromePreset? {
        all.first { $0.name == name }
    }

    // MARK: - Disk

    public func reload() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else {
            user = []
            return
        }
        user = entries
            .filter { $0.pathExtension.lowercased() == Self.fileExtension }
            .compactMap { try? Self.decode(contentsOf: $0).first }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Write (or overwrite) a preset in the user's presets directory.
    @discardableResult
    public func save(_ preset: AerochromePreset) throws -> URL {
        let trimmed = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PresetError.emptyName }
        var stored = preset
        stored.name = trimmed

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.filename(for: trimmed))
        try Self.encode([stored]).write(to: url, options: .atomic)
        reload()
        return url
    }

    public func delete(named name: String) throws {
        guard user.contains(where: { $0.name == name }) else { throw PresetError.notFound(name) }
        let url = directory.appendingPathComponent(Self.filename(for: name))
        try FileManager.default.removeItem(at: url)
        reload()
    }

    /// Write presets to an arbitrary location, for sharing.
    public func export(_ presets: [AerochromePreset], to url: URL) throws {
        guard !presets.isEmpty else { throw PresetError.noPresetsInFile }
        try Self.encode(presets).write(to: url, options: .atomic)
    }

    /// Read presets from an arbitrary location and add them to the user's set.
    /// Names that already exist gain a numeric suffix rather than overwriting.
    @discardableResult
    public func importPresets(from url: URL) throws -> [AerochromePreset] {
        let incoming = try Self.decode(contentsOf: url)
        guard !incoming.isEmpty else { throw PresetError.noPresetsInFile }

        var added: [AerochromePreset] = []
        for var preset in incoming {
            preset.name = uniqueName(for: preset.name)
            try save(preset)
            added.append(preset)
        }
        return added
    }

    /// A name not already taken by a built-in or saved preset.
    public func uniqueName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        var candidate = base
        var suffix = 2
        while all.contains(where: { $0.name == candidate }) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    // MARK: - Coding

    private static func encode(_ presets: [AerochromePreset]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(AerochromePresetFile(presets: presets))
    }

    private static func decode(contentsOf url: URL) throws -> [AerochromePreset] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AerochromePresetFile.self, from: data).presets
    }

    private static func filename(for name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let safe = name.components(separatedBy: illegal).joined(separator: "-")
        return "\(safe.isEmpty ? "preset" : safe).\(fileExtension)"
    }

    // MARK: - Built-ins

    /// The one preset the app ships with, and what a newly added photo starts on.
    ///
    /// Hand-tuned numbers, so `usesLook` is **false**: no combination of the three
    /// Look dials produces them — strength 0.5 puts IR gamma at the calibrated 2.15,
    /// not 1.13, and back-solving strength from that gamma then gives a red
    /// subtraction of 0.16 against the 0.50 wanted here. With `usesLook` true,
    /// `resolved` would quietly overwrite IR gamma, both subtractions and output
    /// gamma with the calibration's values, and the preset would not look like the
    /// picture it came from. The Look dials still work from here; moving one takes
    /// those four controls over, which is what the panel already says it does.
    public static let defaultPreset: AerochromePreset = {
        var params = AerochromeParams()
        params.sourceIR = 2
        params.sourceVisibleRed = 0
        params.sourceVisibleGreen = 1
        params.gammaBy = 1.1307921
        params.subtractIRRed = 0.4981573
        params.gammaRx = 0.46205422
        params.gammaGx = 1.2072839
        params.subtractIRGreen = 0.25263247
        params.overallGamma = 2.627884
        params.outputMapR = 2
        params.outputMapG = 0
        params.outputMapB = 1
        // An S-curve on the master: shadows down a little, highlights up, which is
        // where the contrast in this look comes from.
        params.adjustments.curves.master = ToneCurve(points: [
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.16947798, y: 0.12618963),
            CurvePoint(x: 0.7665483, y: 0.92903054),
            CurvePoint(x: 1, y: 1),
        ])

        return AerochromePreset(
            name: "Aerochrome Magenta",
            params: params,
            look: LookSettings(strength: 0.5),
            usesLook: false,
            // Equal to the defaults, stated anyway so applying the preset puts
            // development back where the look was tuned.
            raw: RawDevelopSettings(),
            notes: "Leaves lean magenta-pink rather than pure red. Hand-tuned, so "
                 + "its transform numbers are taken as written — moving a Look dial "
                 + "takes four of them over."
        )
    }()

    private static let builtInPresets: [AerochromePreset] = [defaultPreset]
}
