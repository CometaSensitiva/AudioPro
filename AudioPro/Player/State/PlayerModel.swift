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
            srtFileName = url.lastPathComponent
            srtErrorMessage = parsedCues.isEmpty
                ? "Il file SRT non contiene segmenti validi."
                : nil
            updateActiveCue(at: playerController.currentTime)
        } catch {
            cues = []
            activeCueID = nil
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
