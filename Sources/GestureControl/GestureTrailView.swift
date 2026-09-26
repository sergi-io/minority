import SwiftUI

/// Only in-memory landmarks are drawn here; camera images are never retained.
struct GestureTrailView: View {
    let sequences: [[HandFeatures]]
    let selection: ClosedRange<Int>
    let mirrored: Bool
    let imageSize: CGSize

    var body: some View {
        Canvas { context, size in
            func point(_ x: Double, _ y: Double) -> CGPoint {
                let scale = min(size.width / imageSize.width, size.height / imageSize.height)
                let width = imageSize.width * scale, height = imageSize.height * scale
                return CGPoint(x: (size.width - width) / 2 + (mirrored ? x : 1 - x) * width,
                               y: (size.height - height) / 2 + (1 - y) * height)
            }
            for (hand, frames) in sequences.enumerated() where !frames.isEmpty {
                let color: Color = hand == 0 ? .cyan : .orange
                // Palm and five fingertips expose both travel and finger-only gestures.
                for joint in [-1, 4, 8, 12, 16, 20] {
                    for index in 1..<frames.count {
                        let previous = frames[index - 1], current = frames[index]
                        guard current.timestamp - previous.timestamp <= 0.35 else { continue }
                        func position(_ frame: HandFeatures) -> CGPoint? {
                            if joint == -1 { return point(frame.palmX, frame.palmY) }
                            return frame.landmarks.first { $0.id == joint }.map { point($0.x, $0.y) }
                        }
                        guard let a = position(previous), let b = position(current) else { continue }
                        var path = Path(); path.move(to: a); path.addLine(to: b)
                        let included = selection.contains(index - 1) && selection.contains(index)
                        context.stroke(path, with: .color(included ? color.opacity(joint == -1 ? 1 : 0.4) : .gray.opacity(0.2)),
                                       lineWidth: joint == -1 ? 3 : 1)
                    }
                }
                for (index, label) in [(selection.lowerBound, "Start"), (selection.upperBound, "End")] where frames.indices.contains(index) {
                    let frame = frames[index]
                    let positions = Dictionary(uniqueKeysWithValues: frame.landmarks.map { ($0.id, point($0.x, $0.y)) })
                    var skeleton = Path()
                    for (a, b) in HandSkeletonGeometry.edges {
                        if let start = positions[a], let end = positions[b] {
                            skeleton.move(to: start); skeleton.addLine(to: end)
                        }
                    }
                    context.stroke(skeleton, with: .color(color.opacity(label == "Start" ? 0.45 : 0.95)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: label == "Start" ? [4, 3] : []))
                    let palm = point(frame.palmX, frame.palmY)
                    context.fill(Path(ellipseIn: CGRect(x: palm.x - 5, y: palm.y - 5, width: 10, height: 10)), with: .color(color))
                    context.draw(Text("\(label) \(hand + 1)").font(.caption.bold()).foregroundColor(color),
                                 at: CGPoint(x: min(size.width - 28, max(28, palm.x)), y: min(size.height - 12, max(12, palm.y + (label == "Start" ? -18 : 18)))))
                }
            }
        }
        .frame(height: 250)
        .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Hand movement trail. Selected movement is colored; discarded movement is gray. Dashed hand is the start; solid hand is the end.")
    }
}
