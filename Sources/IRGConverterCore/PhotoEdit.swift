import Foundation

/// Everything that turns one file into one result: the transform parameters and
/// how the RAW was developed.
///
/// This is what a batch copies between photos, and what each photo in the
/// filmstrip owns its own copy of.
public struct PhotoEdit: Equatable, Codable, Sendable {
    public var params: AerochromeParams
    public var raw: RawDevelopSettings

    public init(params: AerochromeParams = AerochromeParams(),
                raw: RawDevelopSettings = RawDevelopSettings()) {
        self.params = params
        self.raw = raw
    }

    /// Field-by-field with fallbacks, so an edit written by another build still
    /// loads. Files from the versions that carried a `look` object simply drop it —
    /// those builds stored `params` as the values actually on screen, so nothing is
    /// lost by ignoring the dials that produced them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        params = (try? c.decode(AerochromeParams.self, forKey: .params)) ?? AerochromeParams()
        raw = (try? c.decode(RawDevelopSettings.self, forKey: .raw)) ?? RawDevelopSettings()
    }

    public init(preset: AerochromePreset, raw fallback: RawDevelopSettings) {
        self.init(params: preset.params, raw: preset.raw ?? fallback)
    }

    /// What a photo starts as: the default preset.
    ///
    /// Not `PhotoEdit()` — that is the bare struct defaults, which is the
    /// calibration rather than the shipped look. Everything that asks "has this
    /// photo been edited" compares against this.
    public static let `default` = PhotoEdit(preset: AerochromePresetStore.defaultPreset,
                                            raw: RawDevelopSettings())
}

/// Which parts of a copied edit a paste writes.
///
/// The three groups partition `PhotoEdit` exactly — every stored value belongs to
/// one of them and none to two — so "paste everything" and "paste each group in
/// turn" produce the same result. That is what `IRGConverterCheck` asserts.
public struct PasteOptions: Equatable, Codable, Sendable {
    /// The whole Aerochrome transform: source channel roles, all four gammas, both
    /// subtractions and the output channel map.
    public var transform: Bool
    /// Tone, colour, curves and sharpening from the Adjust tab.
    public var adjustments: Bool
    /// Balance, temperature, tint and headroom. Only meaningful for a RAW file;
    /// the caller decides whether the destination is one.
    public var rawDevelopment: Bool

    public init(transform: Bool = true, adjustments: Bool = true,
                rawDevelopment: Bool = true) {
        self.transform = transform
        self.adjustments = adjustments
        self.rawDevelopment = rawDevelopment
    }

    public static let all = PasteOptions()

    public var isEmpty: Bool {
        !transform && !adjustments && !rawDevelopment
    }

    /// Human-readable summary for the menu, e.g. "transform, tone".
    public var summary: String {
        if transform, adjustments, rawDevelopment { return "everything" }
        if isEmpty { return "nothing" }
        var parts: [String] = []
        if transform { parts.append("transform") }
        if adjustments { parts.append("tone") }
        if rawDevelopment { parts.append("RAW") }
        return parts.joined(separator: ", ")
    }

    /// Copy the selected groups from `source` onto `destination`.
    ///
    /// `includeRaw` lets the caller suppress the development group for a
    /// destination that is not a RAW file, where those numbers would be stored
    /// but never used.
    public func apply(_ source: PhotoEdit, to destination: PhotoEdit,
                      includeRaw: Bool = true) -> PhotoEdit {
        var out = destination

        if transform {
            out.params.sourceIR = source.params.sourceIR
            out.params.sourceVisibleRed = source.params.sourceVisibleRed
            out.params.sourceVisibleGreen = source.params.sourceVisibleGreen
            out.params.gammaBy = source.params.gammaBy
            out.params.subtractIRRed = source.params.subtractIRRed
            out.params.gammaRx = source.params.gammaRx
            out.params.gammaGx = source.params.gammaGx
            out.params.subtractIRGreen = source.params.subtractIRGreen
            out.params.overallGamma = source.params.overallGamma
            out.params.outputMapR = source.params.outputMapR
            out.params.outputMapG = source.params.outputMapG
            out.params.outputMapB = source.params.outputMapB
        }

        if adjustments {
            out.params.adjustments = source.params.adjustments
        }

        if rawDevelopment, includeRaw {
            out.raw = source.raw
        }

        return out
    }
}

/// Where a batch export writes each file.
public enum BatchNaming {
    public static let suffix = "_aerochrome"

    /// Which folder a batch writes into.
    public enum Destination: Equatable, Sendable {
        /// One chosen folder for the whole batch.
        case folder(URL)
        /// Alongside each source file, which is where an editor handing work to
        /// another editor is expected to put it — Lightroom in particular then finds
        /// the result next to the master it came from.
        case besideOriginal

        public func directory(for source: URL) -> URL {
            switch self {
            case .folder(let url): return url
            case .besideOriginal: return source.deletingLastPathComponent()
            }
        }
    }

    /// `<directory>/<source name>_aerochrome.<ext>`, with `-2`, `-3`… appended
    /// until the name is free.
    ///
    /// Never overwrites: a batch is easy to run twice by accident, and the second
    /// run silently replacing the first one's output — possibly with different
    /// settings — is not recoverable. `exists` is injected so this is testable
    /// without touching the disk.
    public static func outputURL(for source: URL,
                                 in destination: Destination,
                                 format: ImageIOSupport.ExportFormat = .heic,
                                 exists: (URL) -> Bool) -> URL {
        let directory = destination.directory(for: source)
        let base = source.deletingPathExtension().lastPathComponent + suffix
        let ext = format.fileExtension

        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while exists(candidate) {
            candidate = directory
                .appendingPathComponent("\(base)-\(counter)")
                .appendingPathExtension(ext)
            counter += 1
            // A directory holding this many collisions means something else is
            // wrong; return the last candidate rather than spinning forever.
            if counter > 10_000 { break }
        }
        return candidate
    }
}
