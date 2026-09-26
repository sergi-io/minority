import Foundation

enum HandPose: String, Codable { case open, closed, other }

struct HandLandmark: Identifiable, Equatable {
    let id: Int
    let x: Double
    let y: Double
    let confidence: Double
}

struct HandFeatures {
    let timestamp: TimeInterval
    let palmX: Double
    let palmY: Double
    let confidence: Double
    let pose: HandPose
    let fingerExtensions: [Double]
    let thumbExtension: Double
    let jointShape: [Double]
    let angleMask: [Bool]
    let jointMask: [Bool]
    let jointAngles: [Double]
    let normalizedJoints: [Double]
    let landmarks: [HandLandmark]

    init(timestamp: TimeInterval, palmX: Double, palmY: Double, confidence: Double,
         pose: HandPose, fingerExtensions: [Double], thumbExtension: Double = 0.5,
         jointShape: [Double] = [], landmarks: [HandLandmark] = [],
         jointAngles: [Double] = [], normalizedJoints: [Double] = [],
         angleMask: [Bool] = [], jointMask: [Bool] = []) {
        self.timestamp = timestamp
        self.palmX = palmX
        self.palmY = palmY
        self.confidence = confidence
        self.pose = pose
        self.fingerExtensions = fingerExtensions
        self.thumbExtension = thumbExtension
        self.jointShape = jointShape
        self.landmarks = landmarks
        self.angleMask = angleMask
        self.jointMask = jointMask
        self.jointAngles = jointAngles
        self.normalizedJoints = normalizedJoints
    }
}

struct TrackedHand: Identifiable {
    let id: Int
    let features: HandFeatures
}

enum UserRelativeCoordinates {
    // Capture output is mirrored; image-left is the user's left.
    static func x(fromMirroredImageX x: Double) -> Double { min(1, max(0, x)) }
}

struct GestureVector: Codable, Equatable {
    var x: Double
    var y: Double
    var fingers: [Double]
    var details: [Double]? = nil
    var angleMask: [Bool]? = nil
    var jointMask: [Bool]? = nil
    var angles: [Double]? = nil
    var normalizedJoints: [Double]? = nil

    static func from(_ feature: HandFeatures) -> GestureVector {
        GestureVector(x: feature.palmX, y: feature.palmY, fingers: feature.fingerExtensions,
                      details: feature.jointShape.isEmpty ? nil : feature.jointShape,
                      angleMask: feature.angleMask.isEmpty ? nil : feature.angleMask,
                      jointMask: feature.jointMask.isEmpty ? nil : feature.jointMask,
                      angles: feature.jointAngles.isEmpty ? nil : feature.jointAngles,
                      normalizedJoints: feature.normalizedJoints.isEmpty ? nil : feature.normalizedJoints)
    }
}

struct GestureTemplate: Codable, Equatable {
    let duration: Double
    let frames: [GestureVector]
    var secondaryFrames: [GestureVector]? = nil
    var isStatic: Bool? = nil

    var handCount: Int { secondaryFrames == nil ? 1 : 2 }
}

struct ShortcutBinding: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
    var title: String
}

enum GestureBinding: Codable, Equatable {
    case scrollDown
    case scrollUp
    case browserBack
    case shortcut(ShortcutBinding)
    case text(String)

    var title: String {
        switch self {
        case .scrollDown: "Scroll down"
        case .scrollUp: "Scroll up"
        case .browserBack: "Browser back"
        case .shortcut(let shortcut): shortcut.title
        case .text(let text): "Type text: " + text.replacingOccurrences(of: "\n", with: " ↵ ").prefix(50)
        }
    }
}

