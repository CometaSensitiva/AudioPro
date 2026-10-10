import Foundation

nonisolated enum NotificationPermissionState: Equatable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case unavailable(String)

    var allowsNotifications: Bool {
        if case .authorized = self {
            return true
        }
        return false
    }
}
