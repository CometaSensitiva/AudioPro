import Foundation

struct SubtitleCue: Identifiable, Equatable, Sendable {
    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

enum SubtitleCueLookup {
    static func activeCueID(
        in cues: [SubtitleCue],
        at time: TimeInterval
    ) -> SubtitleCue.ID? {
        guard time.isFinite, !cues.isEmpty else { return nil }

        var lowerBound = 0
        var upperBound = cues.count

        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if cues[middle].start <= time {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        guard lowerBound > 0 else { return nil }
        let candidate = cues[lowerBound - 1]
        return time <= candidate.end ? candidate.id : nil
    }
}