struct SavedGesture: Codable, Identifiable, Equatable {
    static let minimumRecordings = 3
    var id = UUID()
    var name: String
    var enabled = true
    var binding: GestureBinding
    var samples: [GestureTemplate]
    var handCount: Int { samples.first?.handCount ?? 1 }
    var isTrained: Bool {
        samples.count >= Self.minimumRecordings && samples.allSatisfy { $0.handCount == handCount }
    }
    var isActive: Bool { enabled && isTrained }
    var isStatic: Bool { !samples.isEmpty && samples.allSatisfy { $0.isStatic == true } }
}

struct GestureTraining {
    private(set) var samples: [GestureTemplate] = []
    var verified = false
    var isReady: Bool { samples.count >= SavedGesture.minimumRecordings }
    var canSave: Bool { isReady && verified }

    mutating func append(_ template: GestureTemplate) {
        guard samples.first.map({ $0.handCount == template.handCount }) ?? true else { return }
        samples.append(template)
        verified = false
    }
}

enum GestureCaptureLimits {
    static let minimumDuration = 0.2
    static let minimumFrames = 5

    // Camera timestamps are large floating-point values: accept the exact boundary.
    static func accepts(duration: Double) -> Bool {
        duration.isFinite && duration >= minimumDuration - 0.000001
    }
}

enum GestureRecordingError: LocalizedError {
    case tooShort, trackingLost, noMovement

    var errorDescription: String? {
        switch self {
        case .tooShort: "Select at least 0.2 seconds and 5 tracked frames."
        case .trackingLost: "Hand tracking was interrupted. Please try again."
        case .noMovement: "Move your hand or change its shape during the recording."
        }
    }
}

struct GestureRecording {
    private(set) var samples: [HandFeatures] = []
    private var lastTimestamp: Double?
    private(set) var lostTracking = false

    mutating func append(_ feature: HandFeatures?) {
        guard let feature, feature.confidence >= 0.5, feature.fingerExtensions.count == 4 else {
            return
        }
        if let lastTimestamp, feature.timestamp - lastTimestamp > 0.35 { lostTracking = true }
        lastTimestamp = feature.timestamp
        samples.append(feature)
    }

    func finish(automaticallyTrim: Bool = true) throws -> GestureTemplate {
        guard !lostTracking else { throw GestureRecordingError.trackingLost }
        guard let first = samples.first, let last = samples.last,
              samples.count >= GestureCaptureLimits.minimumFrames, GestureCaptureLimits.accepts(duration: last.timestamp - first.timestamp) else {
            throw GestureRecordingError.tooShort
        }
        let maxMotion = samples.map { hypot($0.palmX - first.palmX, $0.palmY - first.palmY) }.max() ?? 0
        let maxShapeChange = samples.map { frame in
            Self.meanFingerDifference(frame.fingerExtensions, first.fingerExtensions)
        }.max() ?? 0
        let maxJointChange = samples.map { frame in
            Self.jointDifference(frame.jointShape, first.jointShape)
        }.max() ?? 0
        guard maxMotion >= 0.09 || maxShapeChange >= 0.16 || maxJointChange >= 0.25 else {
            // Static poses retain 16 actual feature examples, not an absolute-position rule.
            guard samples.allSatisfy({ $0.jointAngles.count == 15 && $0.normalizedJoints.count == 40 }) else {
                throw GestureRecordingError.noMovement
            }
            let held = automaticallyTrim ? samples.filter { last.timestamp - $0.timestamp <= 0.8 } : samples
            return GestureTemplate(duration: held.last!.timestamp - held.first!.timestamp,
                                   frames: GestureMatcher.resample(held, count: 16), isStatic: true)
        }

        if !automaticallyTrim {
            return GestureTemplate(duration: last.timestamp - first.timestamp,
                                   frames: GestureMatcher.resample(samples, count: GestureMatcher.templateFrameCount))
        }

        let palmActivity = GestureMotionSegment.activePalmIndices([samples])
        var activeIndices: [Int] = palmActivity ?? []
        for index in 3..<samples.count where palmActivity == nil {
            let current = samples[index], earlier = samples[index - 3]
            let motion = hypot(current.palmX - earlier.palmX, current.palmY - earlier.palmY)
            let shape = Self.meanFingerDifference(current.fingerExtensions, earlier.fingerExtensions)
            let joints = Self.jointDifference(current.jointShape, earlier.jointShape)
            if motion >= 0.012 || shape >= 0.06 || joints >= 0.10 { activeIndices.append(index) }
        }
        guard let firstActive = activeIndices.first, let lastActive = activeIndices.last else {
            throw GestureRecordingError.noMovement
        }
        var start = max(0, firstActive - 5)
        var end = min(samples.count - 1, lastActive + 3)
        while !GestureCaptureLimits.accepts(duration: samples[end].timestamp - samples[start].timestamp) && end < samples.count - 1 { end += 1 }
        while !GestureCaptureLimits.accepts(duration: samples[end].timestamp - samples[start].timestamp) && start > 0 { start -= 1 }
        let trimmed = Array(samples[start...end])
        return GestureTemplate(duration: trimmed.last!.timestamp - trimmed.first!.timestamp,
                               frames: GestureMatcher.resample(trimmed, count: GestureMatcher.templateFrameCount))
    }

