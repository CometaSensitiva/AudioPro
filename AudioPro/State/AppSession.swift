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

    var hasActiveWork: Bool {
        appState.processingState.isBusy
            || transcriptionModel.state.isBusy
            || transcriptionModel.modelDownloadState.isBusy
    }

    var canTranscribeExportedFile: Bool {
        transcriptionModel.canAcceptMedia
    }

    var activeWorkDescription: String {
        var operations: [String] = []
        if appState.processingState.isBusy {
            operations.append("un’esportazione")
        }
        if transcriptionModel.state.isBusy {
            operations.append("una trascrizione")
        }
        if transcriptionModel.modelDownloadState.isBusy {
            operations.append("il download del modello Whisper")
        }
        guard let lastOperation = operations.popLast() else { return "" }
        guard operations.isEmpty == false else { return lastOperation }
        return "\(operations.joined(separator: ", ")) e \(lastOperation)"
    }

    func cancelAllAndWait() async {
        async let exportCancellation: Void = appState.cancelExportAndWait()
        async let transcriptionCancellation: Void = transcriptionModel.cancelAllAndWait()
        _ = await (exportCancellation, transcriptionCancellation)
    }

    @discardableResult
    func transcribeExportedFile(_ url: URL) -> Bool {
        guard transcriptionModel.selectMedia(url) else { return false }
        section = .transcription
        return true
    }

    func openInPlayback(_ result: TranscriptionResult) {
        playerModel.loadTranscriptionResult(result)
        section = .player
    }
}
