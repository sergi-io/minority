import Foundation

/// One candidate and its recognition history for the entire Test session.
/// Recreating SavedGesture per frame assigns a new UUID, preventing debounce
/// from ever observing the same candidate twice.
struct GestureVerificationSession {
    private let candidate: SavedGesture
    private var matchers: [Int: GestureMatcher] = [:]
    private var multiMatcher = MultiHandMatcher()
    private(set) var closestScore: Double?
    var handCount: Int { candidate.handCount }

    init(samples: [GestureTemplate]) {
        candidate = SavedGesture(name: "Capture test", binding: .scrollDown, samples: samples)
    }

    mutating func consume(_ hands: [TrackedHand], sensitivity: Double) -> Bool {
        closestScore = nil
        if candidate.handCount == 2 {
            multiMatcher.sensitivity = sensitivity
            let result = multiMatcher.consume(hands, gestures: [candidate])
            closestScore = multiMatcher.closestScore
            return result != nil
        }
        let visibleIDs = Set(hands.map(\.id))
        // A tracking loss ends that hand's sequence and pending confirmations.
        matchers = matchers.filter { visibleIDs.contains($0.key) }
        for hand in hands {
            var matcher = matchers[hand.id] ?? GestureMatcher()
            matcher.sensitivity = sensitivity
            let result = matcher.consume(hand.features, gestures: [candidate])
            matchers[hand.id] = matcher
            if let score = matcher.closestScore {
                closestScore = min(closestScore ?? .infinity, score)
            }
            if result != nil { return true }
        }
        return false
    }
}