    private static func meanFingerDifference(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty else { return 0 }
        var total = 0.0
        for index in 0..<min(a.count, b.count) { total += abs(a[index] - b[index]) }
        return total / Double(a.count)
    }

    private static func jointDifference(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == 40, b.count == 40 else { return 0 }
        return (0..<5).map { finger in
            let range = finger * 8..<(finger + 1) * 8
            return range.reduce(0.0) { $0 + abs(a[$1] - b[$1]) } / 8
        }.max() ?? 0
    }
}

struct GestureMatcher {
    static let templateFrameCount = 32
    // Duration multipliers, covering repetitions from twice as fast to twice as slow.
    static let playbackSpeeds: [Double] = [0.5, 0.65, 0.8, 1.0, 1.25, 1.6, 2.0]
    static let historyDuration = 11.0
    static let actionInterval = 0.15
    static let releaseHistoryDuration = 0.3
    static func matchThreshold(_ sensitivity: Double) -> Double {
        0.19 * max(0.7, min(sensitivity, 1.5))
    }
    private var recent: [HandFeatures] = []
    private var lastEvaluation = 0.0
    private var cooldownUntil = 0.0
    private var heldEndpoint: GestureVector?
    private var repeatedGestureID: UUID?
    private var repeatEndpoint: GestureVector?
    private var repeatCooldownUntil = 0.0
    private var repeatEarliest = 0.0
    private var lastSeen: Double?
    private var debounce = GestureDebounce()
    private(set) var closestScore: Double?
    var sensitivity = 1.0

    mutating func reset() {
        recent.removeAll()
        debounce.reset()
        closestScore = nil
        heldEndpoint = nil
        repeatEndpoint = nil
        repeatedGestureID = nil
        lastSeen = nil
        lastEvaluation = 0
    }

