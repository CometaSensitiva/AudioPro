import Combine
import SwiftUI

/// Contesto unico dei comandi della scena. L'azione File e la ricerca cambiano
/// nome e comportamento con la sezione attiva; i controlli di riproduzione sono
/// indipendenti dalla sezione, così possono restare disponibili mentre un media
/// continua a suonare in background.
struct AudioProCommandContext {
    struct Action {
        let title: String
        let isEnabled: Bool
        let perform: () -> Void

        init(
            _ title: String,
            isEnabled: Bool = true,
            perform: @escaping () -> Void
        ) {
            self.title = title
            self.isEnabled = isEnabled
            self.perform = perform
        }
    }

    struct Playback {
        let isPlaying: Bool
        let hasMedia: Bool
        let togglePlayback: () -> Void
        let seekBy: (TimeInterval) -> Void
    }

    let primaryFileAction: Action
    let secondaryFileAction: Action?
    let searchAction: Action?
    let playback: Playback?

    static func export(
        canAddFiles: Bool,
        addFiles: @escaping () -> Void,
        canSearchQueue: Bool,
        searchQueue: @escaping () -> Void,
        playback: Playback? = nil
    ) -> Self {
        Self(
            primaryFileAction: Action(
                "Aggiungi file…",
                isEnabled: canAddFiles,
                perform: addFiles
            ),
            secondaryFileAction: nil,
            searchAction: Action(
                "Cerca nella coda…",
                isEnabled: canSearchQueue,
                perform: searchQueue
            ),
            playback: playback
        )
    }

    static func transcription(
        canChooseMedia: Bool,
        chooseMedia: @escaping () -> Void,
        playback: Playback? = nil
    ) -> Self {
        Self(
            primaryFileAction: Action(
                "Scegli file…",
                isEnabled: canChooseMedia,
                perform: chooseMedia
            ),
            secondaryFileAction: nil,
            searchAction: nil,
            playback: playback
        )
    }

    static func player(
        canOpenMedia: Bool = true,
        openMedia: @escaping () -> Void,
        canOpenSRT: Bool = true,
        openSRT: @escaping () -> Void,
        canSearchTranscript: Bool,
        searchTranscript: @escaping () -> Void,
        playback: Playback
    ) -> Self {
        Self(
            primaryFileAction: Action(
                "Apri file…",
                isEnabled: canOpenMedia,
                perform: openMedia
            ),
            secondaryFileAction: Action(
                "Apri SRT…",
                isEnabled: canOpenSRT,
                perform: openSRT
            ),
            searchAction: Action(
                "Cerca nella trascrizione…",
                isEnabled: canSearchTranscript,
                perform: searchTranscript
            ),
            playback: playback
        )
    }
}

/// Adattatore stretto fra PlayerController e le schermate che devono esporre
/// soltanto i comandi di riproduzione. Osserva esclusivamente i due stati usati
/// dal menu, evitando che `currentTime` ridisegni Export e Trascrizione 4×/s.
@MainActor
final class PlaybackCommandBridge: ObservableObject {
    @Published private(set) var isPlaying: Bool
    @Published private(set) var hasMedia: Bool

    private weak var playerController: PlayerController?
    private var cancellables = Set<AnyCancellable>()

    init(playerController: PlayerController) {
        self.playerController = playerController
        self.isPlaying = playerController.isPlaying
        self.hasMedia = playerController.hasMedia

        playerController.$isPlaying
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                self?.isPlaying = isPlaying
            }
            .store(in: &cancellables)

        playerController.$hasMedia
            .removeDuplicates()
            .sink { [weak self] hasMedia in
                self?.hasMedia = hasMedia
            }
            .store(in: &cancellables)
    }

    var commandContext: AudioProCommandContext.Playback {
        AudioProCommandContext.Playback(
            isPlaying: isPlaying,
            hasMedia: hasMedia,
            togglePlayback: { [weak self] in
                self?.playerController?.togglePlayback()
            },
            seekBy: { [weak self] delta in
                self?.playerController?.seekBy(delta)
            }
        )
    }
}

extension FocusedValues {
    @Entry var audioProCommandContext: AudioProCommandContext?
}

/// Menu app-wide: File e Cerca riflettono la sezione attiva; Riproduzione resta
/// disponibile ogni volta che il contesto espone un player. Le azioni di
/// trasporto non registrano tasti senza modificatori: Spazio e frecce restano
/// al controllo con focus (lista, slider, menu, pulsante o campo di testo).
struct AudioProCommands: Commands {
    @FocusedValue(\.audioProCommandContext) private var commandContext

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            if let action = commandContext?.primaryFileAction {
                Button(action.title, action: action.perform)
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(action.isEnabled == false)
            }

            if let action = commandContext?.secondaryFileAction {
                Button(action.title, action: action.perform)
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(action.isEnabled == false)
            }
        }

        CommandGroup(after: .textEditing) {
            if let action = commandContext?.searchAction {
                Button(action.title, action: action.perform)
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(action.isEnabled == false)
            }
        }

        CommandMenu("Riproduzione") {
            Button(playback?.isPlaying == true ? "Pausa" : "Riproduci") {
                playback?.togglePlayback()
            }
            .disabled(playback?.hasMedia != true)

            Divider()

            Button("Indietro di 5 secondi") {
                playback?.seekBy(-5)
            }
            .disabled(playback?.hasMedia != true)

            Button("Avanti di 5 secondi") {
                playback?.seekBy(5)
            }
            .disabled(playback?.hasMedia != true)
        }
    }

    private var playback: AudioProCommandContext.Playback? {
        commandContext?.playback
    }
}
