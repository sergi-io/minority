import Foundation
import Vision
import CoreVideo

final class HandPoseProcessor {
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()
    private var identity = HandIdentityTracker()

    func process(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [TrackedHand] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return identity.assign([]) }
        let detections = (request.results ?? []).compactMap { extract($0, timestamp: timestamp, imageAspectRatio: Double(CVPixelBufferGetWidth(pixelBuffer)) / Double(CVPixelBufferGetHeight(pixelBuffer))) }
        return identity.assign(detections)
    }

    private func extract(_ observation: VNHumanHandPoseObservation, timestamp: TimeInterval, imageAspectRatio: Double) -> HandFeatures? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        func point(_ name: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let value = points[name], value.confidence >= 0.3 else { return nil }
            return value.location
        }
        guard let wrist = point(.wrist),
              let indexMCP = point(.indexMCP), let middleMCP = point(.middleMCP),
              let ringMCP = point(.ringMCP), let littleMCP = point(.littleMCP) else { return nil }

        let palmXImage = Double((wrist.x + indexMCP.x + middleMCP.x + ringMCP.x + littleMCP.x) / 5)
        let palmY = Double((wrist.y + indexMCP.y + middleMCP.y + ringMCP.y + littleMCP.y) / 5)
        let fingerJoints: [[VNHumanHandPoseObservation.JointName]] = [
            [.thumbCMC, .thumbMP, .thumbIP, .thumbTip],
            [.indexMCP, .indexPIP, .indexDIP, .indexTip],
            [.middleMCP, .middlePIP, .middleDIP, .middleTip],
            [.ringMCP, .ringPIP, .ringDIP, .ringTip],
            [.littleMCP, .littlePIP, .littleDIP, .littleTip]
        ]
        let jointNames = [VNHumanHandPoseObservation.JointName.wrist] + fingerJoints.flatMap { $0 }
        let landmarks: [HandLandmark] = jointNames.enumerated().compactMap { index, name in
            guard let value = points[name], value.confidence >= 0.3 else { return nil }
            return HandLandmark(id: index, x: Double(value.location.x), y: Double(value.location.y),
                                confidence: Double(value.confidence))
        }

        guard let geometry = HandShapeGeometry(landmarks: landmarks, imageAspectRatio: imageAspectRatio) else { return nil }

        let palmWidth = max(0.04, distance(indexMCP, littleMCP))
        let handAxisLength = max(0.03, distance(wrist, middleMCP))
        let axisX = (middleMCP.x - wrist.x) / handAxisLength
        let axisY = (middleMCP.y - wrist.y) / handAxisLength
        var jointShape: [Double] = []
        for finger in fingerJoints {
            var fallback = wrist
            for name in finger {
                let joint = point(name) ?? fallback
                fallback = joint
                let dx = joint.x - wrist.x
                let dy = joint.y - wrist.y
                jointShape.append(Double((dx * axisY - dy * axisX) / palmWidth))
                jointShape.append(Double((dx * axisX + dy * axisY) / palmWidth))
            }
        }

        var extensions: [Double] = []
        for finger in fingerJoints.dropFirst() {
            guard let pip = point(finger[1]) ?? point(finger[0]) else {
                extensions.append(0.5)
                continue
            }
            let tip = point(finger[3]) ?? point(finger[2]) ?? pip
            let ratio = Double(distance(tip, wrist) / max(0.03, distance(pip, wrist)))
            extensions.append(min(1, max(0, (ratio - 0.75) / 0.65)))
        }
        let thumbTip = point(.thumbTip) ?? point(.thumbIP) ?? point(.thumbMP)
        let thumbExtension = thumbTip.map {
            min(1, max(0, (Double(distance($0, indexMCP) / palmWidth) - 0.4) / 0.9))
        } ?? 0.5
        let extended = extensions.filter { $0 >= 0.58 }.count
        let pose: HandPose = extended >= 3 ? .open : (extended <= 1 ? .closed : .other)
        let confidence = (
            Double(points[.wrist]?.confidence ?? 0) +
            Double(points[.indexMCP]?.confidence ?? 0) +
            Double(points[.middleMCP]?.confidence ?? 0) +
            Double(points[.ringMCP]?.confidence ?? 0) +
            Double(points[.littleMCP]?.confidence ?? 0)
        ) / 5
        let userX = UserRelativeCoordinates.x(fromMirroredImageX: palmXImage)
        return HandFeatures(timestamp: timestamp, palmX: userX, palmY: palmY,
                            confidence: confidence, pose: pose, fingerExtensions: extensions,
                            thumbExtension: thumbExtension, jointShape: jointShape,
                            landmarks: landmarks, jointAngles: geometry.angles, normalizedJoints: geometry.joints,
                            angleMask: geometry.angleMask, jointMask: geometry.jointMask)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
