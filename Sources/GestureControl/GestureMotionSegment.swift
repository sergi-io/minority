import Foundation

/// Palm-driven gestures are segmented using palm motion, so noisy fingers during
/// the idle lead-in/tail cannot turn a short swipe into a five-second template.
enum GestureMotionSegment {
    static func activePalmIndices(_ sequences: [[HandFeatures]]) -> [Int]? {
        let moving = sequences.filter { frames in
            guard let first = frames.first else { return false }
            return frames.contains { hypot($0.palmX - first.palmX, $0.palmY - first.palmY) >= 0.09 }
        }
        guard !moving.isEmpty, let count = moving.first?.count, count > 3 else { return nil }
        let smoothed = moving.map { frames in
            frames.indices.map { index -> (x: Double, y: Double) in
                let window = frames[max(0, index - 2)...min(frames.count - 1, index + 2)]
                return (window.reduce(0) { $0 + $1.palmX } / Double(window.count),
                        window.reduce(0) { $0 + $1.palmY } / Double(window.count))
            }
        }
        return (3..<count).filter { index in
            smoothed.contains { points in
                hypot(points[index].x - points[index - 3].x, points[index].y - points[index - 3].y) >= 0.012
            }
        }
    }
}
