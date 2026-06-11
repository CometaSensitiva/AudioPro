import Foundation

enum SRTParser {
    enum ParseError: LocalizedError, Equatable {
        case unreadableEncoding

        var errorDescription: String? {
            switch self {
            case .unreadableEncoding:
                return "Il file SRT non usa una codifica supportata."
            }
        }
    }

    static func load(from url: URL) throws -> [SubtitleCue] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw ParseError.unreadableEncoding
        }
        return parse(text)
    }

    static func parse(_ source: String) -> [SubtitleCue] {
        var normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if normalized.first == "\u{FEFF}" {
            normalized.removeFirst()
        }

        let blocks = makeBlocks(from: normalized)
        let parsed = blocks.enumerated().compactMap { order, lines -> ParsedCue? in
            guard let timelineIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                return nil
            }

            let timelineParts = lines[timelineIndex].components(separatedBy: "-->")
            guard timelineParts.count >= 2,
                  let start = parseTime(timelineParts[0]),
                  let endToken = timelineParts[1].split(whereSeparator: \.isWhitespace).first,
                  let end = parseTime(String(endToken)),
                  end >= start else {
                return nil
            }

            let text = lines
                .dropFirst(timelineIndex + 1)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { return nil }
            return ParsedCue(order: order, start: start, end: end, text: text)
        }

        return parsed
            .sorted {
                if $0.start == $1.start {
                    return $0.order < $1.order
                }
                return $0.start < $1.start
            }
            .enumerated()
            .map { id, cue in
                SubtitleCue(id: id, start: cue.start, end: cue.end, text: cue.text)
            }
    }

    private static func makeBlocks(from source: String) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String] = []

        for line in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    blocks.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            blocks.append(current)
        }
        return blocks
    }

    private static func parseTime(_ source: String) -> TimeInterval? {
        let parts = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":", omittingEmptySubsequences: false)

        guard parts.count == 3,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              let secondsPart = Double(parts[2]),
              hours >= 0,
              (0..<60).contains(minutes),
              secondsPart.isFinite,
              (0..<60).contains(secondsPart) else {
            return nil
        }

        return TimeInterval(hours * 3_600 + minutes * 60) + secondsPart
    }
}

private struct ParsedCue {
    let order: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}
