import Foundation

struct HandIdentityTracker {
    private var previous: [Int: (x: Double, y: Double)] = [:]
    private var velocity: [Int: (x: Double, y: Double)] = [:]

    mutating func assign(_ detections: [HandFeatures]) -> [TrackedHand] {
        let visible = Array(detections.prefix(2))
        guard !visible.isEmpty else {
            previous.removeAll()
            velocity.removeAll()
            return []
        }
        let sorted = visible.sorted { $0.palmX < $1.palmX }
        let assigned: [TrackedHand]
        if sorted.count == 1 {
            let id = previous.keys.min { distance(predicted($0), sorted[0]) < distance(predicted($1), sorted[0]) } ?? 0
            assigned = [TrackedHand(id: id, features: sorted[0])]
        } else if previous[0] != nil && previous[1] != nil {
            let left = predicted(0), right = predicted(1)
            let direct = distance(left, sorted[0]) + distance(right, sorted[1])
            let crossed = distance(left, sorted[1]) + distance(right, sorted[0])
            assigned = crossed < direct
                ? [TrackedHand(id: 0, features: sorted[1]), TrackedHand(id: 1, features: sorted[0])]
                : [TrackedHand(id: 0, features: sorted[0]), TrackedHand(id: 1, features: sorted[1])]
        } else if let oldID = previous.keys.first {
            let old = predicted(oldID)
            let firstIsOld = distance(old, sorted[0]) <= distance(old, sorted[1])
            assigned = firstIsOld
                ? [TrackedHand(id: oldID, features: sorted[0]), TrackedHand(id: 1 - oldID, features: sorted[1])]
                : [TrackedHand(id: oldID, features: sorted[1]), TrackedHand(id: 1 - oldID, features: sorted[0])]
        } else {
            assigned = [TrackedHand(id: 0, features: sorted[0]), TrackedHand(id: 1, features: sorted[1])]
        }
        var newVelocity: [Int: (x: Double, y: Double)] = [:]
        for hand in assigned {
            if let old = previous[hand.id] {
                newVelocity[hand.id] = (hand.features.palmX - old.x, hand.features.palmY - old.y)
            }
        }
        velocity = newVelocity
        previous = Dictionary(uniqueKeysWithValues: assigned.map { ($0.id, ($0.features.palmX, $0.features.palmY)) })
        return assigned.sorted { $0.id < $1.id }
    }

    private func predicted(_ id: Int) -> (x: Double, y: Double) {
        let point = previous[id]!
        let movement = velocity[id] ?? (0, 0)
        return (point.x + movement.x, point.y + movement.y)
    }

    private func distance(_ point: (x: Double, y: Double), _ hand: HandFeatures) -> Double {
        hypot(point.x - hand.palmX, point.y - hand.palmY)
    }
}
