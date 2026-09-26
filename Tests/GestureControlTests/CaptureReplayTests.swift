import XCTest
@testable import GestureControl

final class CaptureReplayTests: XCTestCase {
    private func frame(_ time: Double, progress: Double, angle: Double = 0.2, noise: Double = 0) -> HandFeatures {
        HandFeatures(timestamp: time, palmX: 0.75 - 0.35 * progress + noise * 0.01,
                     palmY: 0.5, confidence: 0.9, pose: .open, fingerExtensions: [0.9, 0.9, 0.9, 0.9],
                     jointShape: Array(repeating: 0.5 + noise, count: 40),
                     jointAngles: Array(repeating: angle, count: 15),
                     normalizedJoints: Array(repeating: 0.5, count: 40))
    }

    func testFingerJitterDoesNotTurnBriefSwipeIntoFiveSecondTemplate() throws {
        var recording = GestureRecording()
        for i in 0...150 {
            let time = Double(i) / 30
            recording.append(frame(time, progress: min(1, max(0, (time - 0.8) / 0.8)),
                                   noise: i.isMultiple(of: 2) ? 0.08 : -0.08))
        }
        let template = try recording.finish()
        XCTAssertLessThan(template.duration, 1.6)
        let gesture = SavedGesture(name: "Swipe", binding: .scrollDown, samples: Array(repeating: template, count: 3))
        var matcher = GestureMatcher()
        var count = 0
        for i in 0...75 {
            let time = Double(i) / 30
            if matcher.consume(frame(10 + time, progress: min(1, max(0, (time - 0.4) / 0.8))), gestures: [gesture]) != nil {
                count += 1
            }
        }
        XCTAssertEqual(count, 1)
    }

    func testPalmMovementAllowsNaturalFingerBendVariation() throws {
        let samples = try [0.19, 0.2, 0.21].map { angle -> GestureTemplate in
            var recording = GestureRecording()
            for i in 0...45 { recording.append(frame(Double(i) / 30, progress: Double(i) / 45, angle: angle)) }
            return try recording.finish()
        }
        let gesture = SavedGesture(name: "Swipe", binding: .scrollDown, samples: samples)
        var matcher = GestureMatcher(), opposite = GestureMatcher(), stationary = GestureMatcher()
        var matches = 0
        for i in 0...60 {
            let time = 10 + Double(i) / 30
            let progress = min(1, Double(i) / 45)
            if matcher.consume(frame(time, progress: progress, angle: 0.32), gestures: [gesture]) != nil { matches += 1 }
            XCTAssertNil(opposite.consume(frame(time, progress: 1 - progress, angle: 0.32), gestures: [gesture]))
            XCTAssertNil(stationary.consume(frame(time, progress: 0.5, angle: 0.32), gestures: [gesture]))
        }
        XCTAssertEqual(matches, 1)
    }
}
