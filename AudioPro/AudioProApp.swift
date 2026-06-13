// ============================================================================
// AudioProApp.swift
// Entry Point - AudioPro Application
// ============================================================================

import SwiftUI
import UserNotifications

@main
struct AudioProApp: App {
    @NSApplicationDelegateAdaptor(AudioProAppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()

    init() {
        // Richiedi permessi per le notifiche all'avvio
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Errore richiesta permessi notifiche: \(error.localizedDescription)")
            }
        }
        NotificationManager.shared.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .task {
                    appDelegate.transcriptionModel = session.transcriptionModel
                }
        }
        .windowStyle(.hiddenTitleBar)
        // Sidebar (~220) + dettaglio + inspector opzionale (360)
        .defaultSize(width: 920, height: 620)
        .commands {
            PlayerCommands()
        }
    }
}
