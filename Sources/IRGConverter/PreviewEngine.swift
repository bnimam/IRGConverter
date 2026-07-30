import CoreGraphics
import Foundation
import IRGConverterCore

/// Owns the preview-resolution processor and serializes access to it.
///
/// `AerochromeProcessor` keeps mutable scratch buffers, so every call has to be
/// funnelled through one queue. Renders are also coalesced: while the user drags
/// a slider, queued-but-superseded renders are dropped instead of each being
/// computed and thrown away.
final class PreviewEngine {
    private let processor = AerochromeProcessor()
    private let queue = DispatchQueue(label: "io.geospace.irgconverter.preview", qos: .userInitiated)
    private let lock = NSLock()
    private var generation: UInt64 = 0

    /// - Parameter scale: how much smaller this image is than the file it came
    ///   from, so a sharpening radius given in full-resolution pixels means the
    ///   same thing here. 1 when the preview is full size.
    func prepare(image: CGImage, scale: Float, completion: @escaping (Bool) -> Void) {
        bumpGeneration()
        queue.async {
            self.processor.renderScale = scale
            let ok = self.processor.prepare(cgImage: image)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func render(params: AerochromeParams,
                aids: ViewingAids,
                completion: @escaping (CGImage?, Histogram?) -> Void) {
        let requested = bumpGeneration()
        queue.async {
            guard self.isCurrent(requested) else { return }
            let output = self.processor.processWithHistogram(params: params, aids: aids)
            DispatchQueue.main.async { completion(output?.image, output?.histogram) }
        }
    }

    @discardableResult
    private func bumpGeneration() -> UInt64 {
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
