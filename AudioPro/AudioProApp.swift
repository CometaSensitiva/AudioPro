// ============================================================================
// AudioProApp.swift
// Entry Point - AudioPro Application
// ============================================================================

import SwiftUI
import UserNotifications

@main
struct AudioProApp: App {
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
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        // Sidebar (~220) + dettaglio + inspector opzionale (360)
        .defaultSize(width: 920, height: 620)
        .commands {
            PlayerCommands()
        }
    }
}
