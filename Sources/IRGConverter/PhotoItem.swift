import CoreGraphics
import Foundation
import IRGConverterCore

/// One file in the filmstrip, with its own edit.
///
/// Deliberately a value type held in an array on the view: the whole point of the
/// filmstrip is that photo B's settings do not move when photo A's do, and giving
/// each photo its own `PhotoEdit` copy is the cheapest way to guarantee that.
struct PhotoItem: Identifiable {
    let id = UUID()
    let url: URL
    /// Whether the RAW development controls apply to this file.
    let isRAW: Bool
    /// Read from metadata at add time, so the strip can show it without decoding.
    let pixelSize: PixelSize?

    /// The edit currently applied to this photo. Starts on the default preset.
    var edit = PhotoEdit.default
    /// What double-clicking a control on this photo reverts to, and its label.
    var baseline = PhotoEdit.default
    var baselineName: String? = AerochromePresetStore.default.name
    /// Preset label, cleared as soon as anything is edited by hand.
    var presetName: String? = AerochromePresetStore.default.name

    /// Filmstrip thumbnail, rendered through the transform so the strip shows the
    /// result rather than the source. Nil until the first render lands.
    var thumbnail: CGImage?
    var thumbnailFailed = false

    var exportState = ExportState.none

    var name: String { url.lastPathComponent }

    /// True when this photo's settings differ from the shipped default preset,
    /// which is what the strip badges as "edited".
    var isEdited: Bool { edit != PhotoEdit.default }

    init(url: URL, isRAW: Bool, pixelSize: PixelSize?, edit: PhotoEdit = .default) {
        self.url = url
        self.isRAW = isRAW
        self.pixelSize = pixelSize
        self.edit = edit
        self.baseline = edit
        // The preset label is only honest when the edit really is that preset.
        if edit != .default {
            self.baselineName = nil
            self.presetName = nil
        }
    }

    struct PixelSize: Equatable {
        var width: Int
        var height: Int
        var label: String { "\(width)×\(height)" }
    }

    enum ExportState: Equatable {
        case none
        case queued
        case running
        case done(URL)
        case failed(String)

        var isBusy: Bool { self == .queued || self == .running }
    }
}

extension Array where Element == PhotoItem {
    func index(of id: PhotoItem.ID?) -> Int? {
        guard let id else { return nil }
        return firstIndex { $0.id == id }
    }

    /// URLs already in the strip, so re-adding the same files does not duplicate
    /// them. Compared by standardized path — the open panel and a drag can hand
    /// back the same file spelled differently.
    var urlKeys: Set<String> {
        Set(map { $0.url.standardizedFileURL.path })
    }
}
