import Foundation

nonisolated enum LocalTranscriptionState: Equatable, Sendable {
    case idle
    case selectingDestination
    case loadingModel
    case transcribing(progress: Double)
    case cancelling
    case completed(TranscriptionResult)
    case failed(message: String)

    var isBusy: Bool {
        switch self {
        case .selectingDestination, .loadingModel, .transcribing, .cancelling:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    var progressValue: Double? {
        guard case .transcribing(let progress) = self else { return nil }
        return min(max(progress, 0), 1)
    }

    var statusMessage: String? {
        switch self {
        case .idle:
            return nil
        case .selectingDestination:
            return "Scegli la cartella di destinazione."
        case .loadingModel:
            return "Caricamento del modello Whisper locale..."
        case .transcribing(let progress):
            return "Trascrizione locale in corso: \(Int(progress * 100))%"
        case .cancelling:
            return "Interruzione sicura e pulizia in corso..."
        case .completed(let result):
            let names = result.generatedURLs.map(\.lastPathComponent).joined(separator: ", ")
            return "Trascrizione salvata: \(names)"
        case .failed(let message):
            return message
        }
    }

    var activatesWaveform: Bool {
        switch self {
        case .loadingModel, .transcribing, .cancelling:
            return true
        case .idle, .selectingDestination, .completed, .failed:
            return false
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
    }
}
