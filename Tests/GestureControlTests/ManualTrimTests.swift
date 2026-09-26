import XCTest
@testable import GestureControl

final class ManualTrimTests: XCTestCase {
    private func frame(_ index: Int, second: Bool = false, staticPose: Bool = false) -> HandFeatures {
        let progress = staticPose ? 0 : Double(min(35, max(15, index)) - 15) / 40
        return HandFeatures(timestamp: Double(index) * 0.05,
                            palmX: second ? 0.8 - progress : 0.2 + progress, palmY: 0.5,
                            confidence: 1, pose: .open, fingerExtensions: [1, 1, 1, 1],
                            jointAngles: Array(repeating: 0.5, count: 15),
                            normalizedJoints: Array(repeating: 0.5, count: 40))
    }

    func testManualLimitsKeepIdleLeadAndTail() throws {
        var recording = GestureRecording()
        for index in 0...60 { recording.append(frame(index)) }
        let manual = try recording.finish(automaticallyTrim: false)
        let automatic = try recording.finish()
        XCTAssertEqual(manual.duration, 3, accuracy: 0.0001)
        XCTAssertLessThan(automatic.duration, manual.duration)
        XCTAssertEqual(manual.frames.first!.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(manual.frames.last!.x, 0.7, accuracy: 0.0001)
    }

    func testSelectedFramesSetBothHandsEndpointsAndDuration() throws {
        var recording = MultiHandRecording()
        for index in 18...32 {
            recording.append([TrackedHand(id: 1, features: frame(index, second: true)),
                              TrackedHand(id: 0, features: frame(index))])
        }
        let template = try recording.finish(automaticallyTrim: false)
        XCTAssertEqual(template.duration, 0.7, accuracy: 0.0001)
        XCTAssertEqual(template.frames.first!.x, frame(18).palmX, accuracy: 0.0001)
        XCTAssertEqual(template.frames.last!.x, frame(32).palmX, accuracy: 0.0001)
        XCTAssertEqual(template.secondaryFrames!.first!.x, frame(18, second: true).palmX, accuracy: 0.0001)
        XCTAssertEqual(template.secondaryFrames!.last!.x, frame(32, second: true).palmX, accuracy: 0.0001)
    }

    func testManualStaticPosePreservesChosenDuration() throws {
        var single = GestureRecording()
        var double = MultiHandRecording()
        for index in 0...40 {
            single.append(frame(index, staticPose: true))
            double.append([TrackedHand(id: 0, features: frame(index, staticPose: true)),
                           TrackedHand(id: 1, features: frame(index, second: true, staticPose: true))])
        }
        for template in [try single.finish(automaticallyTrim: false), try double.finish(automaticallyTrim: false)] {
            XCTAssertEqual(template.isStatic, true)
            XCTAssertEqual(template.duration, 2, accuracy: 0.0001)
        }
    }

    func testTwoTenthsSecondCaptureAndRecognition() throws {
        func hands(_ index: Int, offset: Double = 100, reverse: Bool = false) -> [TrackedHand] {
            let progress = min(1, Double(index) / 4)
            return [0, 1].map { hand in
                let travel = 0.4 * (reverse ? 1 - progress : progress)
                return TrackedHand(id: hand, features: HandFeatures(
                    timestamp: offset + Double(index) * 0.05,
                    palmX: hand == 0 ? 0.2 + travel : 0.6 + travel * 0.5,
                    palmY: 0.5, confidence: 1, pose: .open, fingerExtensions: [1, 1, 1, 1]))
            }
        }
        var single = GestureRecording()
        var pair = MultiHandRecording()
        for index in 0...4 {
            single.append(hands(index)[0].features)
            pair.append(hands(index))
        }
        for autoTrim in [false, true] {
            let singleTemplate = try single.finish(automaticallyTrim: autoTrim)
            let pairTemplate = try pair.finish(automaticallyTrim: autoTrim)
            XCTAssertEqual(singleTemplate.duration, 0.2, accuracy: 0.000001)
            XCTAssertEqual(pairTemplate.duration, 0.2, accuracy: 0.000001)
            let one = SavedGesture(name: "Quick", binding: .scrollDown, samples: Array(repeating: singleTemplate, count: 3))
            let two = SavedGesture(name: "Quick pair", binding: .scrollDown, samples: Array(repeating: pairTemplate, count: 3))
            for reverse in [false, true] {
                var matcher = GestureMatcher()
                var pairMatcher = MultiHandMatcher()
                var singleMatches = 0, pairMatches = 0
                for index in 0...12 {
                    let input = hands(index, offset: 200, reverse: reverse)
                    if matcher.consume(input[0].features, gestures: [one]) != nil { singleMatches += 1 }
                    if pairMatcher.consume(input, gestures: [two]) != nil { pairMatches += 1 }
                }
                XCTAssertEqual(singleMatches, reverse ? 0 : 1)
                XCTAssertEqual(pairMatches, reverse ? 0 : 1)
            }
        }
    }

    func testMinimumDurationAndFrameCountAreBothRequired() {
        for (count, duration) in [(5, 0.19), (4, 0.2)] {
            var single = GestureRecording()
            var pair = MultiHandRecording()
            for index in 0..<count {
                let feature = HandFeatures(timestamp: Double(index) * duration / Double(count - 1),
                                           palmX: 0.2 + Double(index) * 0.1, palmY: 0.5,
                                           confidence: 1, pose: .open, fingerExtensions: [1, 1, 1, 1])
                single.append(feature)
                pair.append([TrackedHand(id: 0, features: feature), TrackedHand(id: 1, features: feature)])
            }
            XCTAssertThrowsError(try single.finish(automaticallyTrim: false))
            XCTAssertThrowsError(try pair.finish(automaticallyTrim: false))
        }
    }

    func testManualSelectionStillRejectsShortOrInterruptedTracking() {
        var short = GestureRecording()
        for index in 0...3 { short.append(frame(index)) }
        XCTAssertThrowsError(try short.finish(automaticallyTrim: false))
        var single = GestureRecording()
        var double = MultiHandRecording()
        for index in Array(0...20) + Array(40...60) {
            single.append(frame(index))
            double.append([TrackedHand(id: 0, features: frame(index)),
                           TrackedHand(id: 1, features: frame(index, second: true))])
        }
        XCTAssertThrowsError(try single.finish(automaticallyTrim: false))
        XCTAssertThrowsError(try double.finish(automaticallyTrim: false))
    }
}