    mutating func consume(_ feature: HandFeatures?, gestures: [SavedGesture]) -> SavedGesture? {
        guard let feature, feature.confidence >= 0.5, feature.fingerExtensions.count == 4 else {
            reset()
            return nil
        }
        if let lastSeen, feature.timestamp - lastSeen > 0.35 { reset() }
        lastSeen = feature.timestamp
        recent.append(feature)
        recent.removeAll { feature.timestamp - $0.timestamp > Self.historyDuration }

        if let endpoint = repeatEndpoint,
           feature.timestamp >= repeatCooldownUntil,
           Self.releaseDistance(GestureVector.from(feature), endpoint) >= 0.18 {
            repeatEndpoint = nil
            repeatEarliest = feature.timestamp
        }
        if let endpoint = heldEndpoint {
            let now = GestureVector.from(feature)
            let distance = Self.releaseDistance(now, endpoint)
            if distance < 0.18 {
                // Keep a short lead-in so leaving the endpoint does not erase
                // the beginning of the next gesture in a continuous chain.
                recent.removeAll { feature.timestamp - $0.timestamp > Self.releaseHistoryDuration }
                return nil
            }
            heldEndpoint = nil
        }
        guard feature.timestamp >= cooldownUntil, feature.timestamp > lastEvaluation else { return nil }
        lastEvaluation = feature.timestamp

        var candidates: [(gesture: SavedGesture, score: Double)] = []
        for gesture in gestures where gesture.isActive {
            if gesture.id == repeatedGestureID && repeatEndpoint != nil { continue }
            var gestureScore = Double.infinity
            for template in gesture.samples where template.secondaryFrames == nil && (16...64).contains(template.frames.count) && GestureCaptureLimits.accepts(duration: template.duration) {
                for speed in Self.playbackSpeeds {
                    let duration = template.duration * speed
                    let earliest = feature.timestamp - duration
                    guard let firstIndex = recent.firstIndex(where: { $0.timestamp >= earliest }),
                          (recent.first?.timestamp ?? 0) <= earliest + 0.15 else { continue }
                    let window = Array(recent[firstIndex...].filter {
                        gesture.id != repeatedGestureID || $0.timestamp >= repeatEarliest
                    })
                    guard window.count >= 5, let first = window.first,
                          feature.timestamp - first.timestamp >= duration * 0.83 else { continue }
                    let score = Self.score(Self.resample(window, count: template.frames.count), template.frames)
                    gestureScore = min(gestureScore, score)
                }
            }
            if gestureScore.isFinite { candidates.append((gesture, gestureScore)) }
        }
        candidates.sort { $0.score < $1.score }
        closestScore = candidates.first?.score
        guard let best = candidates.first, best.score <= Self.matchThreshold(sensitivity),
              candidates.count < 2 || candidates[1].score - best.score >= 0.025 else {
            _ = debounce.confirm(nil)
            return nil
        }
        guard debounce.confirm(best.gesture.id, required: best.gesture.isStatic ? 5 : 2,
                               window: best.gesture.isStatic ? 7 : 3) else { return nil }
        debounce.reset()
        cooldownUntil = feature.timestamp + Self.actionInterval
        heldEndpoint = GestureVector.from(feature)
        // Preserve the existing repeat guard for the same gesture. Different
        // gestures can chain immediately without replaying a trailing movement.
        repeatedGestureID = best.gesture.id
        repeatEndpoint = heldEndpoint
        repeatCooldownUntil = feature.timestamp + 1.0
        recent = [feature]
        return best.gesture
    }

    static func resample(_ samples: [HandFeatures], count: Int) -> [GestureVector] {
        guard let first = samples.first, let last = samples.last, count > 1 else { return [] }
        let duration = max(0.001, last.timestamp - first.timestamp)
        return (0..<count).map { index in
            let target = first.timestamp + duration * Double(index) / Double(count - 1)
            let next = samples.firstIndex(where: { $0.timestamp >= target }) ?? samples.count - 1
            let previous = max(0, next - 1)
            let a = samples[previous], b = samples[next]
            let fraction = b.timestamp == a.timestamp ? 0 : (target - a.timestamp) / (b.timestamp - a.timestamp)
            return GestureVector(
                x: a.palmX + (b.palmX - a.palmX) * fraction,
                y: a.palmY + (b.palmY - a.palmY) * fraction,
                fingers: zip(a.fingerExtensions, b.fingerExtensions).map { $0 + ($1 - $0) * fraction },
                details: interpolateDetails(a.jointShape, b.jointShape, fraction: fraction),
                angleMask: interpolateMask(a.angleMask, b.angleMask, count: 15),
                jointMask: interpolateMask(a.jointMask, b.jointMask, count: 40),
                angles: interpolateFeatures(a.jointAngles, b.jointAngles, count: 15, fraction: fraction),
                normalizedJoints: interpolateDetails(a.normalizedJoints, b.normalizedJoints, fraction: fraction)
            )
        }
    }

