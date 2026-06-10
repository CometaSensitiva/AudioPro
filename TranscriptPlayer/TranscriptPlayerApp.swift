import SwiftUI

@main
struct TranscriptPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            TranscriptPlayerView()
        }
        .defaultSize(width: 520, height: 680)
        .commands {
            TranscriptPlayerCommands()
        }
    }
}

/// Azioni della finestra attiva, esposte ai menu tramite il focus system.
struct TranscriptPlayerActions {
    var isPlaying: Bool
    var hasMedia: Bool
    var togglePlayback: () -> Void
    var seekBy: (TimeInterval) -> Void
    var openMedia: () -> Void
    var openSRT: () -> Void
}

extension FocusedValues {
    @Entry var transcriptPlayerActions: TranscriptPlayerActions?
}

/// Menu File e Controlli: le scorciatoie vivono qui (HIG: scopribili dai menu),
/// non duplicate sui bottoni in finestra.
struct TranscriptPlayerCommands: Commands {
    @FocusedValue(\.transcriptPlayerActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Apri media…") { actions?.openMedia() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)
            Button("Apri SRT…") { actions?.openSRT() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
        CommandMenu("Controlli") {
            Button(actions?.isPlaying == true ? "Pausa" : "Riproduci") {
                actions?.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(actions?.hasMedia != true)

            Divider()

            Button("Indietro di 5 secondi") { actions?.seekBy(-5) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(actions?.hasMedia != true)
            Button("Avanti di 5 secondi") { actions?.seekBy(5) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(actions?.hasMedia != true)
        }
    }
}
