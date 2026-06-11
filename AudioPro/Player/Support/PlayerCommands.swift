import SwiftUI

/// Azioni della sezione Player attiva, esposte ai menu tramite il focus system.
/// Quando il Player non è a fuoco le voci risultano disabilitate (actions == nil).
struct PlayerActions {
    var isPlaying: Bool
    var hasMedia: Bool
    var canSearchTranscript: Bool
    var togglePlayback: () -> Void
    var seekBy: (TimeInterval) -> Void
    var openMedia: () -> Void
    var openSRT: () -> Void
    var startTranscriptSearch: () -> Void
}

extension FocusedValues {
    @Entry var playerActions: PlayerActions?
}

/// Menu File e Riproduzione: le scorciatoie vivono qui (HIG: scopribili dai menu),
/// non duplicate sui bottoni in finestra.
struct PlayerCommands: Commands {
    @FocusedValue(\.playerActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Apri media…") { actions?.openMedia() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)
            Button("Apri SRT…") { actions?.openSRT() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Cerca nella trascrizione…") { actions?.startTranscriptSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions?.canSearchTranscript != true)
        }

        CommandMenu("Riproduzione") {
            // Lo Spazio è registrato sul bottone play/pausa della barra di
            // trasporto, non qui: registrarlo due volte creerebbe ambiguità.
            Button(actions?.isPlaying == true ? "Pausa" : "Riproduci") {
                actions?.togglePlayback()
            }
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
