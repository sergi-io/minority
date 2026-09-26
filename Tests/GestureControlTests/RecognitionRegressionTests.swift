import XCTest
@testable import GestureControl

final class RecognitionRegressionTests: XCTestCase {
    func testOneOccludedFingertipDoesNotDiscardTheHand() throws {
        var points = [HandLandmark(id: 0, x: 0, y: 0, confidence: 1)]
        for finger in 0..<5 {
            for joint in 0..<4 {
                points.append(HandLandmark(id: 1 + finger * 4 + joint,
                                          x: Double(finger - 2) * 0.1 + Double(joint) * 0.015,
                                          y: 0.2 + Double(joint) * 0.12,
                                          confidence: finger == 4 && joint == 3 ? 0.1 : 1))
            }
        }
        XCTAssertNotNil(HandShapeGeometry(landmarks: points, imageAspectRatio: 1))
    }

    func testMaskedAnglesAreExcludedWithoutAcceptingInsufficientEvidence() throws {
        let reference = GestureVector(x: 0.5, y: 0.5, fingers: [1, 1, 1, 1],
                                      angles: Array(repeating: 0.2, count: 15),
                                      normalizedJoints: Array(repeating: 0.5, count: 40))
        var partial = reference
        partial.angleMask = Array(repeating: true, count: 15)
        partial.jointMask = Array(repeating: true, count: 40)
        partial.angleMask?[14] = false
        partial.jointMask?[38] = false
        partial.jointMask?[39] = false
        partial.angles?[14] = 1
        partial.normalizedJoints?[38] = 9
        partial.normalizedJoints?[39] = 9
        XCTAssertLessThan(GestureMatcher.shapeDistance(partial, reference), 0.01)
        XCTAssertEqual(try JSONDecoder().decode(GestureVector.self, from: JSONEncoder().encode(partial)), partial)
        partial.angleMask = Array(repeating: false, count: 15)
        XCTAssertEqual(GestureMatcher.shapeDistance(partial, reference), .infinity)
        partial.angleMask = [true]
        XCTAssertEqual(GestureMatcher.shapeDistance(partial, reference), .infinity)
    }

    func testBriefTwoHandMovementAtTenFramesPerSecond() {
        func hands(_ time: Double, _ progress: Double) -> [TrackedHand] {
            [0, 1].map { index in
                TrackedHand(id: index, features: HandFeatures(timestamp: time,
                    palmX: index == 0 ? 0.2 + 0.2 * progress : 0.8 - 0.2 * progress,
                    palmY: 0.5, confidence: 1, pose: .open, fingerExtensions: [1, 1, 1, 1]))
            }
        }
        let frames = (0...20).map { hands(Double($0) * 0.03, Double($0) / 20) }
        let template = GestureTemplate(duration: 0.6,
            frames: GestureMatcher.resample(frames.map { $0[0].features }, count: 32),
            secondaryFrames: GestureMatcher.resample(frames.map { $0[1].features }, count: 32))
        let gesture = SavedGesture(name: "Quick pair", binding: .scrollDown, samples: Array(repeating: template, count: 3))
        var matcher = MultiHandMatcher()
        var count = 0
        for index in 0...8 {
            if matcher.consume(hands(10 + Double(index) * 0.1, min(1, Double(index) / 6)), gestures: [gesture]) != nil {
                count += 1
            }
        }
        XCTAssertEqual(count, 1)
    }

    func testBriefDynamicMovementAtTenFramesPerSecond() {
        func frame(_ time: Double, _ progress: Double) -> HandFeatures {
            HandFeatures(timestamp: time, palmX: 0.8 - 0.4 * progress, palmY: 0.5,
                         confidence: 1, pose: .open, fingerExtensions: [1, 1, 1, 1])
        }
        let frames = (0...20).map { frame(Double($0) * 0.03, Double($0) / 20) }
        let template = GestureTemplate(duration: 0.6, frames: GestureMatcher.resample(frames, count: 32))
        let gesture = SavedGesture(name: "Quick swipe", binding: .scrollDown, samples: Array(repeating: template, count: 3))
        var matcher = GestureMatcher()
        var count = 0
        for index in 0...8 {
            if matcher.consume(frame(10 + Double(index) * 0.1, min(1, Double(index) / 6)), gestures: [gesture]) != nil {
                count += 1
            }
        }
        XCTAssertEqual(count, 1)
    }
}
