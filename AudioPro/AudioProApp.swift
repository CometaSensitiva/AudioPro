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
        .defaultSize(width: 480, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
