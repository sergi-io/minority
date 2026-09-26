import XCTest
@testable import GestureControl

final class HandShapeGeometryTests: XCTestCase {
    private func landmarks() -> [HandLandmark] {
        var points = [HandLandmark(id: 0, x: 0, y: 0, confidence: 1)]
        for finger in 0..<5 {
            for joint in 0..<4 {
                points.append(HandLandmark(id: 1 + finger * 4 + joint,
                                           x: Double(finger - 2) * 0.1 + Double(joint) * 0.015,
                                           y: 0.2 + Double(joint) * 0.12, confidence: 1))
            }
        }
        return points
    }

    func testAnglesAndNormalizedCoordinatesIgnoreScaleTranslationAndInPlaneRotation() throws {
        let original = landmarks()
        let reference = try XCTUnwrap(HandShapeGeometry(landmarks: original, imageAspectRatio: 1))
        for scale in [0.4, 1.7] {
            let angle = 0.7
            let transformed = original.map { p in
                HandLandmark(id: p.id, x: 0.4 + scale * (p.x * cos(angle) - p.y * sin(angle)),
                             y: 0.1 + scale * (p.x * sin(angle) + p.y * cos(angle)), confidence: 1)
            }
            let result = try XCTUnwrap(HandShapeGeometry(landmarks: transformed, imageAspectRatio: 1))
            for (a, b) in zip(result.angles, reference.angles) { XCTAssertEqual(a, b, accuracy: 0.000001) }
            for (a, b) in zip(result.joints, reference.joints) { XCTAssertEqual(a, b, accuracy: 0.000001) }
        }
        let widescreen = original.map { HandLandmark(id: $0.id, x: $0.x / (16.0 / 9), y: $0.y, confidence: 1) }
        let corrected = try XCTUnwrap(HandShapeGeometry(landmarks: widescreen, imageAspectRatio: 16.0 / 9))
        for (a, b) in zip(corrected.angles, reference.angles) { XCTAssertEqual(a, b, accuracy: 0.000001) }
    }

    func testUnreliableJointsAreMaskedAndDegenerateHandsAreRejected() throws {
        var points = landmarks()
        let tip = points[8]
        points[8] = HandLandmark(id: tip.id, x: tip.x, y: tip.y, confidence: 0.29)
        let partial = try XCTUnwrap(HandShapeGeometry(landmarks: points, imageAspectRatio: 1))
        XCTAssertFalse(partial.angleMask[5])
        XCTAssertFalse(partial.jointMask[14])
        points[8] = HandLandmark(id: tip.id, x: tip.x, y: tip.y, confidence: 0.3)
        XCTAssertNotNil(HandShapeGeometry(landmarks: points, imageAspectRatio: 1))
        points.removeLast()
        XCTAssertNotNil(HandShapeGeometry(landmarks: points, imageAspectRatio: 1))
        points.removeAll { $0.id == 9 }
        XCTAssertNil(HandShapeGeometry(landmarks: points, imageAspectRatio: 1))
        let degenerate = (0...20).map { HandLandmark(id: $0, x: 0, y: 0, confidence: 1) }
        XCTAssertNil(HandShapeGeometry(landmarks: degenerate, imageAspectRatio: 1))
    }

    func testFiveOfSevenVotesMustBelongToSameGesture() {
        let id = UUID(), other = UUID()
        var debounce = GestureDebounce()
        for vote in [id, id, nil, id, other, id] { XCTAssertFalse(debounce.confirm(vote)) }
        XCTAssertTrue(debounce.confirm(id))
        debounce.reset()
        for vote in [id, other, id, other, id, other, id] { XCTAssertFalse(debounce.confirm(vote)) }
        debounce.reset()
        for _ in 0..<4 { XCTAssertFalse(debounce.confirm(id)) }
        for _ in 0..<7 { XCTAssertFalse(debounce.confirm(nil)) }
        XCTAssertFalse(debounce.confirm(id), "Old evidence must expire")
    }

    func testStaticAngleTemplatesRoundTripAndRecognizeOnlyMatchingPose() throws {
        let shape = try XCTUnwrap(HandShapeGeometry(landmarks: landmarks(), imageAspectRatio: 1))
        func frame(_ time: Double, wrong: Bool = false) -> HandFeatures {
            HandFeatures(timestamp: time, palmX: 0.5, palmY: 0.5, confidence: 1, pose: .open,
                         fingerExtensions: [1, 1, 1, 1], jointShape: shape.joints,
                         jointAngles: wrong ? Array(repeating: 0.8, count: 15) : shape.angles,
                         normalizedJoints: shape.joints)
        }
        var recording = GestureRecording()
        var pairRecording = MultiHandRecording()
        for index in 0...30 {
            let sample = frame(Double(index) * 0.05)
            recording.append(sample)
            pairRecording.append([TrackedHand(id: 0, features: sample), TrackedHand(id: 1, features: sample)])
        }
        let template = try recording.finish()
        XCTAssertEqual(template.frames.count, 16)
        XCTAssertEqual(try pairRecording.finish().secondaryFrames?.count, 16)
        let saved = SavedGesture(name: "Pose", binding: .scrollUp, samples: Array(repeating: template, count: 3))
        let restored = try JSONDecoder().decode(SavedGesture.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(saved, restored)
        var matcher = GestureMatcher(), wrongMatcher = GestureMatcher()
        var matches = 0
        for index in 0...60 {
            let time = 10 + Double(index) * 0.05
            if matcher.consume(frame(time), gestures: [restored]) != nil { matches += 1 }
            XCTAssertNil(wrongMatcher.consume(frame(time, wrong: true), gestures: [restored]))
        }
        XCTAssertEqual(matches, 1, "A held pose must not repeat")
        let missingAngles = template.frames.map { GestureVector(x: $0.x, y: $0.y, fingers: $0.fingers, details: $0.details) }
        XCTAssertEqual(GestureMatcher.score(missingAngles, template.frames), .infinity)
    }
}
