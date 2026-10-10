import AppKit
import Foundation

@MainActor
protocol TranscriptionDestinationSelecting: AnyObject {
    func selectDestination(
        suggestedBaseName: String,
        initialDirectoryURL: URL?,
        outputSelection: TranscriptionOutputSelection
    ) async -> TranscriptionDestination?

    func cancelActivePanel()
}

@MainActor
final class TranscriptionDestinationPicker: TranscriptionDestinationSelecting {
    private struct PanelSelection {
        let directoryURL: URL
        let baseName: String
    }

    private enum ConflictChoice {
        case replace
        case rename
        case cancel
    }

    private var activePanel: NSOpenPanel?

    func selectDestination(
        suggestedBaseName: String,
        initialDirectoryURL: URL?,
        outputSelection: TranscriptionOutputSelection
    ) async -> TranscriptionDestination? {
        var baseName = Self.sanitizedBaseName(suggestedBaseName) ?? "Trascrizione"
        var directoryURL = initialDirectoryURL

        while Task.isCancelled == false {
            guard let selection = await presentPanel(
                baseName: baseName,
                initialDirectoryURL: directoryURL,
                outputSelection: outputSelection
            ) else {
                return nil
            }

            guard let sanitizedName = Self.sanitizedBaseName(selection.baseName) else {
                presentInvalidNameAlert()
                baseName = selection.baseName
                directoryURL = selection.directoryURL
                continue
            }
            baseName = sanitizedName
            directoryURL = selection.directoryURL

            let destination = TranscriptionDestination(
                directoryURL: selection.directoryURL,
                baseName: sanitizedName,
                outputSelection: outputSelection,
                overwriteExisting: false,
                securityScopedURL: selection.directoryURL
            )

            let hasSecurityScope = selection.directoryURL.startAccessingSecurityScopedResource()
            let classifiedURLs = destination.selectedURLs.map { url in
                (
                    url,
                    TranscriptionOutputPathClassifier.kind(at: url)
                )
            }
            if hasSecurityScope {
                selection.directoryURL.stopAccessingSecurityScopedResource()
            }

            let unsupportedURLs = classifiedURLs.compactMap { url, kind in
                kind == .unsupported ? url : nil
            }
            if unsupportedURLs.isEmpty == false {
                switch presentUnsupportedConflictAlert(existingURLs: unsupportedURLs) {
                case .rename:
                    continue
                case .cancel:
                    return nil
                case .replace:
                    assertionFailure("Unsupported output paths cannot be replaced.")
                    return nil
                }
            }

            let existingURLs = classifiedURLs.compactMap { url, kind in
                kind == .regularFile ? url : nil
            }

            guard existingURLs.isEmpty == false else {
                return destination
            }

            switch presentConflictAlert(existingURLs: existingURLs) {
            case .replace:
                return TranscriptionDestination(
                    directoryURL: destination.directoryURL,
                    baseName: destination.baseName,
                    outputSelection: destination.outputSelection,
                    overwriteExisting: true,
                    securityScopedURL: destination.securityScopedURL
                )
            case .rename:
                continue
            case .cancel:
                return nil
            }
        }

        return nil
    }

    func cancelActivePanel() {
        activePanel?.cancel(nil)
        activePanel = nil
    }

    private func presentPanel(
        baseName: String,
        initialDirectoryURL: URL?,
        outputSelection: TranscriptionOutputSelection
    ) async -> PanelSelection? {
        cancelActivePanel()

        let panel = Self.makePanel(
            baseName: baseName,
            initialDirectoryURL: initialDirectoryURL,
            outputSelection: outputSelection
        )
        activePanel = panel

        return await withCheckedContinuation { continuation in
            panel.begin { [weak self, weak panel] response in
                let selection: PanelSelection?
                if response == .OK,
                   let panel,
                   let directoryURL = panel.url,
                   let baseName = Self.baseName(in: panel) {
                    selection = PanelSelection(
                        directoryURL: directoryURL,
                        baseName: baseName
                    )
                } else {
                    selection = nil
                }

                if let self, let panel, self.activePanel === panel {
                    self.activePanel = nil
                }
                continuation.resume(returning: selection)
            }
        }
    }

