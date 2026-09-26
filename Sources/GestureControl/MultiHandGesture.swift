import Foundation

struct TwoHandFrame {
    let timestamp: Double
    let first: HandFeatures
    let second: HandFeatures

    init?(_ hands: [TrackedHand]) {
        guard hands.count == 2,
              hands[0].features.confidence >= 0.5,
              hands[1].features.confidence >= 0.5 else { return nil }
        let ordered = hands.sorted { $0.id < $1.id }
        timestamp = ordered[0].features.timestamp
        first = ordered[0].features
        second = ordered[1].features
    }
}

struct MultiHandRecording {
    private(set) var samples: [TwoHandFrame] = []
    private(set) var lostTracking = false

    mutating func append(_ hands: [TrackedHand]) {
        guard let frame = TwoHandFrame(hands) else { return }
        if let previous = samples.last, frame.timestamp - previous.timestamp > 0.35 {
            lostTracking = true
        }
        samples.append(frame)
    }

    func finish(automaticallyTrim: Bool = true) throws -> GestureTemplate {
        guard !lostTracking else { throw GestureRecordingError.trackingLost }
        guard let first = samples.first, let last = samples.last,
              samples.count >= GestureCaptureLimits.minimumFrames, GestureCaptureLimits.accepts(duration: last.timestamp - first.timestamp) else {
            throw GestureRecordingError.tooShort
        }
        let maxChange = samples.map { frame in
            max(Self.change(frame.first, first.first), Self.change(frame.second, first.second))
        }.max() ?? 0
        guard maxChange >= 0.10 else {
            guard samples.allSatisfy({ $0.first.jointAngles.count == 15 && $0.second.jointAngles.count == 15
                && $0.first.normalizedJoints.count == 40 && $0.second.normalizedJoints.count == 40 }) else {
                throw GestureRecordingError.noMovement
            }
            let held = automaticallyTrim ? samples.filter { last.timestamp - $0.timestamp <= 0.8 } : samples
            return GestureTemplate(duration: held.last!.timestamp - held.first!.timestamp,
                                   frames: GestureMatcher.resample(held.map(\.first), count: 16),
                                   secondaryFrames: GestureMatcher.resample(held.map(\.second), count: 16), isStatic: true)
        }

        if !automaticallyTrim {
            return GestureTemplate(duration: last.timestamp - first.timestamp,
                                   frames: GestureMatcher.resample(samples.map(\.first), count: GestureMatcher.templateFrameCount),
                                   secondaryFrames: GestureMatcher.resample(samples.map(\.second), count: GestureMatcher.templateFrameCount))
        }

        let palmActivity = GestureMotionSegment.activePalmIndices([samples.map(\.first), samples.map(\.second)])
        var active: [Int] = palmActivity ?? []
        for index in 3..<samples.count where palmActivity == nil {
            let current = samples[index], earlier = samples[index - 3]
            if max(Self.change(current.first, earlier.first),
                   Self.change(current.second, earlier.second)) >= 0.012 { active.append(index) }
        }
        guard let firstActive = active.first, let lastActive = active.last else {
            throw GestureRecordingError.noMovement
        }
        var start = max(0, firstActive - 5)
        var end = min(samples.count - 1, lastActive + 3)
        while !GestureCaptureLimits.accepts(duration: samples[end].timestamp - samples[start].timestamp) && end < samples.count - 1 { end += 1 }
        while !GestureCaptureLimits.accepts(duration: samples[end].timestamp - samples[start].timestamp) && start > 0 { start -= 1 }
        let trimmed = Array(samples[start...end])
        let firstSequence = trimmed.map(\.first)
        let secondSequence = trimmed.map(\.second)
        return GestureTemplate(duration: trimmed.last!.timestamp - trimmed.first!.timestamp,
                               frames: GestureMatcher.resample(firstSequence, count: GestureMatcher.templateFrameCount),
                               secondaryFrames: GestureMatcher.resample(secondSequence, count: GestureMatcher.templateFrameCount))
    }

    private static func change(_ a: HandFeatures, _ b: HandFeatures) -> Double {
        let motion = hypot(a.palmX - b.palmX, a.palmY - b.palmY)
        let shape = zip(a.fingerExtensions, b.fingerExtensions)
            .map { abs($0 - $1) }.reduce(0, +) / 4
        let joints: Double
        if a.jointShape.count == 40 && b.jointShape.count == 40 {
            joints = (0..<40).map { abs(a.jointShape[$0] - b.jointShape[$0]) }.max() ?? 0
        } else { joints = 0 }
        return motion + 0.5 * shape + 0.25 * joints
    }
}

struct MultiHandMatcher {
    private var recent: [TwoHandFrame] = []
    private var lastSeen: Double?
    private var debounce = GestureDebounce()
    private(set) var closestScore: Double?
    private var lastEvaluation = 0.0
    private var cooldownUntil = 0.0
    private var heldEndpoints: (GestureVector, GestureVector)?
    private var repeatedGestureID: UUID?
    private var repeatEndpoints: (GestureVector, GestureVector)?
    private var repeatCooldownUntil = 0.0
    private var repeatEarliest = 0.0
    var sensitivity = 1.0

