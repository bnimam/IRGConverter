import Foundation
import IRGConverterCore

/// Exports a list of photos at full resolution, one after another.
///
/// Sequential on purpose. Each file is re-developed from the original at native
/// size and the processor keeps a dozen float planes of scratch, so a 20-megapixel
/// frame costs on the order of a gigabyte while it is being converted. Two at once
/// buys little on a memory-bound job and risks swapping; three would be reckless.
final class BatchExporter {
    struct Job {
        let id: UUID
        let url: URL
        let edit: PhotoEdit
    }

    struct Progress {
        var completed: Int
        var failed: Int
        var total: Int
        /// File currently being converted.
        var current: String?

        var fraction: Double {
            total == 0 ? 0 : Double(completed + failed) / Double(total)
        }
    }

    private let queue = DispatchQueue(label: "io.geospace.irgconverter.batch", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false

    /// Start the batch. All callbacks arrive on the main queue.
    ///
    /// - Parameters:
    ///   - itemStarted: fired as each file begins, for the strip's badge.
    ///   - itemFinished: destination URL, or the failure for that one file. A
    ///     failure never stops the batch — one unreadable file should not cost the
    ///     other ninety-nine.
    ///   - progress: fired after every file.
    ///   - finished: `cancelled` says whether the run was stopped early.
    func run(jobs: [Job],
             into destination: BatchNaming.Destination,
             format: ImageIOSupport.ExportFormat,
             itemStarted: @escaping (UUID) -> Void,
             itemFinished: @escaping (UUID, Result<URL, Error>) -> Void,
             progress: @escaping (Progress) -> Void,
             finished: @escaping (Progress, Bool, [URL]) -> Void) {
        guard !jobs.isEmpty else { return }

        lock.lock()
        cancelled = false
        lock.unlock()

        queue.async {
            // One processor for the whole batch: `prepare` resizes its buffers per
            // file, so this reuses the allocation instead of churning a gigabyte
            // per photo. Scoped to this closure so it is released at the end.
            let processor = AerochromeProcessor()
            var state = Progress(completed: 0, failed: 0, total: jobs.count, current: nil)
            var stopped = false
            var written: [URL] = []

            for job in jobs {
                if self.isCancelled { stopped = true; break }

                state.current = job.url.lastPathComponent
                let snapshot = state
                DispatchQueue.main.async {
                    itemStarted(job.id)
                    progress(snapshot)
                }

                let result: Result<URL, Error>
                do {
                    let output = BatchNaming.outputURL(
                        for: job.url, in: destination, format: format,
                        exists: { FileManager.default.fileExists(atPath: $0.path) }
                    )
                    let source = try ImageIOSupport.load(url: job.url, raw: job.edit.raw)
                    guard processor.prepare(cgImage: source),
                          let rendered = processor.render16(params: job.edit.params)
                    else { throw ImageWriteError.encodingFailed }
                    try ImageIOSupport.write(rendered, to: output, format: format)
                    result = .success(output)
                } catch {
                    result = .failure(error)
                }

                switch result {
                case .success(let url):
                    state.completed += 1
                    written.append(url)
                case .failure:
                    state.failed += 1
                }
                let done = state
                DispatchQueue.main.async {
                    itemFinished(job.id, result)
                    progress(done)
                }
            }

            state.current = nil
            let final = state
            let files = written
            DispatchQueue.main.async { finished(final, stopped, files) }
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
