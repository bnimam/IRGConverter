import SwiftUI
import IRGConverterCore

/// Draggable tone-curve editor.
///
/// Drag a point to move it, click empty space to add one, double-click a point
/// to delete it. The two endpoints can only move vertically, so the curve always
/// spans the full input range.
struct CurvesEditor: View {
    @Binding var curves: ToneCurves
    /// What the reset buttons revert to: the curves from whatever was last
    /// applied wholesale, so a preset that ships a curve is restorable.
    let baseline: ToneCurves
    /// Histogram of the current result, drawn behind the curve for reference.
    let histogram: Histogram?

    @State private var channel: Channel = .master
    @State private var draggingIndex: Int?

    enum Channel: String, CaseIterable, Identifiable {
        case master, red, green, blue
        var id: String { rawValue }

        var label: String {
            switch self {
            case .master: return "RGB"
            case .red: return "R"
            case .green: return "G"
            case .blue: return "B"
            }
        }

        var color: Color {
            switch self {
            case .master: return .primary
            case .red: return .red
            case .green: return .green
            case .blue: return .blue
            }
        }

        var keyPath: WritableKeyPath<ToneCurves, ToneCurve> {
            switch self {
            case .master: return \.master
            case .red: return \.red
            case .green: return \.green
            case .blue: return \.blue
            }
        }

        var histogramKeyPath: KeyPath<Histogram, [Int]>? {
            switch self {
            case .master: return \.luma
            case .red: return \.red
            case .green: return \.green
            case .blue: return \.blue
            }
        }
    }

    private static let side: CGFloat = 220
    private static let hitRadius: CGFloat = 14

    private var curve: ToneCurve {
        get { curves[keyPath: channel.keyPath] }
        nonmutating set { curves[keyPath: channel.keyPath] = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $channel) {
                ForEach(Channel.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            canvas

            HStack {
                Button("Reset Channel") { curve = baseline[keyPath: channel.keyPath] }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(curve == baseline[keyPath: channel.keyPath])
                Button("Reset All") { curves = baseline }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(curves == baseline)
            }

            Text("Drag to move · click to add · double-click a point to remove")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canvas: some View {
        let points = curve.points.sorted { $0.x < $1.x }
        return Canvas { context, size in
            // Histogram behind the curve, so an adjustment can be aimed at the
            // tones that actually exist in the frame.
            if let histogram, let path = channel.histogramKeyPath {
                let bins = histogram[keyPath: path]
                var shape = Path()
                shape.move(to: CGPoint(x: 0, y: size.height))
                let step = size.width / CGFloat(max(bins.count - 1, 1))
                for (i, count) in bins.enumerated() {
                    let normalized = min(Double(count) / Double(histogram.peak), 1)
                    let y = size.height - CGFloat(pow(normalized, 0.45)) * size.height
                    shape.addLine(to: CGPoint(x: CGFloat(i) * step, y: y))
                }
                shape.addLine(to: CGPoint(x: size.width, y: size.height))
                shape.closeSubpath()
                context.fill(shape, with: .color(.gray.opacity(0.22)))
            }

            var grid = Path()
            for i in 1..<4 {
                let f = CGFloat(i) / 4
                grid.move(to: CGPoint(x: f * size.width, y: 0))
                grid.addLine(to: CGPoint(x: f * size.width, y: size.height))
                grid.move(to: CGPoint(x: 0, y: f * size.height))
                grid.addLine(to: CGPoint(x: size.width, y: f * size.height))
            }
            context.stroke(grid, with: .color(.gray.opacity(0.25)), lineWidth: 0.5)

            var diagonal = Path()
            diagonal.move(to: CGPoint(x: 0, y: size.height))
            diagonal.addLine(to: CGPoint(x: size.width, y: 0))
            context.stroke(diagonal, with: .color(.gray.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

            // The curve itself, sampled through the same evaluator the processor
            // uses, so what is drawn is what is applied.
            var line = Path()
            let samples = 96
            for i in 0...samples {
                let x = Float(i) / Float(samples)
                let p = point(x: x, y: curve.value(at: x), in: size)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            context.stroke(line, with: .color(channel.color), lineWidth: 1.6)

            for p in points {
                let center = point(x: p.x, y: p.y, in: size)
                let dot = Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4,
                                                 width: 8, height: 8))
                context.fill(dot, with: .color(channel.color))
                context.stroke(dot, with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { event in removePoint(near: event.location) }
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let size = CGSize(width: Self.side, height: Self.side)
                if draggingIndex == nil {
                    draggingIndex = index(near: value.startLocation)
                        ?? addPoint(at: value.startLocation, in: size)
                }
                guard let index = draggingIndex else { return }
                move(index: index, to: value.location, in: size)
            }
            .onEnded { _ in draggingIndex = nil }
    }

    // MARK: - Geometry

    private func point(x: Float, y: Float, in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) * size.width, y: (1 - CGFloat(y)) * size.height)
    }

    private func index(near location: CGPoint) -> Int? {
        let size = CGSize(width: Self.side, height: Self.side)
        let sorted = curve.points.sorted { $0.x < $1.x }
        var best: (index: Int, distance: CGFloat)?
        for (i, p) in sorted.enumerated() {
            let center = point(x: p.x, y: p.y, in: size)
            let d = hypot(center.x - location.x, center.y - location.y)
            if d <= Self.hitRadius, best == nil || d < best!.distance {
                best = (i, d)
            }
        }
        guard let best else { return nil }
        curve = ToneCurve(points: sorted)
        return best.index
    }

    private func addPoint(at location: CGPoint, in size: CGSize) -> Int? {
        let x = Float(min(max(location.x / size.width, 0), 1))
        let y = Float(min(max(1 - location.y / size.height, 0), 1))
        // Never add a second point on top of an endpoint; that would make the
        // curve ambiguous at the edge.
        guard x > 0.02, x < 0.98 else { return nil }
        var points = curve.points.sorted { $0.x < $1.x }
        let insertion = points.firstIndex { $0.x > x } ?? points.count
        points.insert(CurvePoint(x: x, y: y), at: insertion)
        curve = ToneCurve(points: points)
        return insertion
    }

    private func move(index: Int, to location: CGPoint, in size: CGSize) {
        var points = curve.points.sorted { $0.x < $1.x }
        guard points.indices.contains(index) else { return }
        let y = Float(min(max(1 - location.y / size.height, 0), 1))

        if index == 0 || index == points.count - 1 {
            // Endpoints stay pinned to x = 0 and x = 1.
            points[index] = CurvePoint(x: points[index].x, y: y)
        } else {
            // Keep interior points strictly between their neighbours, so the
            // curve stays a function of x.
            let lower = points[index - 1].x + 0.01
            let upper = points[index + 1].x - 0.01
            let x = Float(min(max(location.x / size.width, 0), 1))
            points[index] = CurvePoint(x: min(max(x, lower), max(lower, upper)), y: y)
        }
        curve = ToneCurve(points: points)
    }

    private func removePoint(near location: CGPoint) {
        let size = CGSize(width: Self.side, height: Self.side)
        var points = curve.points.sorted { $0.x < $1.x }
        for (i, p) in points.enumerated() {
            let center = point(x: p.x, y: p.y, in: size)
            guard hypot(center.x - location.x, center.y - location.y) <= Self.hitRadius else {
                continue
            }
            // Endpoints are structural; only interior points can go.
            guard i > 0, i < points.count - 1 else { return }
            points.remove(at: i)
            curve = ToneCurve(points: points)
            return
        }
    }
}
