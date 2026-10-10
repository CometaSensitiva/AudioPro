import Foundation

nonisolated enum WhisperModelDownloadState: Equatable, Sendable {
    case idle
    case downloading(progress: Double?)
    case cancelling
    case completed
    case failed(message: String)

    var isBusy: Bool {
        switch self {
        case .downloading, .cancelling:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    var progressValue: Double? {
        guard case .downloading(let progress) = self,
              let progress,
              progress.isFinite else {
            return nil
        }
        return min(max(progress, 0), 1)
    }

    var statusMessage: String? {
        switch self {
        case .idle:
            return nil
        case .downloading(let progress):
            if let progress, progress.isFinite {
                return "Download del modello Whisper: \(Int(min(max(progress, 0), 1) * 100))%"
            }
            return "Download del modello Whisper in corso…"
        case .cancelling:
            return "Interruzione del download del modello…"
        case .completed:
            return "Whisper Large v3 pronto"
        case .failed(let message):
            return message
        }
    }
}
