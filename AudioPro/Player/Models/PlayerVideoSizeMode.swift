import CoreGraphics

enum PlayerVideoSizeMode: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case theater

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "Piccolo"
        case .medium: return "Medio"
        case .large: return "Grande"
        case .theater: return "Teatro"
        }
    }

    static func mode(forStoredRawValue rawValue: String) -> PlayerVideoSizeMode {
        if rawValue == "fit" {
            return .theater
        }
        return PlayerVideoSizeMode(rawValue: rawValue) ?? .theater
    }

    /// `reservedHeight` is the space kept free below the video (the
    /// transcript): outside Theater mode the video never takes it.
    func frame(in containerSize: CGSize, aspectRatio: CGFloat, reservedHeight: CGFloat = 0) -> CGSize {
        let safeAspectRatio = max(aspectRatio, 0.1)
        let maxWidth = max(280, containerSize.width - 32)
        let targetHeight = min(
            targetHeight(in: containerSize),
            max(160, containerSize.height - reservedHeight)
        )
        let widthLimitedHeight = maxWidth / safeAspectRatio
        let resolvedHeight = min(targetHeight, widthLimitedHeight)

        return CGSize(
            width: resolvedHeight * safeAspectRatio,
            height: resolvedHeight
        )
    }

    private func targetHeight(in containerSize: CGSize) -> CGFloat {
        let viewportLimit = max(260, min(720, containerSize.height * 0.82))
        switch self {
        case .small:
            return min(260, viewportLimit)
        case .medium:
            return min(360, viewportLimit)
        case .large:
            return min(500, viewportLimit)
        case .theater:
            return min(max(460, containerSize.height * 0.72), viewportLimit)
        }
    }
}
