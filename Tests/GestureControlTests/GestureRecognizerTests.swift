import XCTest
import AVFoundation
@testable import GestureControl

final class GestureRecognizerTests: XCTestCase {
    func testRecordAndRecognizeUserLeftSwipe() throws {
        var recording = GestureRecording()
        for i in 0...44 { recording.append(frame(Double(i) * 0.05, x: 0.8 - Double(i) * 0.01)) }
        let template = try recording.finish()
        let gesture = SavedGesture(name: "Left swipe", binding: .browserBack, samples: Array(repeating: template, count: 3))
        var matcher = GestureMatcher()
        var matches: [SavedGesture] = []
        for i in 0...44 {
            if let match = matcher.consume(frame(10 + Double(i) * 0.05, x: 0.8 - Double(i) * 0.01), gestures: [gesture]) {
                matches.append(match)
            }
        }
        XCTAssertEqual(matches.map(\.id), [gesture.id])
    }

    func testOppositeDirectionDoesNotMatch() throws {
        var recording = GestureRecording()
        for i in 0...44 { recording.append(frame(Double(i) * 0.05, x: 0.8 - Double(i) * 0.01)) }
        let gesture = SavedGesture(name: "Left", binding: .scrollDown, samples: Array(repeating: try recording.finish(), count: 3))
        var matcher = GestureMatcher()
        for i in 0...44 {
            XCTAssertNil(matcher.consume(frame(10 + Double(i) * 0.05, x: 0.3 + Double(i) * 0.01), gestures: [gesture]))
        }
    }

