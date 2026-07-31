import Foundation

/// A named set of settings.
///
/// A preset is a literal set of transform numbers plus, optionally, how to develop
/// a RAW file. Applying it puts exactly those numbers on the sliders — there is no
/// derivation in between, so what a preset does is what you can read off the panel.
public struct AerochromePreset: Equatable, Codable, Identifiable, Sendable {
    public var name: String
    public var params: AerochromeParams

    /// RAW development settings, applied only when the loaded file is RAW.
    /// Optional so presets written before this existed still load, and so a
    /// preset can deliberately leave development alone.
    public var raw: RawDevelopSettings?

    /// A one-line note shown in the UI. Optional.
    public var notes: String?

    public var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, params, raw, notes
    }

    public init(name: String,
                params: AerochromeParams = AerochromeParams(),
                raw: RawDevelopSettings? = nil,
                notes: String? = nil) {
        self.name = name
        self.params = params
        self.raw = raw
        self.notes = notes
    }

    /// Field-by-field with fallbacks, so a preset saved by an older or newer build
    /// still loads instead of failing outright.
    ///
    /// Files written by the versions that had Look dials carry a `look` object and a
    /// `usesLook` flag. Both are ignored: those builds stored `params` as the values
    /// actually on the sliders, so the numbers are already here and the dials that
    /// produced them are no longer a thing the app has.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        params = (try? c.decode(AerochromeParams.self, forKey: .params)) ?? AerochromeParams()
        raw = try? c.decode(RawDevelopSettings.self, forKey: .raw)
        notes = try? c.decode(String.self, forKey: .notes)
    }

    /// The parameters this preset produces. Its own, unmodified — kept as a property
    /// rather than removed so call sites read the same as they did when a preset
    /// could still derive its numbers from something else.
    public var resolved: AerochromeParams { params }
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

    /// The look every photo starts on, hand-tuned on a full-spectrum ORF.
    ///
    /// Every other built-in is this one with two or three numbers moved, so the set
    /// is a family rather than a collection of unrelated starting points — and what
    /// each sibling changes is written in its notes.
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
        params.adjustments.curves.master = sCurve
        return AerochromePreset(
            name: "Aerochrome Magenta",
            params: params,
            // Equal to the defaults, stated anyway so applying the preset puts
            // development back where the look was tuned.
            raw: RawDevelopSettings(),
            notes: "The default. Foliage leans magenta-pink rather than pure red."
        )
    }()

    /// The contrast curve the family shares: shadows down a little, highlights up.
    private static let sCurve = ToneCurve(points: [
        CurvePoint(x: 0, y: 0),
        CurvePoint(x: 0.16947798, y: 0.12618963),
        CurvePoint(x: 0.7665483, y: 0.92903054),
        CurvePoint(x: 1, y: 1),
    ])

    /// A denser version of that curve, for the one preset whose point is density.
    private static let deepCurve = ToneCurve(points: [
        CurvePoint(x: 0, y: 0),
        CurvePoint(x: 0.20, y: 0.10),
        CurvePoint(x: 0.78, y: 0.94),
        CurvePoint(x: 1, y: 1),
    ])

    /// Every measurement in the notes below is from the sample frame, comparing the
    /// sibling against the default: `IRGConverterCheck` asserts the direction of
    /// each one, so a preset cannot quietly stop doing what it says.
    private static let builtInPresets: [AerochromePreset] = {
        let base = defaultPreset.params

        func sibling(_ name: String, notes: String,
                     _ configure: (inout AerochromeParams) -> Void) -> AerochromePreset {
            var params = base
            configure(&params)
            return AerochromePreset(name: name, params: params,
                                    raw: RawDevelopSettings(), notes: notes)
        }

        return [
            defaultPreset,
            sibling("Aerochrome Red",
                    notes: "Purer red foliage. Takes more infrared out of the green "
                         + "group, which is what was keeping the blue output up and "
                         + "the leaves pink.") {
                $0.subtractIRGreen = 0.55
            },
            sibling("Aerochrome Bold",
                    notes: "Brighter, stronger separation. For flat light or weak "
                         + "vegetation. Raises the infrared curve and re-balances the "
                         + "red subtraction under it.") {
                $0.gammaBy = 1.55
                $0.subtractIRRed = 0.58
            },
            sibling("Aerochrome Subtle",
                    notes: "Restrained. A lower infrared curve and lighter "
                         + "subtractions keep more of the original tonality.") {
                $0.gammaBy = 1.02
                $0.subtractIRRed = 0.38
                $0.subtractIRGreen = 0.18
            },
            sibling("Aerochrome Deep",
                    notes: "Denser shadows and richer colour, from a lower output "
                         + "gamma and a steeper curve. Watch the shadows for clipping.") {
                $0.overallGamma = 2.05
                $0.adjustments.curves.master = deepCurve
            },
            sibling("Pre-swapped IRG",
                    notes: "For files already ordered infrared / red / green, so the "
                         + "red channel is read as infrared instead of blue.") {
                $0.sourceIR = 0
                $0.sourceVisibleRed = 1
                $0.sourceVisibleGreen = 2
            },
        ]
    }()
}
