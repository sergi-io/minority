import CoreGraphics

enum HandSkeletonGeometry {
    static let edges: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4),
        (0, 5), (5, 6), (6, 7), (7, 8),
        (0, 9), (9, 10), (10, 11), (11, 12),
        (0, 13), (13, 14), (14, 15), (15, 16),
        (0, 17), (17, 18), (18, 19), (19, 20),
        (5, 9), (9, 13), (13, 17)
    ]

    // Vision uses a bottom-left origin. Capture frames are mirrored; an
    // unmirrored preview needs the opposite horizontal landmark coordinate.
    static func project(_ landmark: HandLandmark, into size: CGSize,
                        imageSize: CGSize = CGSize(width: 640, height: 480), flipX: Bool = false) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        // Match the preview layer's aspect-fit placement, including any letterboxing.
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let imageWidth = imageSize.width * scale
        let imageHeight = imageSize.height * scale
        let offsetX = (size.width - imageWidth) / 2
        let offsetY = (size.height - imageHeight) / 2
        let x = flipX ? 1 - landmark.x : landmark.x
        return CGPoint(x: offsetX + x * imageWidth,
                       y: offsetY + landmark.y * imageHeight)
    }
}
