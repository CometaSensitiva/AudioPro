import Combine
import Foundation

/// Stato della sezione Player, posseduto dalla root (ContentView): sopravvive
/// al cambio di sezione, così la riproduzione continua mentre si lavora
/// nella sezione Esportazione.
@MainActor
final class PlayerModel: ObservableObject {
    let playerController = PlayerController()
    let fileSelectionService = FileSelectionService()

    @Published var cues: [SubtitleCue] = []
    @Published var activeCueID: SubtitleCue.ID?
    @Published var srtFileName: String?
    @Published var srtErrorMessage: String?

    @Published var isTranscriptSearchVisible = false
    @Published var transcriptQuery = "" {
        didSet {
            if let currentMatchID, matchIDs.contains(currentMatchID) == false {
                self.currentMatchID = nil
            }
        }
    }
    @Published private(set) var currentMatchID: SubtitleCue.ID?

    /// Cue il cui testo contiene la query, ignorando maiuscole e accenti.
    var matchIDs: [SubtitleCue.ID] {
        let query = transcriptQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return [] }
        return cues
            .filter { $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .map(\.id)
    }

    var isEmpty: Bool {
        !playerController.hasMedia && cues.isEmpty
    }

    func clearAll() {
        playerController.unloadMedia()
        cues = []
        activeCueID = nil
        srtFileName = nil
        srtErrorMessage = nil
        closeTranscriptSearch()
    }

    func startTranscriptSearch() {
        guard cues.isEmpty == false else { return }
        isTranscriptSearchVisible = true
    }

    func closeTranscriptSearch() {
        isTranscriptSearchVisible = false
        transcriptQuery = ""
        currentMatchID = nil
    }

    func nextMatch() {
        advanceMatch(by: 1)
    }

    func previousMatch() {
        advanceMatch(by: -1)
    }

    /// Avanza ciclicamente tra i match e fa seek all'inizio della cue:
    /// il "fast forward alla parola" richiesto. Lo stato play/pausa resta
    /// quello corrente.
    private func advanceMatch(by offset: Int) {
        let matches = matchIDs
        guard matches.isEmpty == false else { return }

        let nextIndex: Int
        if let currentMatchID, let index = matches.firstIndex(of: currentMatchID) {
            nextIndex = (index + offset + matches.count) % matches.count
        } else {
            nextIndex = offset >= 0 ? 0 : matches.count - 1
        }

        let id = matches[nextIndex]
        currentMatchID = id
        if let cue = cues.first(where: { $0.id == id }) {
            playerController.seek(to: cue.start)
        }
    }

    func chooseMedia() {
        Task {
            guard let url = await fileSelectionService.selectMedia() else { return }
            playerController.loadMedia(from: url)
        }
    }

    func chooseSRT() {
        Task {
            guard let url = await fileSelectionService.selectSRT() else { return }
            handleSRTImport(url)
        }
    }

    func handleSRTImport(_ url: URL) {
        do {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let parsedCues = try SRTParser.load(from: url)
            cues = parsedCues
            currentMatchID = nil
            srtFileName = url.lastPathComponent
            srtErrorMessage = parsedCues.isEmpty
                ? "Il file SRT non contiene segmenti validi."
                : nil
            updateActiveCue(at: playerController.currentTime)
        } catch {
            cues = []
            activeCueID = nil
            currentMatchID = nil
            srtFileName = nil
            srtErrorMessage = "Impossibile leggere il file SRT: \(error.localizedDescription)"
        }
    }

    func updateActiveCue(at time: TimeInterval) {
        let nextCueID = SubtitleCueLookup.activeCueID(in: cues, at: time)
        guard nextCueID != activeCueID else { return }
        activeCueID = nextCueID
    }
}
