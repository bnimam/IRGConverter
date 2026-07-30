import CoreGraphics
import Foundation
import IRGConverterCore

/// Renders filmstrip thumbnails through the transform.
///
/// The strip shows results, not sources — a strip of near-identical grey-green
/// originals is useless for picking which photo to work on next. That means every
/// thumbnail is a real conversion, so this class exists to make them cheap:
///
/// - The decoded small source is cached per file, keyed by its RAW development.
///   Moving a Look slider then costs only the transform, not a re-decode.
/// - One serial queue and one processor. `AerochromeProcessor` holds mutable
///   scratch buffers, so concurrent use is not an option, and rebuilding it per
///   thumbnail would throw away the buffer allocations.
/// - Per-photo generation counters. Dragging a slider enqueues a render per step;
///   superseded ones are dropped instead of each being computed and discarded.
final class ThumbnailEngine {
    /// Long edge, in pixels. Rendered at 2× the on-screen size so the strip stays
    /// sharp on a Retina display.
    static let size = 220

    private let queue = DispatchQueue(label: "io.geospace.irgconverter.thumbs", qos: .utility)
    private let processor = AerochromeProcessor()

    /// Decoded sources, keyed by photo id. Holding these costs about 0.3 MB each
    /// at 220 px, so a hundred-photo strip is still well under a hundred megabytes.
    private var sources: [UUID: (raw: RawDevelopSettings, image: CGImage)] = [:]
    private var generations: [UUID: UInt64] = [:]
    private let lock = NSLock()

    /// Render `id`'s thumbnail and call back on the main queue.
    ///
    /// Superseded requests for the same id never call back at all, so the caller
    /// does not have to guard against a stale thumbnail arriving late.
    /// - Parameter nativeLongEdge: the file's own long edge, so the processor knows
    ///   how far down this render is scaled. Only sharpening depends on it, and at
    ///   220 px it works out below the radius floor and is skipped — a thumbnail is
    ///   for picking the photo, not for judging its detail.
    func render(id: UUID, url: URL, edit: PhotoEdit, nativeLongEdge: Int?,
                completion: @escaping (UUID, CGImage?) -> Void) {
        let requested = bump(id)

        queue.async {
            guard self.isCurrent(id, requested) else { return }

            let source: CGImage
            if let cached = self.cachedSource(id, raw: edit.raw) {
                source = cached
            } else {
                guard let decoded = try? ImageIOSupport.load(url: url, raw: edit.raw,
                                                             maxDimension: Self.size)
                else {
                    DispatchQueue.main.async { completion(id, nil) }
                    return
                }
                let scaled = ImageIOSupport.downsample(image: decoded, maxDimension: Self.size)
                self.store(id, raw: edit.raw, image: scaled)
                source = scaled
            }

            // Re-check after the decode: a drag can have moved on while a RAW was
            // being demosaiced.
            guard self.isCurrent(id, requested) else { return }
            let native = nativeLongEdge ?? max(source.width, source.height)
            self.processor.renderScale = native > 0
                ? Float(max(source.width, source.height)) / Float(native)
                : 1
            let image = self.processor.process(cgImage: source, params: edit.params)
            guard self.isCurrent(id, requested) else { return }
            DispatchQueue.main.async { completion(id, image) }
        }
    }

    /// Drop a removed photo's cached source.
    func forget(_ id: UUID) {
        lock.lock()
        sources[id] = nil
        generations[id] = (generations[id] ?? 0) + 1
        lock.unlock()
    }

    private func bump(_ id: UUID) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let next = (generations[id] ?? 0) + 1
        generations[id] = next
        return next
    }

    private func isCurrent(_ id: UUID, _ value: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generations[id] == value
    }

    private func cachedSource(_ id: UUID, raw: RawDevelopSettings) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = sources[id], entry.raw == raw else { return nil }
        return entry.image
    }

    private func store(_ id: UUID, raw: RawDevelopSettings, image: CGImage) {
        lock.lock()
        sources[id] = (raw, image)
        lock.unlock()
    }
}
