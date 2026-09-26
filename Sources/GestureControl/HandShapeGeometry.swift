import Foundation

/// Dimensionless, palm-aligned coordinates and three bend angles per finger.
/// Angles describe rotation in the camera plane, not unobservable 3D rotation.
struct HandShapeGeometry {
    let joints: [Double]
    let angles: [Double]
    let angleMask: [Bool]
    let jointMask: [Bool]

    init?(landmarks: [HandLandmark], imageAspectRatio: Double) {
        guard imageAspectRatio.isFinite, imageAspectRatio > 0 else { return nil }
        var points: [Int: (x: Double, y: Double)] = [:]
        for point in landmarks where point.confidence >= 0.3 && point.confidence.isFinite
            && point.x.isFinite && point.y.isFinite {
            points[point.id] = (point.x * imageAspectRatio, point.y)
        }
        // Do not invent a joint by substituting its neighbour when Vision loses it.
        guard let wrist = points[0], let middle = points[9] else { return nil }
        let dx = middle.x - wrist.x, dy = middle.y - wrist.y
        let scale = hypot(dx, dy)
        guard scale > 0.000001 else { return nil }
        let axisX = dx / scale, axisY = dy / scale
        var normalized: [Double] = []
        var bends: [Double] = []
        var validAngles: [Bool] = []
        var validJoints: [Bool] = []
        for id in 1...20 {
            guard let point = points[id] else {
                normalized += [0, 0]
                validJoints += [false, false]
                continue
            }
            validJoints += [true, true]
            let x = (point.x - wrist.x) / scale, y = (point.y - wrist.y) / scale
            normalized += [x * axisY - y * axisX, x * axisX + y * axisY]
        }
        for finger in 0..<5 {
            let ids = [0] + Array((1 + finger * 4)...(4 + finger * 4))
            for joint in 1...3 {
                guard let a = points[ids[joint - 1]], let b = points[ids[joint]],
                      let c = points[ids[joint + 1]] else {
                    bends.append(0)
                    validAngles.append(false)
                    continue
                }
                let ux = b.x - a.x, uy = b.y - a.y
                let vx = c.x - b.x, vy = c.y - b.y
                let lengths = hypot(ux, uy) * hypot(vx, vy)
                guard lengths > 0.000000000001 else {
                    bends.append(0)
                    validAngles.append(false)
                    continue
                }
                validAngles.append(true)
                bends.append(acos(max(-1, min(1, (ux * vx + uy * vy) / lengths))) / .pi)
            }
        }
        guard validAngles.filter({ $0 }).count >= 9, validJoints.filter({ $0 }).count >= 24 else { return nil }
        joints = normalized
        angles = bends
        angleMask = validAngles
        jointMask = validJoints
    }
}

struct GestureDebounce {
    private var votes: [UUID?] = []

    mutating func reset() { votes.removeAll() }

    mutating func confirm(_ candidate: UUID?, required: Int = 5, window: Int = 7) -> Bool {
        votes.append(candidate)
        if votes.count > window { votes.removeFirst(votes.count - window) }
        guard let candidate else { return false }
        return votes.filter { $0 == candidate }.count >= required
    }
}
