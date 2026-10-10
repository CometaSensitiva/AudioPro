// ============================================================================
// AudioProApp.swift
// Entry Point - AudioPro Application
// ============================================================================

import SwiftUI

@main
struct AudioProApp: App {
    @NSApplicationDelegateAdaptor(AudioProAppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()

    init() {
        NotificationManager.shared.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .environment(\.locale, Locale(identifier: "it_IT"))
                .task {
                    appDelegate.session = session
                }
        }
        .windowStyle(.hiddenTitleBar)
        // Sidebar (~220) + dettaglio + inspector opzionale (360)
        .defaultSize(width: 1080, height: 700)
        .commands {
            AudioProCommands()
        }
    }
}
