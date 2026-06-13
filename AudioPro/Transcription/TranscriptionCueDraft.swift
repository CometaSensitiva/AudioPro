import Foundation

nonisolated struct TranscriptionCueDraft: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}
