import XCTest
@testable import GestureControl

final class GestureVerificationSessionTests: XCTestCase {
    private func hand(_ time: Double, progress: Double, id: Int = 0) -> TrackedHand {
        TrackedHand(id: id, features: HandFeatures(timestamp: time,
            palmX: id == 0 ? 0.2 + 0.35 * progress : 0.8 - 0.35 * progress,
            palmY: 0.5, confidence: 0.95, pose: .open, fingerExtensions: [1, 1, 1, 1]))
    }

    func testOneHandTestSessionCanCompleteAfterThreeRecordings() throws {
        let templates = try [1.8, 2.0, 2.2].map { duration -> GestureTemplate in
            var recording = GestureRecording()
            for i in 0...40 { recording.append(hand(Double(i) / 40 * duration, progress: Double(i) / 40).features) }
            return try recording.finish()
        }
        var session = GestureVerificationSession(samples: templates)
        var matches = 0
        for i in 0...50 {
            if session.consume([hand(10 + Double(i) * 0.05, progress: min(1, Double(i) / 40))], sensitivity: 1) {
                matches += 1
            }
        }
        XCTAssertEqual(matches, 1)
    }

    func testTwoHandTestSessionCanCompleteAfterThreeRecordings() throws {
        let templates = try [1.8, 2.0, 2.2].map { duration -> GestureTemplate in
            var recording = MultiHandRecording()
            for i in 0...40 {
                recording.append([0, 1].map { hand(Double(i) / 40 * duration, progress: Double(i) / 40, id: $0) })
            }
            return try recording.finish()
        }
        var session = GestureVerificationSession(samples: templates)
        var matches = 0
        for i in 0...50 {
            if session.consume([0, 1].map { hand(10 + Double(i) * 0.05, progress: min(1, Double(i) / 40), id: $0) }, sensitivity: 1) {
                matches += 1
            }
        }
        XCTAssertEqual(matches, 1)
    }

    func testStaticTestSessionCanAccumulateFiveConfirmations() throws {
        func pose(_ time: Double) -> TrackedHand {
            TrackedHand(id: 0, features: HandFeatures(timestamp: time, palmX: 0.5, palmY: 0.5,
                confidence: 1, pose: .open, fingerExtensions: [1, 1, 1, 1],
                jointShape: Array(repeating: 0.5, count: 40), jointAngles: Array(repeating: 0.2, count: 15),
                normalizedJoints: Array(repeating: 0.5, count: 40)))
        }
        var recording = GestureRecording()
        for i in 0...30 { recording.append(pose(Double(i) * 0.05).features) }
        let templates = Array(repeating: try recording.finish(), count: 3)
        var session = GestureVerificationSession(samples: templates)
        var matches = 0
        for i in 0...45 {
            if session.consume([pose(10 + Double(i) * 0.05)], sensitivity: 1) { matches += 1 }
        }
        XCTAssertEqual(matches, 1)
    }

    func testUntrainedOrOppositeMovementCannotPassTestSession() throws {
        var recording = GestureRecording()
        for i in 0...40 { recording.append(hand(Double(i) * 0.05, progress: Double(i) / 40).features) }
        let template = try recording.finish()
        var incomplete = GestureVerificationSession(samples: [template, template])
        var opposite = GestureVerificationSession(samples: Array(repeating: template, count: 3))
        for i in 0...40 {
            XCTAssertFalse(incomplete.consume([hand(10 + Double(i) * 0.05, progress: Double(i) / 40)], sensitivity: 1))
            XCTAssertFalse(opposite.consume([hand(10 + Double(i) * 0.05, progress: 1 - Double(i) / 40)], sensitivity: 1))
        }
    }
}
