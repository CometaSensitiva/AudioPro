import Foundation
import UserNotifications
import AppKit

/// Gestisce le notifiche locali e l'apertura del Finder per l'export.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
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
    
    func notifyExportFinished(outputURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Export completato"
        content.body = outputURL.lastPathComponent
        content.categoryIdentifier = exportCategory
        content.userInfo = ["path": outputURL.path]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
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
}
