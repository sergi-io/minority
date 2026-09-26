import SwiftUI
import AVFoundation

@main
struct GestureControlApp: App {
    @StateObject private var state = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Minority", systemImage: state.enabled ? "hand.raised.fill" : "hand.raised") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable gesture control", isOn: Binding(get: { state.enabled }, set: state.setEnabled))
                Text("\(state.gestures.filter(\.isActive).count) active gestures")
                Text("Camera: \(state.cameraPermissionGranted ? "Allowed" : "Not allowed")")
                Text("Accessibility: \(state.accessibilityPermissionGranted ? "Allowed" : "Not allowed")")
                if !state.accessibilityPermissionGranted {
                    Button("Open Accessibility Settings") { state.openAccessibilitySettings() }
                    Text("Already enabled? Remove the old entry, add this app again, then relaunch it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Button("Gesture Manager…") { openWindow(id: "manager") }
                Button("Quit Minority") { NSApplication.shared.terminate(nil) }
            }
            .padding(8)
        }
        .menuBarExtraStyle(.window)

        Window("Gesture Manager", id: "manager") {
            GestureManagerView(state: state)
                .frame(minWidth: 980, minHeight: 700)
        }
        .defaultSize(width: 1120, height: 820)

        Window("Gesture Detection Log", id: "debug-log") {
            GestureDetectionLogView(state: state)
                .frame(minWidth: 480, minHeight: 320)
        }
        .defaultSize(width: 580, height: 430)
    }
}

private enum ActionKind: String, CaseIterable, Identifiable {
    case scrollDown = "Scroll down"
    case scrollUp = "Scroll up"
    case browserBack = "Browser back"
    case shortcut = "Keyboard shortcut"
    case text = "Type text"
    var id: String { rawValue }

    init(_ binding: GestureBinding) {
        switch binding {
        case .scrollDown: self = .scrollDown
        case .scrollUp: self = .scrollUp
        case .browserBack: self = .browserBack
        case .shortcut: self = .shortcut
        case .text: self = .text
        }
    }
}

private struct StatusPill: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11), in: Capsule())
    }
}

