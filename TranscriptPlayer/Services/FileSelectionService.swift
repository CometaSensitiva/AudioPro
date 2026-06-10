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
        guard activePanel == nil else {
            activePanel?.makeKeyAndOrderFront(nil)
            return nil
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
                self?.activePanel = nil
                continuation.resume(returning: selectedURL)
            }
        }
    }
}