    func testSavedGestureReplaysAtDifferentSpeedsAfterReload() throws {
        var recording = GestureRecording()
        for index in 0...44 {
            recording.append(frame(Double(index) * 0.05, x: 0.8 - 0.4 * Double(index) / 44))
        }
        let gesture = SavedGesture(name: "Swipe", binding: .browserBack, samples: Array(repeating: try recording.finish(), count: 3))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("gestures.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = GestureStore(url: url)
        try store.save([gesture])
        let saved = try XCTUnwrap(store.load().first)
        for speed in [0.5, 0.7, 1.3, 2.0] {
            var matcher = GestureMatcher()
            var matches = 0
            for index in 0...44 {
                let timestamp = 10 + Double(index) * 0.05 * speed
                let x = 0.8 - 0.4 * Double(index) / 44
                if matcher.consume(frame(timestamp, x: x), gestures: [saved]) != nil { matches += 1 }
            }
            XCTAssertEqual(matches, 1, "Replay speed: \(speed)")
        }
        var opposite = GestureMatcher()
        for index in 0...44 {
            let timestamp = 20 + Double(index) * 0.05 * 0.7
            let x = 0.4 + 0.4 * Double(index) / 44
            XCTAssertNil(opposite.consume(frame(timestamp, x: x), gestures: [saved]))
        }
    }

    func testHeuristicMatchAllowsNonlinearTimingAndSmallerMotion() throws {
        var recording = GestureRecording()
        for index in 0...44 {
            recording.append(frame(Double(index) * 0.05, x: 0.8 - 0.4 * Double(index) / 44))
        }
        let gesture = SavedGesture(name: "Swipe", binding: .browserBack, samples: Array(repeating: try recording.finish(), count: 3))
        var matcher = GestureMatcher()
        var matches = 0
        for index in 0...44 {
            let progress = Double(index) / 44
            let x = 0.7 - 0.28 * pow(progress, 1.8)
            if matcher.consume(frame(10 + Double(index) * 0.05, x: x), gestures: [gesture]) != nil {
                matches += 1
            }
        }
        XCTAssertEqual(matches, 1)
    }

    func testAmbiguousGesturesDoNotFireAnAction() throws {
        var recording = GestureRecording()
        for index in 0...44 {
            recording.append(frame(Double(index) * 0.05, x: 0.8 - 0.4 * Double(index) / 44))
        }
        let template = try recording.finish()
        let first = SavedGesture(name: "One", binding: .scrollDown, samples: Array(repeating: template, count: 3))
        let second = SavedGesture(name: "Two", binding: .browserBack, samples: Array(repeating: template, count: 3))
        var matcher = GestureMatcher()
        for index in 0...44 {
            let x = 0.8 - 0.4 * Double(index) / 44
            XCTAssertNil(matcher.consume(frame(10 + Double(index) * 0.05, x: x),
                                         gestures: [first, second]))
        }
    }

    func testTwoHandGestureReplaysAtDifferentSpeeds() throws {
        var recording = MultiHandRecording()
        for index in 0...44 {
            recording.append(pair(Double(index) * 0.05, progress: Double(index) / 44))
        }
        let gesture = SavedGesture(name: "Two hands", binding: .scrollDown,
                                   samples: Array(repeating: try recording.finish(), count: 3))
        for speed in [0.5, 0.7, 1.3, 2.0] {
            var matcher = MultiHandMatcher()
            var matches = 0
            for index in 0...44 {
                let timestamp = 10 + Double(index) * 0.05 * speed
                if matcher.consume(pair(timestamp, progress: Double(index) / 44),
                                   gestures: [gesture]) != nil { matches += 1 }
            }
            XCTAssertEqual(matches, 1, "Replay speed: \(speed)")
        }
    }

    func testStaticHandCannotBeRecordedAsGesture() {
        var recording = GestureRecording()
        for i in 0...44 { recording.append(frame(Double(i) * 0.05, x: 0.5)) }
        XCTAssertThrowsError(try recording.finish())
    }

    func testRecordingTrimsIdleTimeAroundQuickGesture() throws {
        var recording = GestureRecording()
        for i in 0...44 {
            let progress = min(1, max(0, (Double(i) * 0.05 - 0.6) / 0.5))
            recording.append(frame(Double(i) * 0.05, x: 0.8 - 0.35 * progress))
        }
        let template = try recording.finish()
        XCTAssertLessThan(template.duration, 1.5)
        XCTAssertGreaterThan(template.duration, 0.4)
    }

    func testRecordedHandShapeChangeMatchesWithoutPalmMotion() throws {
        var recording = GestureRecording()
        for i in 0...44 {
            let progress = min(1, max(0, (Double(i) * 0.05 - 0.6) / 0.5))
            recording.append(frame(Double(i) * 0.05, x: 0.5, extensionValue: 0.9 - 0.8 * progress))
        }
        let gesture = SavedGesture(name: "Fist", binding: .scrollDown, samples: Array(repeating: try recording.finish(), count: 3))
        var matcher = GestureMatcher()
        var matched = false
        for i in 0...44 {
            let progress = min(1, max(0, (Double(i) * 0.05 - 0.6) / 0.5))
            matched = matcher.consume(frame(10 + Double(i) * 0.05, x: 0.5,
                                            extensionValue: 0.9 - 0.8 * progress), gestures: [gesture]) != nil || matched
        }
        XCTAssertTrue(matched)
    }

    func testSavedGestureAndShortcutRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("gestures.json")
        let store = GestureStore(url: url)
        let shortcut = ShortcutBinding(keyCode: 12, modifiers: 1 << 20, title: "⌘Q")
        let gesture = SavedGesture(name: "Close", binding: .shortcut(shortcut), samples: [])
        try store.save([gesture])
        XCTAssertEqual(try store.load(), [gesture])
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testMirroredCameraCoordinates() {
        XCTAssertEqual(UserRelativeCoordinates.x(fromMirroredImageX: 0.15), 0.15)
    }

    func testSkeletonProjectionRespectsAspectFitAndCameraDimensions() {
        let point = HandLandmark(id: 4, x: 0.5, y: 0.5, confidence: 1)
        let projected = HandSkeletonGeometry.project(point, into: CGSize(width: 320, height: 180))
        XCTAssertEqual(projected.x, 160, accuracy: 0.001)
        XCTAssertEqual(projected.y, 90, accuracy: 0.001)
        let side = HandLandmark(id: 8, x: 0.2, y: 0.5, confidence: 1)
        XCTAssertEqual(HandSkeletonGeometry.project(side, into: CGSize(width: 320, height: 180)).x,
                       88, accuracy: 0.001)
        XCTAssertEqual(HandSkeletonGeometry.project(side, into: CGSize(width: 320, height: 180), flipX: true).x,
                       232, accuracy: 0.001)
    }

    func testWidescreenCameraOverlayPreservesFullFrame() {
        let source = CGSize(width: 1920, height: 1080)
        let bottomLeft = HandLandmark(id: 0, x: 0, y: 0, confidence: 1)
        let topRight = HandLandmark(id: 1, x: 1, y: 1, confidence: 1)
        let preview = CGSize(width: 800, height: 450)
        XCTAssertEqual(HandSkeletonGeometry.project(bottomLeft, into: preview, imageSize: source), .zero)
        XCTAssertEqual(HandSkeletonGeometry.project(topRight, into: preview, imageSize: source),
                       CGPoint(x: 800, y: 450))
        XCTAssertEqual(HandSkeletonGeometry.project(bottomLeft, into: CGSize(width: 800, height: 600), imageSize: source),
                       CGPoint(x: 0, y: 75))
    }

    func testLegacyGestureFrameLoadsWithoutDetailedJoints() throws {
        let json = Data(#"{"x":0.5,"y":0.5,"fingers":[0.1,0.2,0.3,0.4]}"#.utf8)
        let frame = try JSONDecoder().decode(GestureVector.self, from: json)
        XCTAssertNil(frame.details)
        let oldTemplate = Data(#"{"duration":1.0,"frames":[{"x":0.5,"y":0.5,"fingers":[0.1,0.2,0.3,0.4]}]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(GestureTemplate.self, from: oldTemplate).handCount, 1)
    }

    func testThumbMotionIsDistinctFromIndexMotion() throws {
        var recording = GestureRecording()
        for index in 0...44 {
            let progress = min(1, max(0, (Double(index) * 0.05 - 0.6) / 0.5))
            recording.append(detailedFrame(Double(index) * 0.05, movingFinger: 0, progress: progress))
        }
        let gesture = SavedGesture(name: "Thumb", binding: .scrollDown, samples: Array(repeating: try recording.finish(), count: 3))
        var correctMatcher = GestureMatcher()
        var wrongMatcher = GestureMatcher()
        var correctMatch = false
        var wrongMatch = false
        for index in 0...44 {
            let progress = min(1, max(0, (Double(index) * 0.05 - 0.6) / 0.5))
            let timestamp = 10 + Double(index) * 0.05
            correctMatch = correctMatcher.consume(detailedFrame(timestamp, movingFinger: 0, progress: progress), gestures: [gesture]) != nil || correctMatch
            wrongMatch = wrongMatcher.consume(detailedFrame(timestamp, movingFinger: 1, progress: progress), gestures: [gesture]) != nil || wrongMatch
        }
        XCTAssertTrue(correctMatch)
        XCTAssertFalse(wrongMatch)
    }

    func testHandIdentityStaysWithEachHandWhenTheyCross() {
        var tracker = HandIdentityTracker()
        _ = tracker.assign([frame(0, x: 0.2), frame(0, x: 0.8)])
        _ = tracker.assign([frame(0.05, x: 0.4), frame(0.05, x: 0.6)])
        let crossed = tracker.assign([frame(0.10, x: 0.45), frame(0.10, x: 0.55)])
        XCTAssertEqual(crossed.first(where: { $0.id == 0 })?.features.palmX, 0.55)
        XCTAssertEqual(crossed.first(where: { $0.id == 1 })?.features.palmX, 0.45)
    }

    func testTwoHandGestureRequiresTwoHands() throws {
        var recording = MultiHandRecording()
        for index in 0...44 {
            let progress = Double(index) / 44
            recording.append(pair(Double(index) * 0.05, progress: progress))
        }
        let template = try recording.finish()
        XCTAssertEqual(template.handCount, 2)
        XCTAssertEqual(try JSONDecoder().decode(GestureTemplate.self, from: JSONEncoder().encode(template)).handCount, 2)
        let gesture = SavedGesture(name: "Two-hand pinch", binding: .scrollDown, samples: Array(repeating: template, count: 3))
        var matcher = MultiHandMatcher()
        var matchCount = 0
        for index in 0...44 {
            let progress = Double(index) / 44
            if matcher.consume(pair(10 + Double(index) * 0.05, progress: progress), gestures: [gesture]) != nil {
                matchCount += 1
            }
        }
        XCTAssertEqual(matchCount, 1)
        matcher.reset()
        for index in 0...44 {
            let progress = Double(index) / 44
            XCTAssertNil(matcher.consume(Array(pair(20 + Double(index) * 0.05, progress: progress).prefix(1)),
                                         gestures: [gesture]))
        }
    }

    func testPreviewViewCreatesLayerBeforeCameraSessionIsAttached() {
        let view = PreviewView(frame: .zero)
        XCTAssertNotNil(view.previewLayer)
    }

    func testDTWPreservesTwoHandCoordination() {
        func sequence(_ phase: (Double) -> Double) -> [GestureVector] {
            (0..<32).map { index in
                GestureVector(x: 0.5, y: 0.5,
                              fingers: Array(repeating: phase(Double(index) / 31), count: 4))
            }
        }
        let reference = sequence { $0 < 0.5 ? 0 : 1 }
        let early = sequence { $0 < 0.2 ? 0 : 1 }
        let late = sequence { $0 < 0.8 ? 0 : 1 }
        XCTAssertLessThan(GestureMatcher.score(early, reference), GestureMatcher.matchThreshold(1))
        XCTAssertLessThan(GestureMatcher.score(late, reference), GestureMatcher.matchThreshold(1))
        XCTAssertGreaterThan(GestureMatcher.sequenceScore([early, late], [reference, reference]),
                             GestureMatcher.matchThreshold(1.5))
        XCTAssertLessThan(GestureMatcher.sequenceScore([late, late], [reference, reference]),
                          GestureMatcher.matchThreshold(1))
    }

    func testStationaryAndWrongFinalShapeDoNotMatch() {
        let template = (0..<32).map { index in
            GestureVector(x: 0.5, y: 0.5, fingers: Array(repeating: Double(index) / 31, count: 4))
        }
        let stationary = Array(repeating: template[16], count: 32)
        XCTAssertGreaterThan(GestureMatcher.score(stationary, template), GestureMatcher.matchThreshold(1))
        var wrongEnd = template
        for index in 27..<32 { wrongEnd[index].fingers = [0, 0, 0, 0] }
        XCTAssertGreaterThan(GestureMatcher.score(wrongEnd, template), GestureMatcher.matchThreshold(1))
    }

    func testDetailedTemplatesRequireDetailedInputButLegacyStillMatches() {
        let legacy = (0..<16).map { index in
            GestureVector(x: Double(index) / 30, y: 0.5, fingers: [1, 1, 1, 1])
        }
        let detailed = legacy.map { vector in
            var result = vector
            result.details = Array(repeating: 0.5, count: 40)
            return result
        }
        XCTAssertEqual(GestureMatcher.score(legacy, detailed), .infinity)
        XCTAssertEqual(GestureMatcher.score(detailed, legacy), 0, accuracy: 0.001)
        var invalid = legacy
        invalid[8].x = .nan
        XCTAssertEqual(GestureMatcher.score(invalid, legacy), .infinity)
    }

    func testRepeatAfterReleaseAndTrackingLoss() throws {
        var recording = GestureRecording()
        for i in 0...44 { recording.append(frame(Double(i) * 0.05, x: 0.8 - Double(i) * 0.01)) }
        let gesture = SavedGesture(name: "Repeat", binding: .browserBack, samples: Array(repeating: try recording.finish(), count: 3))
        var matcher = GestureMatcher()
        var matches = 0
        for repetition in 0..<3 {
            let start = 10 + Double(repetition) * 5
            for i in 0...44 {
                if matcher.consume(frame(start + Double(i) * 0.05, x: 0.8 - Double(i) * 0.01),
                                   gestures: [gesture]) != nil { matches += 1 }
            }
            for i in 45...95 {
                XCTAssertNil(matcher.consume(frame(start + Double(i) * 0.05, x: 0.36), gestures: [gesture]))
            }
            if repetition == 1 { XCTAssertNil(matcher.consume(nil, gestures: [gesture])) }
        }
        XCTAssertEqual(matches, 3)
    }

    func testTwoHandThumbGestureCanRepeatAfterRelease() throws {
        func hands(_ time: Double, _ progress: Double) -> [TrackedHand] {
            [TrackedHand(id: 0, features: detailedFrame(time, movingFinger: 0, progress: progress)),
             TrackedHand(id: 1, features: detailedFrame(time, movingFinger: 0, progress: progress))]
        }
        var recording = MultiHandRecording()
        for i in 0...44 { recording.append(hands(Double(i) * 0.05, Double(i) / 44)) }
        let gesture = SavedGesture(name: "Thumbs", binding: .scrollDown, samples: Array(repeating: try recording.finish(), count: 3))
        var matcher = MultiHandMatcher()
        var matches = 0
        for repetition in 0..<2 {
            let start = 10 + Double(repetition) * 5
            for i in 0...44 {
                if matcher.consume(hands(start + Double(i) * 0.05, Double(i) / 44), gestures: [gesture]) != nil {
                    matches += 1
                }
            }
            for i in 45...95 {
                XCTAssertNil(matcher.consume(hands(start + Double(i) * 0.05, 1), gestures: [gesture]))
            }
        }
        XCTAssertEqual(matches, 2)
    }

    func testLegacySixteenFrameTemplateStillRecognizes() throws {
        let features = (0...44).map { frame(Double($0) * 0.05, x: 0.8 - Double($0) * 0.01) }
        let template = GestureTemplate(duration: 2.2, frames: GestureMatcher.resample(features, count: 16))
        let gesture = SavedGesture(name: "Legacy", binding: .browserBack, samples: Array(repeating: template, count: 3))
        var matcher = GestureMatcher()
        XCTAssertTrue(features.contains { matcher.consume($0, gestures: [gesture]) != nil })
    }

    func testTrainingRequiresThreeCapturesAndVerification() throws {
        var training = GestureTraining()
        for index in 0..<3 {
            let template = GestureTemplate(duration: 1 + Double(index) * 0.1,
                                           frames: [GestureVector(x: 0.5, y: 0.5, fingers: [1, 1, 1, 1])])
            training.append(template)
            XCTAssertEqual(training.samples.count, index + 1)
            XCTAssertEqual(training.isReady, index == 2)
            XCTAssertFalse(training.canSave)
        }
        training.verified = true
        XCTAssertTrue(training.canSave)
        training.append(training.samples[0])
        XCTAssertFalse(training.canSave, "Adding an example must invalidate the previous test")
        let count = training.samples.count
        training.append(GestureTemplate(duration: 1, frames: [], secondaryFrames: []))
        XCTAssertEqual(training.samples.count, count, "Do not mix hand counts during training")
        training = GestureTraining()
        XCTAssertTrue(training.samples.isEmpty)
        XCTAssertFalse(training.canSave)
    }

    func testIncompleteSavedTrainingNeverMatchesAndSurvivesReload() throws {
        var single = GestureRecording()
        var double = MultiHandRecording()
        for i in 0...44 {
            single.append(frame(Double(i) * 0.05, x: 0.8 - Double(i) * 0.01))
            double.append(pair(Double(i) * 0.05, progress: Double(i) / 44))
        }
        let oneTemplate = try single.finish(), twoTemplate = try double.finish()
        for count in 1...2 {
            let one = SavedGesture(name: "Incomplete", binding: .browserBack,
                                   samples: Array(repeating: oneTemplate, count: count))
            let two = SavedGesture(name: "Incomplete pair", binding: .scrollDown,
                                   samples: Array(repeating: twoTemplate, count: count))
            let loaded = try JSONDecoder().decode([SavedGesture].self, from: JSONEncoder().encode([one, two]))
            XCTAssertEqual(loaded, [one, two])
            XCTAssertTrue(loaded.allSatisfy { !$0.isActive })
            var matcher = GestureMatcher()
            var multi = MultiHandMatcher()
            for i in 0...44 {
                XCTAssertNil(matcher.consume(frame(10 + Double(i) * 0.05, x: 0.8 - Double(i) * 0.01), gestures: loaded))
                XCTAssertNil(multi.consume(pair(10 + Double(i) * 0.05, progress: Double(i) / 44), gestures: loaded))
            }
        }
    }

    func testAllTrainingExamplesPersist() throws {
        var training = GestureTraining()
        for duration in [1.0, 1.2, 1.5] {
            var recording = GestureRecording()
            for i in 0...44 {
                recording.append(frame(Double(i) / 44 * duration, x: 0.8 - Double(i) * 0.01))
            }
            training.append(try recording.finish())
        }
        let gesture = SavedGesture(name: "Trained", binding: .scrollDown, samples: training.samples)
        XCTAssertTrue(gesture.isActive)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("gestures.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = GestureStore(url: url)
        try store.save([gesture])
        XCTAssertEqual(try store.load(), [gesture])
    }

    private func frame(_ timestamp: Double, x: Double, extensionValue: Double = 0.9) -> HandFeatures {
        HandFeatures(timestamp: timestamp, palmX: x, palmY: 0.5, confidence: 0.95,
                     pose: .open, fingerExtensions: Array(repeating: extensionValue, count: 4))
    }

    private func detailedFrame(_ timestamp: Double, movingFinger: Int, progress: Double) -> HandFeatures {
        var joints = Array(repeating: 0.0, count: 40)
        for index in movingFinger * 8..<(movingFinger + 1) * 8 { joints[index] = progress }
        return HandFeatures(timestamp: timestamp, palmX: 0.5, palmY: 0.5, confidence: 0.95,
                            pose: .open, fingerExtensions: [0.9, 0.9, 0.9, 0.9], jointShape: joints)
    }

    private func pair(_ timestamp: Double, progress: Double) -> [TrackedHand] {
        [TrackedHand(id: 0, features: frame(timestamp, x: 0.2 + 0.2 * progress)),
         TrackedHand(id: 1, features: frame(timestamp, x: 0.8 - 0.2 * progress))]
    }
}
