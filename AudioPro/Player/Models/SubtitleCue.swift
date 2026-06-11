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

        // Le cue possono sovrapporsi (annidate): se l'ultima per start non
        // contiene il tempo, risali finché una lo contiene. Restituisce la cue
        // iniziata più di recente che contiene il tempo. Nei gap di file non
        // sovrapposti la risalita è O(n) nel caso peggiore: irrilevante a 4 Hz.
        var index = lowerBound - 1
        while index >= 0 {
            if time <= cues[index].end {
                return cues[index].id
            }
            index -= 1
        }
        return nil
    }
}
