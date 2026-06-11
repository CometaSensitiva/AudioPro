import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class FileSelectionService: ObservableObject {
    private var activePanel: NSOpenPanel?

    func selectMedia() async -> URL? {
        await selectFile(
            allowedContentTypes: [.audio, .movie],
            message: "Seleziona un file audio o video.",
            prompt: "Scegli"
        )
    }

    func selectSRT() async -> URL? {
        var contentTypes: [UTType] = [.plainText]
        if let srtType = UTType(filenameExtension: "srt"), srtType != .plainText {
            contentTypes.insert(srtType, at: 0)
        }

        return await selectFile(
            allowedContentTypes: contentTypes,
            message: "Seleziona il file SRT della trascrizione.",
            prompt: "Scegli"
        )
    }

    private func selectFile(
        allowedContentTypes: [UTType],
        message: String,
        prompt: String
    ) async -> URL? {
        // L'ultima richiesta vince: un pannello già aperto (es. media) viene
        // annullato quando l'utente ne chiede un altro (es. SRT), invece di
        // rifocalizzare quello sbagliato e restituire nil in silenzio.
        if let activePanel {
            activePanel.cancel(nil)
            self.activePanel = nil
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = allowedContentTypes
        panel.message = message
        panel.prompt = prompt
        activePanel = panel

        return await withCheckedContinuation { continuation in
            panel.begin { [weak self, weak panel] response in
                let selectedURL = response == .OK ? panel?.url : nil
                // Azzera solo se è ancora il proprio pannello: il completion di
                // un pannello annullato non deve cancellare quello nuovo.
                if let self, let panel, self.activePanel === panel {
                    self.activePanel = nil
                }
                continuation.resume(returning: selectedURL)
            }
        }
    }
}
