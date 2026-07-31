import CoreGraphics
import SwiftUI
import IRGConverterCore

/// Renders one small tile per preset, from the photo already on screen.
///
/// Cheap because it prepares the processor **once** and then runs each preset's
/// parameters over the same prepared planes: the expensive part of a conversion is
/// the decode and the buffer setup, not the transform. Measured on the sample frame
/// at tile size, the whole set of presets costs about as much as one thumbnail.
final class PresetPreviewEngine {
    /// Long edge of a tile render, in pixels. 2× the on-screen size, for Retina.
    static let size = 260

    private let queue = DispatchQueue(label: "io.geospace.irgconverter.presettiles",
                                      qos: .userInitiated)
    private let processor = AerochromeProcessor()
    private let lock = NSLock()
    private var generation: UInt64 = 0

    /// Render `presets` against `source`, calling `tile` on the main queue as each
    /// one lands so the grid fills in rather than appearing all at once.
    ///
    /// A second call supersedes the first: tiles from the older run stop arriving.
    func render(source: CGImage,
                presets: [AerochromePreset],
                nativeLongEdge: Int?,
                tile: @escaping (String, CGImage) -> Void,
                finished: @escaping () -> Void) {
        let requested = bump()

        queue.async {
            guard self.isCurrent(requested) else { return }
            let small = ImageIOSupport.downsample(image: source, maxDimension: Self.size)
            // Same reasoning as the filmstrip: a radius given in full-resolution
            // pixels cannot show at tile size, so tell the processor how far down
            // this render is and let it skip the unsharp mask.
            let native = nativeLongEdge ?? max(small.width, small.height)
            self.processor.renderScale = native > 0
                ? Float(max(small.width, small.height)) / Float(native)
                : 1
            guard self.processor.prepare(cgImage: small) else {
                DispatchQueue.main.async { finished() }
                return
            }

            for preset in presets {
                guard self.isCurrent(requested) else { return }
                guard let image = self.processor.process(params: preset.params) else { continue }
                let name = preset.name
                DispatchQueue.main.async {
                    guard self.isCurrent(requested) else { return }
                    tile(name, image)
                }
            }
            DispatchQueue.main.async {
                guard self.isCurrent(requested) else { return }
                finished()
            }
        }
    }

    @discardableResult
    private func bump() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    private func isCurrent(_ value: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == generation
    }
}

/// Every preset as a tile of the current photo, for picking one by eye.
///
/// The preset menu names looks; this shows them. Which matters here more than in
/// most editors, because what a preset does depends entirely on the frame — how
/// much infrared a given set of subtractions leaves behind is a property of the
/// vegetation in front of the camera, not of the numbers alone.
struct PresetTilesView: View {
    let presets: [AerochromePreset]
    let userPresetNames: Set<String>
    /// Rendered tiles, keyed by preset name. Fills in as they arrive.
    let tiles: [String: CGImage]
    /// The preset the photo was started from, drawn with an accent border.
    let activeName: String?
    let isRendering: Bool
    let onSelect: (AerochromePreset) -> Void
    let onClose: () -> Void

    private let tileWidth: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Presets").font(.headline)
                if isRendering {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 12)],
                          spacing: 12) {
                    ForEach(presets) { preset in
                        tile(preset)
                    }
                }
                .padding(12)
            }

            Divider()

            Text("Rendered from the photo on screen, at the current RAW development. "
                 + "Click one to apply it — sharpening and development settings a "
                 + "preset carries are applied then, not shown here.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
        .frame(minWidth: 560, idealWidth: 700, minHeight: 420, idealHeight: 560)
    }

    private func tile(_ preset: AerochromePreset) -> some View {
        let isActive = preset.name == activeName

        return Button {
            onSelect(preset)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .windowBackgroundColor))
                    if let image = tiles[preset.name] {
                        Image(image, scale: 1.0, label: Text(preset.name))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: tileWidth * 0.72)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isActive ? Color.accentColor
                                               : Color(nsColor: .separatorColor),
                                      lineWidth: isActive ? 2.5 : 1)
                )

                HStack(spacing: 4) {
                    Text(preset.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if userPresetNames.contains(preset.name) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .help("One of yours")
                    }
                }
                .foregroundColor(isActive ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help(preset.notes ?? preset.name)
    }
}
