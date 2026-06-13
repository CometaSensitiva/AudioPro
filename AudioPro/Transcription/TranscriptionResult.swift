import Foundation

nonisolated struct TranscriptionResult: Equatable, Sendable {
    let mediaURL: URL
    let srtURL: URL?
    let txtURL: URL?
    let cues: [SubtitleCue]

    var generatedURLs: [URL] {
        [srtURL, txtURL].compactMap { $0 }
    }

    var canOpenInPlayback: Bool {
        srtURL != nil
    }
}
