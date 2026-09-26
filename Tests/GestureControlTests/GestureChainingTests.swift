import XCTest
@testable import GestureControl

final class GestureChainingTests: XCTestCase {
    private func hands(_ time: Double, _ progress: Double) -> [TrackedHand] {
        [0, 1].map { hand in
            TrackedHand(id: hand, features: HandFeatures(timestamp: time,
                palmX: hand == 0 ? 0.2 + progress * 0.4 : 0.6 + progress * 0.2,
                palmY: 0.5, confidence: 1, pose: .open, fingerExtensions: [1, 1, 1, 1]))
        }
    }

    private func gesture(reverse: Bool, twoHands: Bool) throws -> SavedGesture {
        var single = GestureRecording()
        var pair = MultiHandRecording()
        for index in 0...6 {
            let progress = Double(index) / 6
            let input = hands(Double(index) * 0.05, reverse ? 1 - progress : progress)
            single.append(input[0].features)
            pair.append(input)
        }
        let template = try twoHands ? pair.finish(automaticallyTrim: false) : single.finish(automaticallyTrim: false)
        return SavedGesture(name: reverse ? "Back" : "Forward", binding: .scrollDown,
                            samples: Array(repeating: template, count: 3))
    }

    func testContinuousForwardBackForwardChainForOneAndTwoHands() throws {
        for twoHands in [false, true] {
            let forward = try gesture(reverse: false, twoHands: twoHands)
            let back = try gesture(reverse: true, twoHands: twoHands)
            var single = GestureMatcher()
            var pair = MultiHandMatcher()
            var detected: [UUID] = []
            var times: [Double] = []
            for index in 0...42 {
                let progress: Double
                switch index {
                case 0...6: progress = Double(index) / 6
                case 7...8: progress = 1
                case 9...14: progress = 1 - Double(index - 8) / 6
                case 15...16: progress = 0
                case 17...22: progress = Double(index - 16) / 6
                default: progress = 1 // Holding the final pose must not repeat.
                }
                let time = 10 + Double(index) * 0.05
                let input = hands(time, progress)
                let match = twoHands ? pair.consume(input, gestures: [forward, back])
                    : single.consume(input[0].features, gestures: [forward, back])
                if let match { detected.append(match.id); times.append(time) }
            }
            XCTAssertEqual(detected, [forward.id, back.id, forward.id], "Two hands: \(twoHands)")
            for (previous, next) in zip(times, times.dropFirst()) {
                XCTAssertLessThan(next - previous, 0.7)
                XCTAssertGreaterThanOrEqual(next - previous, GestureMatcher.actionInterval)
            }
        }
    }

    func testTrackingLossCannotReusePreviousMovement() throws {
        for twoHands in [false, true] {
            let forward = try gesture(reverse: false, twoHands: twoHands)
            var single = GestureMatcher()
            var pair = MultiHandMatcher()
            for index in 0...4 {
                let input = hands(10 + Double(index) * 0.05, Double(index) / 6)
                XCTAssertNil(twoHands ? pair.consume(input, gestures: [forward])
                             : single.consume(input[0].features, gestures: [forward]))
            }
            XCTAssertNil(twoHands ? pair.consume([], gestures: [forward]) : single.consume(nil, gestures: [forward]))
            for index in 6...16 {
                let input = hands(10 + Double(index) * 0.05, min(1, Double(index) / 6))
                XCTAssertNil(twoHands ? pair.consume(input, gestures: [forward])
                             : single.consume(input[0].features, gestures: [forward]))
            }
        }
    }
}
