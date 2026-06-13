import AppKit

@MainActor
final class AudioProAppDelegate: NSObject, NSApplicationDelegate {
    weak var transcriptionModel: TranscriptionModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let transcriptionModel, transcriptionModel.state.isBusy else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Trascrizione ancora in corso"
        alert.informativeText = """
        Uscendo ora AudioPro interromperà Whisper, eliminerà i file temporanei e chiuderà solo al termine della pulizia.
        """
        alert.addButton(withTitle: "Continua trascrizione")
        alert.addButton(withTitle: "Interrompi ed esci")

        guard alert.runModal() == .alertSecondButtonReturn else {
            return .terminateCancel
        }

        Task {
            await transcriptionModel.cancelAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
