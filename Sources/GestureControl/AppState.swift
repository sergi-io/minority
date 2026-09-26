import AppKit
import AVFoundation
import SwiftUI

enum CaptureStage: Equatable {
    case idle
    case countdown(Int)
    case recording
    case reviewing
}

struct GestureDetectionEvent: Identifiable {
    let id = UUID()
    let date = Date()
    let gestureName: String
    let actionName: String
    let handDescription: String
    let actionSent: Bool
}

@MainActor
final class AppState: ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey: "gestureEnabled")
    @Published var gestures: [SavedGesture] = []
    @Published var confidence = 0.0
    @Published var detectedPose = "No hand detected"
    @Published var trackedHands: [TrackedHand] = []
    @Published private(set) var cameraFrameSize = CGSize(width: 640, height: 480)
    @Published var lastAction = "No gesture yet"
    @Published private(set) var debugEnabled = false
    @Published private(set) var detectionEvents: [GestureDetectionEvent] = []
    @Published var scrollAmount = UserDefaults.standard.object(forKey: "scrollAmount") as? Int ?? 3
    @Published var sensitivity = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 1.0
    @Published var previewMirrored = UserDefaults.standard.object(forKey: "previewMirrored") as? Bool ?? false
    @Published var captureStage: CaptureStage = .idle
    @Published var captureHandCount = 1
    @Published var captureSamples = 0
    @Published private(set) var captureSequences: [[HandFeatures]] = []
    @Published var trimStart = 0.0
    @Published var trimEnd = 0.0
    @Published var captureStartedAt = Date()

    var trimRange: ClosedRange<Int> {
        let last = max(0, (captureSequences.first?.count ?? 1) - 1)
        let start = min(last, max(0, Int(trimStart)))
        return start...max(start, min(last, Int(trimEnd)))
    }

    func captureTime(at index: Int) -> Double {
        guard let frames = captureSequences.first, frames.indices.contains(index) else { return 0 }
        return frames[index].timestamp - frames[0].timestamp
    }

    var trimValidation: String? {
        do { _ = try trimmedTemplate(); return nil }
        catch GestureRecordingError.tooShort { return "Select at least 0.2 seconds and 5 tracked frames." }
        catch GestureRecordingError.trackingLost { return "Tracking was lost inside this selection. Trim out the gap or record again." }
        catch { return error.localizedDescription }
    }

    private func trimmedTemplate() throws -> GestureTemplate {
        guard let first = captureSequences.first, !first.isEmpty else { throw GestureRecordingError.tooShort }
        if captureHandCount == 2 {
            var selected = MultiHandRecording()
            for index in trimRange {
                selected.append(captureSequences.enumerated().map { TrackedHand(id: $0.offset, features: $0.element[index]) })
            }
            return try selected.finish(automaticallyTrim: false)
        }
        var selected = GestureRecording()
        for index in trimRange { selected.append(first[index]) }
        return try selected.finish(automaticallyTrim: false)
    }
    @Published private(set) var training = GestureTraining()
    var capturedTemplate: GestureTemplate? { training.samples.last }
    @Published private(set) var isVerifying = false
    @Published private(set) var verificationCountdown: Int?
    @Published private(set) var verificationFeedback = ""
    private var verificationTrackedFrames = 0
    var captureVerified: Bool { training.verified }
    @Published var message: String?

    let camera = CameraManager()
    private let store: GestureStore
    private let emitter = SystemActionEmitter()
    private var matchers: [Int: GestureMatcher] = [:]
    private var multiMatcher = MultiHandMatcher()
    private var recording = GestureRecording()
    private var multiRecording = MultiHandRecording()
    private var captureHandID: Int?
    private var captureToken = UUID()
    private var captureTargetID: UUID?
    private var verificationToken = UUID()
    private var verificationSession: GestureVerificationSession?
    private var permissionTimer: Timer?
    private var cameraActive = false
    private var lastPreviewTimestamp = 0.0
    private var lastActionTimestamp = 0.0

    init(store: GestureStore = GestureStore(), startServices: Bool = true) {
        self.store = store
        do { gestures = try store.load() }
        catch { message = "Could not load saved gestures: \(error.localizedDescription)" }
        camera.onHands = { [weak self] hands in
            Task { @MainActor in self?.consume(hands) }
        }
        camera.onFrameSize = { [weak self] size in
            Task { @MainActor in self?.cameraFrameSize = size }
        }
        guard startServices else { return }
        refresh()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var cameraPermissionGranted: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    var accessibilityPermissionGranted: Bool { SystemActionEmitter.hasAccessibilityPermission }
    var canFinishRecording: Bool {
        if captureHandCount == 2 {
            guard let first = multiRecording.samples.first, let last = multiRecording.samples.last else { return false }
            return multiRecording.samples.count >= GestureCaptureLimits.minimumFrames && GestureCaptureLimits.accepts(duration: last.timestamp - first.timestamp)
        }
        guard let first = recording.samples.first, let last = recording.samples.last else { return false }
        return recording.samples.count >= GestureCaptureLimits.minimumFrames && GestureCaptureLimits.accepts(duration: last.timestamp - first.timestamp)
    }

    func refresh() {
        let shouldRun = cameraPermissionGranted && (enabled || debugEnabled || isVerifying || captureStage != .idle)
        if shouldRun && !cameraActive {
            cameraActive = true
            camera.start()
        } else if !shouldRun && cameraActive {
            cameraActive = false
            camera.stop()
            resetMatchers()
            trackedHands = []
            lastPreviewTimestamp = 0
            confidence = 0
            detectedPose = "No hand detected"
        }
        objectWillChange.send()
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "gestureEnabled")
        if value {
            if !cameraPermissionGranted { camera.start() }
            if !accessibilityPermissionGranted { SystemActionEmitter.requestAccessibilityPermission() }
        } else {
            resetMatchers()
        }
        refresh()
    }

    func setDebugEnabled(_ value: Bool) {
        debugEnabled = value
        if !value && !enabled { resetMatchers() }
        refresh()
    }

    func clearDetectionLog() {
        detectionEvents.removeAll()
    }

    func startRecording(addingTo targetID: UUID? = nil, handCount: Int = 1, continuingTraining: Bool = false) {
        guard captureStage == .idle else { return }
        guard cameraPermissionGranted else {
            message = "Allow camera access, then press Record again."
            camera.start()
            return
        }
        stopVerification()
        verificationFeedback = ""
        message = nil
        if !continuingTraining { training = GestureTraining() }
        training.verified = false
        captureTargetID = targetID
        captureHandCount = gestures.first(where: { $0.id == targetID })?.handCount ?? max(1, min(handCount, 2))
        recording = GestureRecording()
        multiRecording = MultiHandRecording()
        captureHandID = nil
        captureSamples = 0
        captureSequences = []
        resetMatchers()
        captureToken = UUID()
        let token = captureToken
        captureStage = .countdown(3)
        refresh()
        Task { @MainActor in
            for remaining in stride(from: 2, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard captureToken == token else { return }
                if remaining == 0 { captureStartedAt = Date() }
                captureStage = remaining == 0 ? .recording : .countdown(remaining)
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard captureToken == token else { return }
            finishRecording()
        }
    }

    func recordNextExample() {
        guard let template = capturedTemplate else { return }
        startRecording(handCount: template.handCount, continuingTraining: true)
    }

    func cancelRecording() {
        captureToken = UUID()
        captureStage = .idle
        captureTargetID = nil
        recording = GestureRecording()
        multiRecording = MultiHandRecording()
        captureHandID = nil
        captureSamples = 0
        captureSequences = []
        resetMatchers()
        refresh()
    }

    func finishRecording() {
        guard captureStage == .recording else { return }
        captureToken = UUID()
        guard captureSamples >= 2 else {
            cancelRecording()
            message = "No usable movement captured. Keep your hands visible and record again."
            return
        }
        trimStart = 0
        trimEnd = Double(captureSamples - 1)
        captureStage = .reviewing
        message = "Recording stopped. Adjust Start and End, then use the selected movement."
        refresh()
    }

    func acceptTrimmedRecording() {
        guard captureStage == .reviewing else { return }
        let target = captureTargetID
        do {
            let template = try trimmedTemplate()
            if let target, let index = gestures.firstIndex(where: { $0.id == target }) {
                var updated = gestures
                updated[index].samples.append(template)
                try persist(updated)
                message = "\(updated[index].name): \(updated[index].samples.count) recordings."
                    + (updated[index].isTrained ? " Ready for detection." : " At least three are required for detection.")
            } else {
                training.append(template)
                message = training.isReady
                    ? "\(training.samples.count) recordings ready. Test the gesture before saving."
                    : "Recording \(training.samples.count) of \(SavedGesture.minimumRecordings) captured. Record the same gesture again."
            }
        } catch {
            message = error.localizedDescription
            return
        }
        captureStage = .idle
        captureTargetID = nil
        defer { refresh() }
        recording = GestureRecording()
        multiRecording = MultiHandRecording()
        captureHandID = nil
        captureSamples = 0
        captureSequences = []
        resetMatchers()
    }

    func startVerification() {
        guard training.isReady, capturedTemplate != nil, captureStage == .idle, cameraPermissionGranted else { return }
        verificationToken = UUID()
        let token = verificationToken
        training.verified = false
        isVerifying = true
        verificationCountdown = 3
        verificationTrackedFrames = 0
        verificationFeedback = "Get ready · 3"
        verificationSession = GestureVerificationSession(samples: training.samples)
        message = "Wait for the countdown, then repeat the gesture. No action will be sent."
        refresh()
        Task { @MainActor in
            for remaining in stride(from: 2, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard verificationToken == token, isVerifying else { return }
                verificationCountdown = remaining == 0 ? nil : remaining
                verificationFeedback = remaining == 0 ? "Repeat the gesture now" : "Get ready · \(remaining)"
            }
            message = "Repeat the gesture now. No action will be sent."
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard verificationToken == token, isVerifying else { return }
            let result = verificationTrackedFrames == 0
                ? "No usable hand frames reached the test. Keep the hand inside the preview."
                : "Hand tracking worked, but the movement did not match. Repeat the full recorded path from its starting pose."
            stopVerification()
            verificationFeedback = result
            message = result
        }
    }

    func stopVerification() {
        verificationToken = UUID()
        isVerifying = false
        verificationCountdown = nil
        verificationSession = nil
        refresh()
    }

    func discardCapture() {
        stopVerification()
        training = GestureTraining()
        verificationFeedback = ""
        message = nil
    }

    @discardableResult
    func createGesture(name: String, binding: GestureBinding) -> UUID? {
        guard training.canSave, captureStage == .idle, !isVerifying else {
            message = "Record the gesture at least three times and pass Test before saving."
            return nil
        }
        if case .text(let text) = binding, text.isEmpty {
            message = "Enter the text this gesture should type."
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { message = "Enter a gesture name."; return nil }
        do {
            let gesture = SavedGesture(name: trimmed, binding: binding, samples: training.samples)
            try persist(gestures + [gesture])
            training = GestureTraining()
            message = "Saved \(trimmed)."
            return gesture.id
        } catch { message = error.localizedDescription; return nil }
    }

    @discardableResult
    func updateGesture(id: UUID, name: String, binding: GestureBinding, enabled: Bool) -> Bool {
        guard let index = gestures.firstIndex(where: { $0.id == id }) else {
            message = "This gesture no longer exists. Select a gesture and try again."
            return false
        }
        if case .text(let text) = binding, text.isEmpty {
            message = "Enter the text this gesture should type."
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { message = "Enter a gesture name."; return false }
        var updated = gestures
        updated[index].name = trimmed
        updated[index].binding = binding
        updated[index].enabled = enabled
        do { try persist(updated); message = "Saved changes to \(trimmed)."; return true }
        catch { message = error.localizedDescription; return false }
    }

    func deleteGesture(id: UUID) {
        do { try persist(gestures.filter { $0.id != id }); message = "Gesture deleted." }
        catch { message = error.localizedDescription }
    }

    func updateScroll(_ amount: Int) {
        scrollAmount = amount
        UserDefaults.standard.set(amount, forKey: "scrollAmount")
    }

    func updateSensitivity(_ value: Double) {
        sensitivity = value
        UserDefaults.standard.set(value, forKey: "sensitivity")
    }

    func setPreviewMirrored(_ value: Bool) {
        previewMirrored = value
        UserDefaults.standard.set(value, forKey: "previewMirrored")
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func persist(_ updated: [SavedGesture]) throws {
        try store.save(updated)
        gestures = updated
        resetMatchers()
    }

    private func resetMatchers() {
        matchers.removeAll()
        multiMatcher.reset()
    }

    private func consume(_ hands: [TrackedHand]) {
        if let timestamp = hands.first?.features.timestamp {
            if timestamp - lastPreviewTimestamp >= 0.05 {
                lastPreviewTimestamp = timestamp
                confidence = hands.map { $0.features.confidence }.reduce(0, +) / Double(hands.count)
                detectedPose = hands.count == 2 ? "Two hands detected" : "One hand: \(hands[0].features.pose.rawValue)"
                trackedHands = hands
            }
        } else if !trackedHands.isEmpty {
            confidence = 0
            detectedPose = "No hand detected"
            trackedHands = []
        }
        if captureStage == .recording {
            if captureHandCount == 2 { multiRecording.append(hands) }
            else {
                if captureHandID == nil { captureHandID = hands.first?.id }
                recording.append(hands.first(where: { $0.id == captureHandID })?.features)
            }
            captureSamples = captureHandCount == 2 ? multiRecording.samples.count : recording.samples.count
            captureSequences = captureHandCount == 2
                ? [multiRecording.samples.map(\.first), multiRecording.samples.map(\.second)]
                : [recording.samples]
            return
        }
        if isVerifying, let capturedTemplate {
            guard verificationCountdown == nil else { return }
            if hands.count < capturedTemplate.handCount {
                verificationFeedback = capturedTemplate.handCount == 2 ? "Keep both hands visible" : "Waiting for a hand"
            } else {
                verificationTrackedFrames += 1
                verificationFeedback = "Hand tracked · comparing the movement"
            }
            if verificationSession?.consume(hands, sensitivity: sensitivity) == true {
                verificationSucceeded()
            } else {
                updateVerificationScore(verificationSession?.closestScore)
            }
            return
        }
        guard captureStage == .idle, capturedTemplate == nil,
              debugEnabled || (enabled && accessibilityPermissionGranted) else { return }
        if hands.isEmpty { resetMatchers(); return }
        multiMatcher.sensitivity = sensitivity
        if let gesture = multiMatcher.consume(hands, gestures: gestures),
           let timestamp = hands.first?.features.timestamp, timestamp - lastActionTimestamp >= GestureMatcher.actionInterval {
            handleDetection(gesture, timestamp: timestamp, handDescription: "Two hands")
            return
        }
        for hand in hands {
            var matcher = matchers[hand.id] ?? GestureMatcher()
            matcher.sensitivity = sensitivity
            let matched = matcher.consume(hand.features, gestures: gestures)
            matchers[hand.id] = matcher
            if let matched, hand.features.timestamp - lastActionTimestamp >= GestureMatcher.actionInterval {
                handleDetection(matched, timestamp: hand.features.timestamp,
                                handDescription: "Hand \(hand.id + 1)")
                return
            }
        }
    }

    private func handleDetection(_ gesture: SavedGesture, timestamp: Double, handDescription: String) {
        lastActionTimestamp = timestamp
        let actionSent = enabled && accessibilityPermissionGranted
        if debugEnabled {
            detectionEvents.insert(GestureDetectionEvent(gestureName: gesture.name,
                                                         actionName: gesture.binding.title,
                                                         handDescription: handDescription,
                                                         actionSent: actionSent), at: 0)
            if detectionEvents.count > 100 { detectionEvents.removeLast() }
        }
        if actionSent { perform(gesture) }
    }

    private func updateVerificationScore(_ score: Double?) {
        guard let score, score.isFinite else { return }
        let limit = GestureMatcher.matchThreshold(sensitivity)
        verificationFeedback = score <= limit
            ? "Movement matched · confirming"
            : "Hand tracked · repeat the full path and hand shape"
    }

    private func verificationSucceeded() {
        stopVerification()
        training.verified = true
        verificationFeedback = "Gesture recognized"
        message = "Gesture recognized! Name it and save it."
    }

    private func perform(_ gesture: SavedGesture) {
        emitter.emit(gesture.binding, scrollAmount: scrollAmount)
        lastAction = "\(gesture.name) → \(gesture.binding.title)"
    }
}