    mutating func reset() {
        recent.removeAll()
        debounce.reset()
        closestScore = nil
        lastSeen = nil
        lastEvaluation = 0
        heldEndpoints = nil
        repeatEndpoints = nil
        repeatedGestureID = nil
    }

    mutating func consume(_ hands: [TrackedHand], gestures: [SavedGesture]) -> SavedGesture? {
        guard let frame = TwoHandFrame(hands) else { reset(); return nil }
        if let lastSeen, frame.timestamp - lastSeen > 0.35 { reset() }
        lastSeen = frame.timestamp
        recent.append(frame)
        recent.removeAll { frame.timestamp - $0.timestamp > GestureMatcher.historyDuration }
        if let endpoints = repeatEndpoints, frame.timestamp >= repeatCooldownUntil {
            let movement = GestureMatcher.releaseDistance(GestureVector.from(frame.first), endpoints.0)
                + GestureMatcher.releaseDistance(GestureVector.from(frame.second), endpoints.1)
            if movement >= 0.22 {
                repeatEndpoints = nil
                repeatEarliest = frame.timestamp
            }
        }
        if let heldEndpoints {
            let a = GestureVector.from(frame.first), b = GestureVector.from(frame.second)
            let movement = GestureMatcher.releaseDistance(a, heldEndpoints.0)
                + GestureMatcher.releaseDistance(b, heldEndpoints.1)
            if movement < 0.22 {
                recent.removeAll { frame.timestamp - $0.timestamp > GestureMatcher.releaseHistoryDuration }
                return nil
            }
            self.heldEndpoints = nil
        }
        guard frame.timestamp >= cooldownUntil, frame.timestamp > lastEvaluation else { return nil }
        lastEvaluation = frame.timestamp

        var candidates: [(gesture: SavedGesture, score: Double)] = []
        for gesture in gestures where gesture.isActive {
            if gesture.id == repeatedGestureID && repeatEndpoints != nil { continue }
            var gestureScore = Double.infinity
            for template in gesture.samples {
                guard let secondary = template.secondaryFrames,
                      (16...64).contains(template.frames.count), secondary.count == template.frames.count,
                      GestureCaptureLimits.accepts(duration: template.duration) else { continue }
                for speed in GestureMatcher.playbackSpeeds {
                    let duration = template.duration * speed
                    let earliest = frame.timestamp - duration
                    guard let firstIndex = recent.firstIndex(where: { $0.timestamp >= earliest }),
                          (recent.first?.timestamp ?? 0) <= earliest + 0.15 else { continue }
                    let window = Array(recent[firstIndex...].filter {
                        gesture.id != repeatedGestureID || $0.timestamp >= repeatEarliest
                    })
                    guard window.count >= 5, let first = window.first,
                          frame.timestamp - first.timestamp >= duration * 0.83 else { continue }
                    let sampleA = GestureMatcher.resample(window.map(\.first), count: template.frames.count)
                    let sampleB = GestureMatcher.resample(window.map(\.second), count: template.frames.count)
                    let direct = Self.pairScore(sampleA, sampleB, template.frames, secondary)
                    let reversed = Self.pairScore(sampleB, sampleA, template.frames, secondary)
                    let score = min(direct, reversed)
                    gestureScore = min(gestureScore, score)
                }
            }
            if gestureScore.isFinite { candidates.append((gesture, gestureScore)) }
        }
        candidates.sort { $0.score < $1.score }
        closestScore = candidates.first?.score
        guard let best = candidates.first, best.score <= GestureMatcher.matchThreshold(sensitivity),
              candidates.count < 2 || candidates[1].score - best.score >= 0.025 else {
            _ = debounce.confirm(nil)
            return nil
        }
        guard debounce.confirm(best.gesture.id, required: best.gesture.isStatic ? 5 : 2,
                               window: best.gesture.isStatic ? 7 : 3) else { return nil }
        debounce.reset()
        cooldownUntil = frame.timestamp + GestureMatcher.actionInterval
        heldEndpoints = (GestureVector.from(frame.first), GestureVector.from(frame.second))
        repeatedGestureID = best.gesture.id
        repeatEndpoints = heldEndpoints
        repeatCooldownUntil = frame.timestamp + 1.0
        recent = [frame]
        return best.gesture
    }

    private static func pairScore(_ a: [GestureVector], _ b: [GestureVector],
                                  _ templateA: [GestureVector], _ templateB: [GestureVector]) -> Double {
        guard let a0 = a.first, let b0 = b.first,
              let ta0 = templateA.first, let tb0 = templateB.first else { return .infinity }
        let spacing = abs(hypot(a0.x - b0.x, a0.y - b0.y)
                          - hypot(ta0.x - tb0.x, ta0.y - tb0.y))
        return GestureMatcher.sequenceScore([a, b], [templateA, templateB])
            + 0.3 * spacing
    }

}
