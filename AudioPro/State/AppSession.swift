import Combine
import Foundation

@MainActor
final class AppSession: ObservableObject {
    @Published var section: AppSection = .merger

    let appState: AudioAppState
    let transcriptionModel: TranscriptionModel
    let playerModel: PlayerModel

    convenience init() {
        self.init(
            appState: AudioAppState(),
            transcriptionModel: TranscriptionModel(),
            playerModel: PlayerModel()
        )
    }

    init(
        appState: AudioAppState,
        transcriptionModel: TranscriptionModel,
        playerModel: PlayerModel
    ) {
        self.appState = appState
        self.transcriptionModel = transcriptionModel
        self.playerModel = playerModel
    }

    func transcribeExportedFile(_ url: URL) {
        transcriptionModel.selectMedia(url)
        section = .transcription
    }

    func openInPlayback(_ result: TranscriptionResult) {
        playerModel.loadTranscriptionResult(result)
        section = .player
    }
}
