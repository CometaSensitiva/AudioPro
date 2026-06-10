import SwiftUI

@main
struct TranscriptPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            TranscriptPlayerView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