private struct GestureManagerView: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var shortcutCapture = ShortcutCapture()
    @State private var selectedID: UUID?
    @State private var name = ""
    @State private var actionText = ""
    @State private var actionKind: ActionKind = .scrollDown
    @State private var editorEnabled = true
    @State private var confirmDelete = false
    @State private var confirmDiscardCapture = false
    @State private var pendingSelectionID: UUID?
    @State private var selectedHandCount = 1
    @State private var saveFeedback: String?
    @State private var saveSucceeded = false

    private var selected: SavedGesture? { state.gestures.first { $0.id == selectedID } }

    private var hasUnsavedChanges: Bool {
        guard let selected else { return false }
        return name != selected.name || selectedBinding != selected.binding
            || editorEnabled != selected.enabled
            || (actionKind == .shortcut && !shortcutCapture.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var selectedBinding: GestureBinding? {
        switch actionKind {
        case .scrollDown: .scrollDown
        case .scrollUp: .scrollUp
        case .browserBack: .browserBack
        case .shortcut: shortcutCapture.value.map(GestureBinding.shortcut)
        case .text: .text(actionText)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                    Color.accentColor.opacity(0.055),
                                    Color(nsColor: .windowBackgroundColor)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                managerHeader
                Divider().opacity(0.5)
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 300)
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
                    mainPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { state.refresh() }
        .onDisappear { shortcutCapture.cancel() }
        .onChange(of: actionKind) { _ in shortcutCapture.cancel(); saveFeedback = nil }
        .onChange(of: selectedID) { _ in shortcutCapture.cancel() }
        .onChange(of: state.captureStage) { _ in shortcutCapture.cancel() }
        .onChange(of: state.isVerifying) { _ in shortcutCapture.cancel() }
        .confirmationDialog("Delete this gesture?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let selectedID { state.deleteGesture(id: selectedID); self.selectedID = nil }
            }
        }
        .confirmationDialog("Discard the unsaved recording?", isPresented: $confirmDiscardCapture) {
            Button("Discard and open gesture", role: .destructive) {
                state.discardCapture()
                if let pendingSelectionID,
                   let gesture = state.gestures.first(where: { $0.id == pendingSelectionID }) {
                    select(gesture)
                }
                pendingSelectionID = nil
            }
            Button("Keep recording", role: .cancel) { pendingSelectionID = nil }
        }
    }

    private var managerHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fingers.spread.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Minority").font(.headline)
                Text("Gesture studio").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(title: state.enabled ? "Control on" : "Control paused",
                       symbol: state.enabled ? "waveform" : "pause.fill",
                       tint: state.enabled ? .green : .secondary)
            StatusPill(title: "\(state.gestures.filter(\.isActive).count) active",
                       symbol: "hand.raised.fill", tint: .indigo)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: Binding(get: { state.enabled }, set: state.setEnabled)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gesture control").font(.subheadline.weight(.semibold))
                    Text(state.enabled ? "Listening for your gestures" : "Turn on when ready")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06)))

            HStack {
                Text("YOUR GESTURES")
                    .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                Spacer()
                Text("\(state.gestures.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if state.gestures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "hand.draw").font(.title2).foregroundStyle(.indigo)
                    Text("Your gesture library is empty").font(.subheadline.weight(.semibold))
                    Text("Record a movement, test it, then choose what it should do.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.gestures) { gesture in gestureRow(gesture) }
                    }
                    .padding(.vertical, 1)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("RECORD WITH").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                Picker("Hands in gesture", selection: $selectedHandCount) {
                    Text("One hand").tag(1)
                    Text("Two hands").tag(2)
                }
                .pickerStyle(.segmented)
                Button {
                    selectedID = nil
                    name = ""
                    actionText = ""
                    actionKind = .scrollDown
                    shortcutCapture.value = nil
                    state.startRecording(handCount: selectedHandCount)
                } label: {
                    Label("Record new gesture", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
                .disabled(state.captureStage != .idle || state.capturedTemplate != nil || state.isVerifying)
            }

            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                Text("Gesture data stays on this Mac. Camera video is never saved.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func gestureRow(_ gesture: SavedGesture) -> some View {
        let isSelected = selectedID == gesture.id
        let tint = actionTint(gesture.binding)
        return Button {
            if state.capturedTemplate != nil {
                pendingSelectionID = gesture.id
                confirmDiscardCapture = true
            } else {
                select(gesture)
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: actionSymbol(gesture.binding))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(gesture.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if !gesture.isTrained {
                        Text("Needs recordings: \(gesture.samples.count)/\(SavedGesture.minimumRecordings)")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    Text("\(gesture.binding.title) · \(gesture.handCount) hand\(gesture.handCount == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                Circle().fill(gesture.isActive ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
            .padding(10)
            .background(isSelected ? Color.indigo.opacity(0.11) : Color.primary.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.indigo.opacity(0.5) : Color.primary.opacity(0.045), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state.captureStage != .idle)
    }

    private var mainPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected == nil ? "Build a gesture" : "Edit gesture")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Record a pose or movement three times, test recognition, and bind an action.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.setDebugEnabled(!state.debugEnabled)
                        if state.debugEnabled { openWindow(id: "debug-log") }
                    } label: {
                        Label("Debug log", systemImage: "waveform.path")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(state.debugEnabled ? .green : .indigo)
                }

                if let template = state.capturedTemplate, selected == nil, state.captureStage == .idle {
                    captureReview(template)
                }
                if (selected != nil || state.capturedTemplate != nil) && state.captureStage == .idle { gestureEditor }
                if state.captureStage != .idle { recordingPanel }

                livePreviewPanel
                permissionsPanel
                handDetailsPanel
                settingsPanel
                if let message = state.message {
                    Label(message, systemImage: state.captureVerified ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.callout).foregroundColor(state.captureVerified ? .green : .secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func captureReview(_ template: GestureTemplate) -> some View {
        HStack(spacing: 15) {
            Image(systemName: state.captureVerified ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: 26))
                .foregroundColor(state.captureVerified ? .green : .indigo)
                .frame(width: 52, height: 52)
                .background((state.captureVerified ? Color.green : Color.indigo).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(state.captureVerified ? "Gesture recognized" : "Your capture is ready")
                    .font(.headline)
                Text("\(template.handCount) hand\(template.handCount == 1 ? "" : "s") · \(String(format: "%.1f", template.duration)) sec · \(state.training.samples.count)/\(SavedGesture.minimumRecordings) recordings · Repeat the same movement.")
                    .font(.caption).foregroundStyle(.secondary)
                if !state.verificationFeedback.isEmpty {
                    Text(state.verificationFeedback)
                        .font(.caption).foregroundStyle(state.captureVerified ? .green : .secondary)
                }
            }
            Spacer(minLength: 10)
            if state.isVerifying {
                ProgressView().controlSize(.small)
                Button("Stop") {
                    state.stopVerification()
                    state.message = "Test stopped. You can try again."
                }
            } else if !state.training.isReady {
                Button("Record \(state.training.samples.count + 1) of \(SavedGesture.minimumRecordings)") {
                    state.recordNextExample()
                }
                .buttonStyle(.borderedProminent).tint(.indigo)
                .disabled(state.captureStage != .idle)
            } else {
                Button(state.captureVerified ? "Test again" : "Test gesture") { state.startVerification() }
                    .buttonStyle(.borderedProminent).tint(.indigo)
            }
            Menu {
                Button {
                    state.startRecording(handCount: template.handCount)
                } label: {
                    Label("Restart all recordings", systemImage: "arrow.counterclockwise")
                }
                Button("Add training example") { state.recordNextExample() }
                Button(role: .destructive) {
                    state.discardCapture()
                } label: {
                    Label("Discard capture", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .disabled(state.captureStage != .idle || state.isVerifying)
        }
        .padding(16)
        .background(LinearGradient(colors: [Color.indigo.opacity(0.11), Color.purple.opacity(0.055)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.indigo.opacity(0.12)))
    }

    private var livePreviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live preview", systemImage: "viewfinder")
                    .font(.headline)
                Spacer()
                StatusPill(title: state.detectedPose,
                           symbol: state.trackedHands.isEmpty ? "hand.raised" : "hand.raised.fingers.spread.fill",
                           tint: state.trackedHands.isEmpty ? .secondary : .green)
                Text(state.confidence, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.secondary)
            }
            if state.cameraPermissionGranted && (state.enabled || state.debugEnabled || state.isVerifying || state.captureStage != .idle) {
                CameraPreview(session: state.camera.session, hands: state.trackedHands,
                              mirrored: state.previewMirrored, imageSize: state.cameraFrameSize)
                    .aspectRatio(state.cameraFrameSize.width / state.cameraFrameSize.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Label("LIVE · wireframe is not saved", systemImage: "circle.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(12)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08)))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.metering.center.weighted")
                        .font(.system(size: 28)).foregroundStyle(.indigo)
                    Text("Preview is paused").font(.subheadline.weight(.semibold))
                    Text("Turn on control or Debug to start the camera and see your hand landmarks.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Start preview") { state.setDebugEnabled(true); openWindow(id: "debug-log") }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity).frame(height: 200)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            }
            HStack {
                Toggle("Mirror preview", isOn: Binding(get: { state.previewMirrored }, set: state.setPreviewMirrored))
                    .toggleStyle(.checkbox)
                Spacer()
                Text("Last action: \(state.lastAction)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(17)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.055)))
    }

    private var permissionsPanel: some View {
        HStack(spacing: 12) {
            permissionCard("Camera", allowed: state.cameraPermissionGranted, symbol: "camera.fill")
            permissionCard("Accessibility", allowed: state.accessibilityPermissionGranted, symbol: "hand.tap.fill")
            Spacer(minLength: 0)
            if !state.accessibilityPermissionGranted {
                Button("Open Settings") { state.openAccessibilitySettings() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func permissionCard(_ title: String, allowed: Bool, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(allowed ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(allowed ? "Ready" : "Permission needed").font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var handDetailsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hand detail").font(.headline)
            ForEach(0..<2, id: \.self) { handID in
                let hand = state.trackedHands.first { $0.id == handID }
                let extensions = hand.map { [$0.features.thumbExtension] + $0.features.fingerExtensions }
                    ?? Array(repeating: 0.0, count: 5)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Hand \(handID + 1)").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(hand.map { "\($0.features.landmarks.count)/21 joints · \($0.features.pose.rawValue)" }
                             ?? "No hand detected")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<min(5, extensions.count), id: \.self) { index in
                            VStack(spacing: 5) {
                                Text(["Thumb", "Index", "Middle", "Ring", "Little"][index])
                                    .font(.caption2).foregroundStyle(.secondary)
                                ProgressView(value: extensions[index])
                                    .tint(.indigo)
                                Text(hand == nil ? "—" : extensions[index].formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption.monospacedDigit().weight(.medium))
                            }
                            .frame(maxWidth: .infinity).padding(.horizontal, 7)
                        }
                    }
                }
                .padding(13)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(17)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transaction { $0.animation = nil }
    }

    private var recordingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state.captureStage {
            case .countdown(let seconds):
                Label("Get ready · \(seconds)", systemImage: "timer")
                    .font(.headline).foregroundStyle(.indigo)
                Text("Hold a clear pose or perform one complete movement. Keep all fingers visible.")
                    .font(.caption).foregroundStyle(.secondary)
            case .recording:
                HStack {
                    Label("Recording your gesture", systemImage: "record.circle.fill")
                        .font(.headline).foregroundStyle(.red)
                    Spacer()
                    Text("\(state.captureSamples) frames").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                TimelineView(.periodic(from: state.captureStartedAt, by: 0.1)) { timeline in
                    let elapsed = min(5, max(0, timeline.date.timeIntervalSince(state.captureStartedAt)))
                    VStack(alignment: .leading) {
                        Text(String(format: "REC · %.1f / 5.0 sec", elapsed)).monospacedDigit()
                        ProgressView(value: elapsed, total: 5).tint(.red)
                    }
                }
                Text(state.trackedHands.count < state.captureHandCount
                     ? "Tracking missing — keep the required hands visible."
                     : "Recording now. Stop when done; recording stops automatically at 5 seconds. Then trim the movement.")
                    .font(.caption).foregroundStyle(.secondary)
            case .reviewing:
                Label("Recording stopped · Trim movement", systemImage: "scissors")
                    .font(.headline).foregroundStyle(.indigo)
                Text("Only the colored section will be kept. Drag Start and End to choose the exact first and last frame. Dashed hand = start; solid hand = end.")
                    .font(.caption).foregroundStyle(.secondary)
            case .idle: EmptyView()
            }
            if !state.captureSequences.isEmpty && (state.captureStage == .recording || state.captureStage == .reviewing) {
                GestureTrailView(sequences: state.captureSequences,
                                 selection: state.captureStage == .reviewing ? state.trimRange : 0...max(0, state.captureSamples - 1),
                                 mirrored: state.previewMirrored, imageSize: state.cameraFrameSize)
                Text("Palm and fingertip trails · Hand 1: cyan · Hand 2: orange")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if state.captureStage == .reviewing {
                trimControls
            }
            HStack {
                if state.captureStage == .reviewing {
                    Button("Use selected movement") { state.acceptTrimmedRecording() }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                        .disabled(state.trimValidation != nil)
                }
                if state.captureStage == .recording {
                    Button("Stop and trim") { state.finishRecording() }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                        .disabled(state.captureSamples < 2)
                }
                Button("Cancel recording", role: .cancel) { state.cancelRecording() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(17)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.indigo.opacity(0.16)))
    }

    private var trimControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Start").frame(width: 40, alignment: .leading)
                Slider(value: Binding(get: { state.trimStart }, set: { state.trimStart = min($0, state.trimEnd - 1) }),
                       in: 0...Double(max(1, state.captureSamples - 1)), step: 1)
                    .accessibilityLabel("Movement start")
                Text(String(format: "%.2f s", state.captureTime(at: state.trimRange.lowerBound))).monospacedDigit()
            }
            HStack {
                Text("End").frame(width: 40, alignment: .leading)
                Slider(value: Binding(get: { state.trimEnd }, set: { state.trimEnd = max($0, state.trimStart + 1) }),
                       in: 0...Double(max(1, state.captureSamples - 1)), step: 1)
                    .accessibilityLabel("Movement end")
                Text(String(format: "%.2f s", state.captureTime(at: state.trimRange.upperBound))).monospacedDigit()
            }
            HStack {
                Text(String(format: "Selected: %.2f sec · %d frames",
                            state.captureTime(at: state.trimRange.upperBound) - state.captureTime(at: state.trimRange.lowerBound),
                            state.trimRange.count))
                Spacer()
                Button("Reset trim") { state.trimStart = 0; state.trimEnd = Double(state.captureSamples - 1) }
            }
            .font(.caption)
            if let error = state.trimValidation {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Fine tune", systemImage: "slider.horizontal.3").font(.headline)
            HStack(spacing: 16) {
                Label("Scroll amount", systemImage: "arrow.down.to.line")
                    .font(.caption).frame(width: 125, alignment: .leading)
                Slider(value: Binding(get: { Double(state.scrollAmount) },
                                      set: { state.updateScroll(Int($0.rounded())) }), in: 0...25, step: 1)
                    .tint(.indigo)
                Text("\(state.scrollAmount)").font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 22, alignment: .trailing)
            }
            HStack(spacing: 16) {
                Label("Sensitivity", systemImage: "scope")
                    .font(.caption).frame(width: 125, alignment: .leading)
                Slider(value: Binding(get: { state.sensitivity }, set: state.updateSensitivity), in: 0.7...1.5)
                    .tint(.indigo)
                Text(state.sensitivity, format: .number.precision(.fractionLength(1)))
                    .font(.caption.monospacedDigit().weight(.semibold)).frame(width: 22, alignment: .trailing)
            }
        }
        .padding(17)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.055)))
    }

    private func actionSymbol(_ binding: GestureBinding) -> String {
        switch binding {
        case .scrollDown: "arrow.down"
        case .scrollUp: "arrow.up"
        case .browserBack: "arrow.left"
        case .shortcut: "keyboard"
        case .text: "text.cursor"
        }
    }

    private func actionTint(_ binding: GestureBinding) -> Color {
        switch binding {
        case .scrollDown: .blue
        case .scrollUp: .teal
        case .browserBack: .orange
        case .shortcut: .purple
        case .text: .mint
        }
    }

    @ViewBuilder
    private var gestureEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.indigo)
                    .frame(width: 34, height: 34)
                    .background(Color.indigo.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected == nil ? "Name and action" : "Gesture settings")
                        .font(.headline)
                    Text(selected == nil ? "Choose how this gesture should behave." : "Update the name, action, or availability.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            TextField("Gesture name", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("Action", selection: $actionKind) {
                ForEach(ActionKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            .pickerStyle(.menu)

            if actionKind == .text {
                Text("Text to type").font(.subheadline.weight(.semibold))
                TextEditor(text: $actionText)
                    .font(.body)
                    .frame(minHeight: 90, maxHeight: 160)
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                    .accessibilityLabel("Text to type when the gesture is recognized")
                Text("The gesture types this text into the focused app. Spaces and line breaks are preserved. Accessibility permission is required.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if actionKind == .shortcut {
                ShortcutChipsEditor(editor: shortcutCapture)
                    .id(selectedID)
                    .disabled(shortcutCapture.isCapturing)
                HStack {
                    Label(shortcutCapture.value?.title ?? "No shortcut recorded", systemImage: "keyboard")
                        .font(.subheadline.monospaced())
                    Spacer()
                    Button(shortcutCapture.isCapturing ? "Press a key…" : "Record shortcut") {
                        if shortcutCapture.isCapturing { shortcutCapture.cancel() }
                        else { shortcutCapture.start() }
                    }
                }
                if shortcutCapture.isCapturing {
                    ShortcutCaptureField(capture: shortcutCapture)
                        .frame(height: 42)
                }
                Text("Click Record shortcut, then press the combination (for example ⌘⌥→). Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if selected != nil {
                Text("\(selected?.samples.count ?? 0) recordings · minimum \(SavedGesture.minimumRecordings) for detection")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Enable when training is complete", isOn: $editorEnabled)
                    .toggleStyle(.switch)
                HStack(spacing: 10) {
                    Button("Save changes") { save() }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                        .disabled(shortcutCapture.isCapturing || state.isVerifying)
                    Button("Add another recording") {
                        if let selectedID { state.startRecording(addingTo: selectedID) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.captureStage != .idle)
                    .help("Record the same gesture at a different speed or distance to improve recognition.")
                    Spacer()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                        .buttonStyle(.borderless)
                }
                Text("Add 3–5 examples of the same movement with natural changes in speed and distance. Keep both hands coordinated for two-hand gestures.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Button {
                        save()
                    } label: {
                        Label("Save gesture", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent).tint(.indigo)
                    .disabled(!state.training.canSave || state.isVerifying || state.captureStage != .idle)
                    if !state.captureVerified {
                        Label(state.training.isReady ? "Test first to unlock saving" : "Record at least three examples", systemImage: "lock.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if hasUnsavedChanges && (saveFeedback == nil || saveSucceeded) {
                Label("Unsaved changes", systemImage: "pencil.circle")
                    .font(.callout).foregroundStyle(.orange)
            } else if let saveFeedback {
                Label(saveFeedback, systemImage: saveSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(saveSucceeded ? .green : .orange)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.055)))
    }

    private func select(_ gesture: SavedGesture) {
        saveFeedback = nil
        selectedID = gesture.id
        name = gesture.name
        actionKind = ActionKind(gesture.binding)
        editorEnabled = gesture.enabled
        if case .text(let text) = gesture.binding { actionText = text }
        else { actionText = "" }
        if case .shortcut(let shortcut) = gesture.binding { shortcutCapture.value = shortcut }
        else { shortcutCapture.value = nil }
    }

    private func save() {
        saveSucceeded = false
        if actionKind == .shortcut, let error = shortcutCapture.prepareForSave() {
            saveFeedback = error
            return
        }
        if actionKind == .text && actionText.isEmpty {
            saveFeedback = "Enter the text this gesture should type."
            return
        }
        guard let binding = selectedBinding else {
            saveFeedback = "Complete a shortcut or choose another action."
            return
        }
        if let selectedID {
            saveSucceeded = state.updateGesture(id: selectedID, name: name, binding: binding, enabled: editorEnabled)
        } else if let id = state.createGesture(name: name, binding: binding),
                  let gesture = state.gestures.first(where: { $0.id == id }) {
            select(gesture)
            saveSucceeded = true
        }
        saveFeedback = state.message
    }

}

private struct GestureDetectionLogView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gesture Detection Log").font(.title2.bold())
                Text(state.debugEnabled ? "Live" : "Paused")
                    .font(.caption).foregroundColor(state.debugEnabled ? .green : .secondary)
                Spacer()
                Button("Clear log") { state.clearDetectionLog() }
                    .disabled(state.detectionEvents.isEmpty)
            }
            Text("Shows saved gesture matches in real time. Actions are sent only when control is enabled and Accessibility is allowed. This log stays in memory and is not saved.")
                .font(.caption).foregroundStyle(.secondary)
            if state.detectionEvents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No gestures detected yet").font(.headline)
                    Text("Perform a saved gesture in view of the camera.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(state.detectionEvents) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.gestureName).fontWeight(.medium)
                            Spacer()
                            Text(event.date, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text("\(event.handDescription) · \(event.actionName) · \(event.actionSent ? "Action sent" : "Preview only")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(16)
        .onDisappear { state.setDebugEnabled(false) }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let hands: [TrackedHand]
    let mirrored: Bool
    let imageSize: CGSize
    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        if let previewLayer = view.previewLayer {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspect
        }
        view.setPreviewMirrored(mirrored)
        view.imageSize = imageSize
        view.hands = hands
        return view
    }
    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.setPreviewMirrored(mirrored)
        nsView.imageSize = imageSize
        nsView.hands = hands
    }
}

final class PreviewView: NSView {
    private let bones = [CAShapeLayer(), CAShapeLayer()]
    private let joints = [CAShapeLayer(), CAShapeLayer()]
    private let labels = [CATextLayer(), CATextLayer()]
    private var previewIsMirrored = false
    var imageSize = CGSize(width: 640, height: 480) { didSet { drawSkeleton() } }
    var hands: [TrackedHand] = [] { didSet { drawSkeleton() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer = AVCaptureVideoPreviewLayer()
        let colors = [NSColor.systemCyan, NSColor.systemPink]
        for index in 0..<2 {
            bones[index].strokeColor = colors[index].cgColor
            bones[index].fillColor = NSColor.clear.cgColor
            bones[index].lineWidth = 2.5
            bones[index].lineCap = .round
            joints[index].fillColor = colors[index].cgColor
            labels[index].foregroundColor = colors[index].cgColor
            labels[index].fontSize = 15
            labels[index].string = "\(index + 1)"
            layer?.addSublayer(bones[index])
            layer?.addSublayer(joints[index])
            layer?.addSublayer(labels[index])
        }
    }

    var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

    func setPreviewMirrored(_ mirrored: Bool) {
        if let connection = previewLayer?.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirrored != mirrored { connection.isVideoMirrored = mirrored }
        }
        if previewIsMirrored != mirrored {
            previewIsMirrored = mirrored
            drawSkeleton()
        }
    }

    override func layout() {
        super.layout()
        for index in 0..<2 {
            bones[index].frame = bounds
            joints[index].frame = bounds
        }
        drawSkeleton()
    }

    private func drawSkeleton() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in 0..<2 {
            var points: [Int: CGPoint] = [:]
            if let hand = hands.first(where: { $0.id == index }) {
                for landmark in hand.features.landmarks {
                    points[landmark.id] = HandSkeletonGeometry.project(landmark, into: bounds.size,
                                                                       imageSize: imageSize,
                                                                       flipX: !previewIsMirrored)
                }
            }
            let linePath = CGMutablePath()
            for (start, end) in HandSkeletonGeometry.edges {
                guard let a = points[start], let b = points[end] else { continue }
                linePath.move(to: a)
                linePath.addLine(to: b)
            }
            let dotPath = CGMutablePath()
            for point in points.values {
                dotPath.addEllipse(in: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            }
            bones[index].path = linePath
            joints[index].path = dotPath
            labels[index].frame = points[0].map {
                CGRect(x: $0.x + 8, y: $0.y + 8, width: 22, height: 20)
            } ?? .zero
        }
        CATransaction.commit()
    }
}
