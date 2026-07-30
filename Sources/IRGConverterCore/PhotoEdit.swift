import Foundation

/// Everything that turns one file into one result: the transform parameters, the
/// Look dials that drove them, and how the RAW was developed.
///
/// This is what a batch copies between photos, and what each photo in the
/// filmstrip owns its own copy of. The three parts are stored rather than
/// re-derived because `params` can legitimately disagree with `look` — moving a
/// group slider by hand detaches it, and a copy has to carry what the user can
/// actually see, not what the dials would have produced.
public struct PhotoEdit: Equatable, Codable, Sendable {
    public var params: AerochromeParams
    public var look: LookSettings
    public var raw: RawDevelopSettings

    public init(params: AerochromeParams = AerochromeParams(),
                look: LookSettings = LookSettings(),
                raw: RawDevelopSettings = RawDevelopSettings()) {
        self.params = params
        self.look = look
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        params = (try? c.decode(AerochromeParams.self, forKey: .params)) ?? AerochromeParams()
        look = (try? c.decode(LookSettings.self, forKey: .look)) ?? LookSettings()
        raw = (try? c.decode(RawDevelopSettings.self, forKey: .raw)) ?? RawDevelopSettings()
    }

    public init(preset: AerochromePreset, raw fallback: RawDevelopSettings) {
        self.init(params: preset.resolved, look: preset.look, raw: preset.raw ?? fallback)
    }

    /// What a photo starts as: the default preset, resolved.
    ///
    /// Not `PhotoEdit()` — that is the bare struct defaults, which is the
    /// calibration rather than the shipped look. Everything that asks "has this
    /// photo been edited" compares against this.
    public static let `default` = PhotoEdit(preset: AerochromePresetStore.defaultPreset,
                                            raw: RawDevelopSettings())
}

/// Which parts of a copied edit a paste writes.
///
/// The four groups partition `PhotoEdit` exactly — every stored value belongs to
/// one of them and none to two — so "paste everything" and "paste each group in
/// turn" produce the same result. That is what `IRGConverterCheck` asserts.
///
/// `look` deliberately owns the four transform values the dials drive
/// (`gammaBy`, both subtractions, `overallGamma`) as well as the dials
/// themselves, and copies them verbatim instead of re-deriving them. A photo
/// whose IR gamma was nudged by hand would otherwise paste as something the
/// source photo never looked like.
public struct PasteOptions: Equatable, Codable, Sendable {
    /// Look dials, plus IR gamma, both IR subtractions and output gamma.
    public var look: Bool
    /// Source channel assignment, the two visible group curves, the output
    /// channel map and the black-and-white mode.
    public var channels: Bool
    /// Tone, colour and the curves from the Adjust tab.
    public var adjustments: Bool
    /// Balance, temperature, tint and headroom. Only meaningful for a RAW file;
    /// the caller decides whether the destination is one.
    public var rawDevelopment: Bool

    public init(look: Bool = true, channels: Bool = true,
                adjustments: Bool = true, rawDevelopment: Bool = true) {
        self.look = look
        self.channels = channels
        self.adjustments = adjustments
        self.rawDevelopment = rawDevelopment
    }

    public static let all = PasteOptions()

    public var isEmpty: Bool {
        !look && !channels && !adjustments && !rawDevelopment
    }

    /// Human-readable summary for the menu, e.g. "Look, tone".
    public var summary: String {
        if !isEmpty, look, channels, adjustments, rawDevelopment { return "everything" }
        if isEmpty { return "nothing" }
        var parts: [String] = []
        if look { parts.append("Look") }
        if channels { parts.append("channels") }
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

        if look {
            out.look = source.look
            out.params.gammaBy = source.params.gammaBy
            out.params.subtractIRRed = source.params.subtractIRRed
            out.params.subtractIRGreen = source.params.subtractIRGreen
            out.params.overallGamma = source.params.overallGamma
        }

        if channels {
            out.params.sourceIR = source.params.sourceIR
            out.params.sourceVisibleRed = source.params.sourceVisibleRed
            out.params.sourceVisibleGreen = source.params.sourceVisibleGreen
            out.params.gammaRx = source.params.gammaRx
            out.params.gammaGx = source.params.gammaGx
            out.params.outputMapR = source.params.outputMapR
            out.params.outputMapG = source.params.outputMapG
            out.params.outputMapB = source.params.outputMapB
            out.params.monochrome = source.params.monochrome
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