    static func makePanel(
        baseName: String,
        initialDirectoryURL: URL?,
        outputSelection: TranscriptionOutputSelection
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.identifier = NSUserInterfaceItemIdentifier("AudioPro.TranscriptionDestination")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = initialDirectoryURL
        panel.message = """
        Scegli il nome e la cartella. AudioPro richiede l’accesso per creare i file della trascrizione.
        \(outputSelection.creationDescription)
        """
        panel.prompt = "Consenti e avvia"
        panel.accessoryView = TranscriptionNameAccessoryView(baseName: baseName)
        panel.isAccessoryViewDisclosed = true
        return panel
    }

    static func baseName(in panel: NSOpenPanel) -> String? {
        (panel.accessoryView as? TranscriptionNameAccessoryView)?.baseName
    }

    private func presentInvalidNameAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Nome non valido"
        alert.informativeText = "Inserisci un nome che non sia composto soltanto da punti."
        alert.addButton(withTitle: "Cambia nome")
        alert.runModal()
    }

    private func presentUnsupportedConflictAlert(existingURLs: [URL]) -> ConflictChoice {
        let names = existingURLs.map(\.lastPathComponent).joined(separator: ", ")
        let replacementReference = existingURLs.count == 1 ? "questo elemento" : "questi elementi"
        let conflictDescription = existingURLs.count == 1
            ? "Esiste già un elemento che non è un file regolare: \(names)."
            : "Esistono già elementi che non sono file regolari: \(names)."
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Destinazione non sostituibile"
        alert.informativeText = """
        \(conflictDescription) Per proteggere i dati, AudioPro non può sostituire \(replacementReference).
        """
        alert.addButton(withTitle: "Cambia nome")
        alert.addButton(withTitle: "Annulla")

        return alert.runModal() == .alertFirstButtonReturn ? .rename : .cancel
    }

    private func presentConflictAlert(existingURLs: [URL]) -> ConflictChoice {
        let names = existingURLs.map(\.lastPathComponent).joined(separator: ", ")
        let preservationDescription = existingURLs.count == 1
            ? "Il file attuale resterà invariato finché la nuova trascrizione non sarà completata."
            : "I file attuali resteranno invariati finché la nuova trascrizione non sarà completata."
        let conflictDescription = existingURLs.count == 1
            ? "Esiste già il file \(names)."
            : "Esistono già questi file: \(names)."
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = existingURLs.count == 1 ? "File già esistente" : "File già esistenti"
        alert.informativeText = """
        \(conflictDescription) \(preservationDescription)
        """
        alert.addButton(withTitle: existingURLs.count > 1 ? "Sostituisci i file" : "Sostituisci")
        alert.addButton(withTitle: "Cambia nome")
        alert.addButton(withTitle: "Annulla")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .rename
        default:
            return .cancel
        }
    }

    nonisolated static func sanitizedBaseName(_ rawName: String) -> String? {
        var value = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [".srt", ".txt"] where value.lowercased().hasSuffix(suffix) {
            value.removeLast(suffix.count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        value = value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        while value.last == "." || value.last?.isWhitespace == true {
            value.removeLast()
        }

        guard value.isEmpty == false,
              value.contains(where: { $0 != "." && $0.isWhitespace == false }) else {
            return nil
        }
        return value
    }
}

@MainActor
private final class TranscriptionNameAccessoryView: NSView {
    private let nameField: NSTextField

    var baseName: String {
        nameField.stringValue
    }

    init(baseName: String) {
        nameField = NSTextField(string: baseName)
        super.init(frame: .zero)

        let label = NSTextField(labelWithString: "Nome:")
        label.setContentHuggingPriority(.required, for: .horizontal)

        nameField.placeholderString = "Nome della trascrizione"
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [label, nameField])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
