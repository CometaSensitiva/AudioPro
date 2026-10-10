import Foundation
import UserNotifications
import AppKit

protocol ExportNotifying {
    func prepareForExportNotifications()
    func notifyExportFinished(outputURL: URL)
    func notificationPermissionState() async -> NotificationPermissionState
    func requestNotificationPermission() async -> NotificationPermissionState
    @MainActor func openNotificationSettings()
}

extension ExportNotifying {
    func prepareForExportNotifications() {}
    func notificationPermissionState() async -> NotificationPermissionState { .unknown }
    func requestNotificationPermission() async -> NotificationPermissionState { .unknown }
    @MainActor func openNotificationSettings() {}
}

/// Gestisce le notifiche locali e l'apertura del Finder per l'export.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, ExportNotifying {
    static let shared = NotificationManager()
    private override init() {}
    
    private let center = UNUserNotificationCenter.current()
    private let exportCategory = "EXPORT_DONE"
    private let openAction = "OPEN_FOLDER"
    
    func configure() {
        center.delegate = self
        let open = UNNotificationAction(identifier: openAction, title: "Mostra in Finder", options: [.foreground])
        let category = UNNotificationCategory(identifier: exportCategory, actions: [open], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func prepareForExportNotifications() {
        Task {
            _ = await ensureAuthorizationIfNeeded()
        }
    }
    
    func notifyExportFinished(outputURL: URL) {
        Task {
            guard await ensureAuthorizationIfNeeded() else {
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Esportazione completata"
            content.body = outputURL.lastPathComponent
            content.categoryIdentifier = exportCategory
            content.userInfo = ["path": outputURL.path]

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await add(request)
            } catch {
                print("Errore invio notifica export: \(error.localizedDescription)")
            }
        }
    }

    func notificationPermissionState() async -> NotificationPermissionState {
        await currentPermissionState()
    }

    func requestNotificationPermission() async -> NotificationPermissionState {
        switch await currentPermissionState() {
        case .authorized:
            return .authorized
        case .notDetermined, .unknown:
            do {
                return try await requestAuthorization() ? .authorized : .denied
            } catch {
                print("Errore richiesta permessi notifiche: \(error.localizedDescription)")
                return .unavailable(error.localizedDescription)
            }
        case .denied:
            return .denied
        case .unavailable(let message):
            return .unavailable(message)
        }
    }

    @MainActor
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["path"] as? String else { return }
        let url = URL(fileURLWithPath: path)
        
        // Apri il Finder sul file esportato per default tap o azione "Mostra in Finder"
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier || response.actionIdentifier == openAction {
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func ensureAuthorizationIfNeeded() async -> Bool {
        let state = await requestNotificationPermission()
        if case .denied = state {
            print("Notifiche disattivate per AudioPro nelle impostazioni di macOS.")
        }
        return state.allowsNotifications
    }

    private func currentPermissionState() async -> NotificationPermissionState {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(
                    returning: Self.permissionState(for: settings.authorizationStatus)
                )
            }
        }
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private nonisolated static func permissionState(
        for authorizationStatus: UNAuthorizationStatus
    ) -> NotificationPermissionState {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .unavailable("Stato notifiche non riconosciuto.")
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
