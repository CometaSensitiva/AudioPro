import Foundation

nonisolated struct TranscriptionOutput: Equatable, Sendable {
    let cues: [SubtitleCue]
    let srtText: String
    let plainText: String
}