    private static func interpolateMask(_ a: [Bool], _ b: [Bool], count: Int) -> [Bool]? {
        if a.isEmpty && b.isEmpty { return nil }
        guard a.count == count, b.count == count else { return Array(repeating: false, count: count) }
        return zip(a, b).map { $0 && $1 }
    }

    private static func interpolateFeatures(_ a: [Double], _ b: [Double], count: Int, fraction: Double) -> [Double]? {
        guard a.count == count, b.count == count else { return nil }
        return zip(a, b).map { $0 + ($1 - $0) * fraction }
    }

    static func shapeDistance(_ a: GestureVector, _ b: GestureVector) -> Double {
        guard a.angleMask == nil || a.angleMask?.count == 15,
              b.angleMask == nil || b.angleMask?.count == 15,
              a.jointMask == nil || a.jointMask?.count == 40,
              b.jointMask == nil || b.jointMask?.count == 40 else { return .infinity }
        if let angles = b.angles {
            guard let live = a.angles, live.count == 15, angles.count == 15,
                  let joints = a.normalizedJoints, let reference = b.normalizedJoints,
                  joints.count == 40, reference.count == 40 else { return .infinity }
            var angleCount = 0, jointCount = 0
            var angleSum = 0.0, jointSum = 0.0
            for index in 0..<15 where (a.angleMask?[index] ?? true) && (b.angleMask?[index] ?? true) {
                let delta = live[index] - angles[index]
                angleSum += delta * delta
                angleCount += 1
            }
            for index in 0..<40 where (a.jointMask?[index] ?? true) && (b.jointMask?[index] ?? true) {
                jointSum += abs(joints[index] - reference[index])
                jointCount += 1
            }
            guard angleCount >= 9, jointCount >= 24 else { return .infinity }
            let missingPenalty = 0.04 * (1 - Double(angleCount) / 15)
            return 2 * sqrt(angleSum / Double(angleCount)) + 0.15 * jointSum / Double(jointCount) + missingPenalty
        }
        return 0.65 * meanFingerDifference(a.fingers, b.fingers) + 0.65 * jointDifference(a.details, b.details)
    }

    private static func interpolateDetails(_ a: [Double], _ b: [Double], fraction: Double) -> [Double]? {
        guard a.count == 40, b.count == 40 else { return nil }
        return zip(a, b).map { $0 + ($1 - $0) * fraction }
    }

    static func releaseDistance(_ a: GestureVector, _ b: GestureVector) -> Double {
        hypot(a.x - b.x, a.y - b.y) + shapeDistance(a, b)
    }

    static func score(_ sample: [GestureVector], _ template: [GestureVector]) -> Double {
        sequenceScore([sample], [template])
    }

