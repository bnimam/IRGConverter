import SwiftUI
import IRGConverterCore

/// Overlaid RGB histogram of the rendered result.
///
/// Bins are plotted on a mild power curve rather than linearly. A false-colour
/// render puts most of its pixels in a few narrow peaks — vegetation piles up in
/// the red channel — and a linear plot reduces everything else to an invisible
/// line along the axis.
struct HistogramView: View {
    let histogram: Histogram?

    private static let channels: [(KeyPath<Histogram, [Int]>, Color)] = [
        (\.red, .red), (\.green, .green), (\.blue, .blue),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                if let histogram {
                    ForEach(Array(Self.channels.enumerated()), id: \.offset) { _, channel in
                        Canvas { context, size in
                            let path = Self.path(
                                bins: histogram[keyPath: channel.0],
                                peak: histogram.peak,
                                size: size
                            )
                            context.fill(path, with: .color(channel.1.opacity(0.55)))
                        }
                        .blendMode(.screen)
                    }
                } else {
                    Text("No image")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 240, height: 84)
            .background(.black.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if let histogram {
                HStack(spacing: 8) {
                    clipLabel("shadow", histogram.clippedShadows)
                    clipLabel("highlight", histogram.clippedHighlights)
                }
            }
        }
        .padding(8)
    }

    private func clipLabel(_ name: String, _ fraction: Double) -> some View {
        let percent = fraction * 100
        return Text("\(name) clip \(String(format: percent >= 0.1 ? "%.1f%%" : "%.2f%%", percent))")
            .font(.caption2.monospaced())
            // Only call it out once enough pixels are actually pinned to matter.
            .foregroundColor(percent >= 1 ? .orange : .secondary)
    }

    private static func path(bins: [Int], peak: Int, size: CGSize) -> Path {
        var path = Path()
        guard !bins.isEmpty, peak > 0 else { return path }
        let step = size.width / CGFloat(bins.count - 1)
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, count) in bins.enumerated() {
            let normalized = min(Double(count) / Double(peak), 1)
            let scaled = pow(normalized, 0.45)
            let y = size.height - CGFloat(scaled) * size.height
            path.addLine(to: CGPoint(x: CGFloat(i) * step, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}
