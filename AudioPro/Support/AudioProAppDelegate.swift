import AppKit

@MainActor
final class AudioProAppDelegate: NSObject, NSApplicationDelegate {
    weak var session: AppSession?
    private var isTerminationPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminationPending {
            return .terminateLater
        }

        guard let session, session.hasActiveWork else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Operazioni ancora in corso"
        alert.informativeText = """
        AudioPro sta completando \(session.activeWorkDescription). Se esci ora, AudioPro interromperà le operazioni, rimuoverà i file temporanei e si chiuderà al termine della pulizia.
        """
        alert.addButton(withTitle: "Continua le operazioni")
        alert.addButton(withTitle: "Interrompi ed esci")

        guard alert.runModal() == .alertSecondButtonReturn else {
            return .terminateCancel
        }

        isTerminationPending = true
        Task { [weak self] in
            await session.cancelAllAndWait()
            self?.isTerminationPending = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