    // Both hands must follow the SAME warping path. Independent alignments would accept
    // sequential hand movements as a simultaneous gesture (and lose coordination).
    static func sequenceScore(_ samples: [[GestureVector]], _ templates: [[GestureVector]]) -> Double {
        guard samples.count == templates.count, !samples.isEmpty,
              let n = samples.first?.count, n >= 2,
              samples.allSatisfy({ $0.count == n }),
              templates.allSatisfy({ $0.count == n }) else { return .infinity }
        func valid(_ vector: GestureVector) -> Bool {
            vector.x.isFinite && vector.y.isFinite && vector.fingers.count == 4
                && vector.fingers.allSatisfy(\.isFinite)
                && (vector.angles == nil || (vector.angles!.count == 15 && vector.angles!.allSatisfy { $0.isFinite && (0...1).contains($0) }))
                && (vector.normalizedJoints == nil || (vector.normalizedJoints!.count == 40 && vector.normalizedJoints!.allSatisfy(\.isFinite)))
                && (vector.details == nil || (vector.details!.count == 40 && vector.details!.allSatisfy(\.isFinite)))
        }
        guard samples.flatMap({ $0 }).allSatisfy(valid),
              templates.flatMap({ $0 }).allSatisfy(valid) else { return .infinity }
        for hand in samples.indices {
            // A detailed recording cannot be verified from missing joints. Legacy templates
            // without details still use their original palm and extension features.
            if templates[hand].contains(where: { $0.details != nil }),
               samples[hand].contains(where: { $0.details == nil }) { return .infinity }
        }
        func amplitude(_ frames: [GestureVector]) -> Double {
            let first = frames[0]
            return frames.map { hypot($0.x - first.x, $0.y - first.y) }.max() ?? 0
        }
        let amplitudesA = samples.map(amplitude), amplitudesB = templates.map(amplitude)
        // One spatial scale preserves the relative amount each hand moves.
        let scaleA = max(0.18, amplitudesA.max() ?? 0)
        let scaleB = max(0.18, amplitudesB.max() ?? 0)
        // For a palm movement, trajectory carries the intent. Do not let incidental
        // finger bends outweigh a matching path. Finger-only gestures keep full shape weight.
        let shapeWeight = (amplitudesB.max() ?? 0) >= 0.09 ? 0.35 : 1.0
        func localCost(_ i: Int, _ j: Int) -> Double {
            var worstHand = 0.0
            for hand in samples.indices {
                let a = samples[hand][i], b = templates[hand][j]
                let a0 = samples[hand][0], b0 = templates[hand][0]
                let motion = hypot((a.x - a0.x) / scaleA - (b.x - b0.x) / scaleB,
                                   (a.y - a0.y) / scaleA - (b.y - b0.y) / scaleB)
                let cost = 0.38 * motion + shapeWeight * shapeDistance(a, b)
                worstHand = max(worstHand, cost)
            }
            return worstHand
        }
        let stride = n + 1
        let band = max(4, n / 3)
        var costs = [Double](repeating: .infinity, count: stride * stride)
        var steps = [Int](repeating: 0, count: stride * stride)
        costs[0] = 0
        for i in 1...n {
            for j in max(1, i - band)...min(n, i + band) {
                let diagonal = (i - 1) * stride + j - 1
                let up = (i - 1) * stride + j
                let left = i * stride + j - 1
                var previous = diagonal
                if costs[up] + 0.006 < costs[previous] { previous = up }
                if costs[left] + 0.006 < costs[previous] { previous = left }
                let index = i * stride + j
                costs[index] = costs[previous] + localCost(i - 1, j - 1) + (previous == diagonal ? 0 : 0.006)
                steps[index] = steps[previous] + 1
            }
        }
        let end = n * stride + n
        guard steps[end] > 0 else { return .infinity }
        let amplitudePenalty = zip(amplitudesA, amplitudesB).map {
            0.12 * abs(log(($0 + 0.08) / ($1 + 0.08)))
        }.max() ?? 0
        // Averaging alone can hide a wrong starting/final pose in a long sequence.
        let endpointPenalty = 0.25 * max(localCost(0, 0), localCost(n - 1, n - 1))
        return costs[end] / Double(steps[end]) + amplitudePenalty + endpointPenalty
    }

    private static func meanFingerDifference(_ a: [Double], _ b: [Double]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var total = 0.0
        for index in 0..<count { total += abs(a[index] - b[index]) }
        return total / Double(count)
    }

    private static func jointDifference(_ a: [Double]?, _ b: [Double]?) -> Double {
        guard let a, let b, a.count == 40, b.count == 40 else { return 0 }
        return (0..<5).map { finger in
            let range = finger * 8..<(finger + 1) * 8
            return range.reduce(0.0) { $0 + abs(a[$1] - b[$1]) } / 8
        }.max() ?? 0
    }
}
