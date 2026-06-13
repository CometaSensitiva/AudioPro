import Foundation

enum TranscriptionOutputFormatter {
    nonisolated static func makeOutput(from drafts: [TranscriptionCueDraft]) -> TranscriptionOutput {
        let cues = makeSubtitleCues(from: drafts)
        return TranscriptionOutput(
            cues: cues,
            srtText: makeSRT(from: cues),
            plainText: makePlainText(from: cues)
        )
    }

    nonisolated static func makeSubtitleCues(from drafts: [TranscriptionCueDraft]) -> [SubtitleCue] {
        drafts
            .compactMap { draft -> TranscriptionCueDraft? in
                let text = cleanText(draft.text)
                guard text.isEmpty == false else { return nil }
                guard draft.start.isFinite, draft.end.isFinite, draft.end > draft.start else { return nil }
                return TranscriptionCueDraft(start: draft.start, end: draft.end, text: text)
            }
            .sorted {
                if $0.start == $1.start {
                    return $0.end < $1.end
                }
                return $0.start < $1.start
            }
            .enumerated()
            .map { index, draft in
                SubtitleCue(id: index, start: draft.start, end: draft.end, text: draft.text)
            }
    }

    nonisolated static func makeSRT(from cues: [SubtitleCue]) -> String {
        cues.enumerated()
            .map { index, cue in
                """
                \(index + 1)
                \(formatSRTTime(cue.start)) --> \(formatSRTTime(cue.end))
                \(cue.text)
                """
            }
            .joined(separator: "\n\n")
            .appending(cues.isEmpty ? "" : "\n")
    }

    nonisolated static func makePlainText(from cues: [SubtitleCue]) -> String {
        cues
            .map(\.text)
            .joined(separator: "\n")
            .appending(cues.isEmpty ? "" : "\n")
    }

    nonisolated static func formatSRTTime(_ seconds: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int((seconds * 1_000).rounded()))
        let milliseconds = totalMilliseconds % 1_000
        let totalSeconds = totalMilliseconds / 1_000
        let displaySeconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(
            format: "%02d:%02d:%02d,%03d",
            hours,
            minutes,
            displaySeconds,
            milliseconds
        )
    }

    nonisolated private static func cleanText(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"<\|[^|]+?\|>"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
