import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Binding var section: AppSection
    @ObservedObject var transcriptionModel: TranscriptionModel
    @EnvironmentObject private var appState: AudioAppState

    private let dropTypes: [UTType] = [.audio, .movie, .fileURL]

    private struct AccessibleFile: Sendable {
        let url: URL
        let securityScopedURL: URL?
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(style: .sidebar)
                .ignoresSafeArea(.container, edges: [.top, .leading, .bottom])

            List(selection: $section) {
                Section("Strumenti") {
                    ForEach(AppSection.allCases) { item in
                        HStack {
                            Label(item.name, systemImage: item.symbolName)
                            Spacer()
                            if item == .merger, appState.processingState.isBusy {
                                exportIndicator
                            } else if item == .transcription,
                                      transcriptionModel.state.isBusy || transcriptionModel.modelDownloadState.isBusy {
                                transcriptionIndicator
                            }
                        }
                        .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("AudioPro")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        // La coda file vive ora nel contenuto principale: la sidebar accetta
        // comunque il drop esterno per aggiungere file rapidamente.
        .onDrop(of: dropTypes, isTargeted: nil, perform: handleExternalDrop(providers:))
    }

    @ViewBuilder
    private var exportIndicator: some View {
        if case .running(let progress) = appState.processingState {
            JobProgressBadge(progress: progress)
                .help("Esportazione \(Int(progress * 100))%")
                .accessibilityLabel("Avanzamento esportazione")
                .accessibilityValue(percentAccessibilityValue(progress))
        }
    }

    @ViewBuilder
    private var transcriptionIndicator: some View {
        if transcriptionModel.modelDownloadState.isBusy {
            JobProgressBadge(progress: transcriptionModel.modelDownloadState.progressValue)
                .help(transcriptionModel.modelDownloadState.statusMessage ?? "Download del modello in corso")
                .accessibilityLabel("Download del modello Whisper")
                .accessibilityValue(
                    transcriptionModel.modelDownloadState.statusMessage
                        ?? "Download del modello in corso"
                )
        } else if let progress = transcriptionModel.state.progressValue {
            JobProgressBadge(progress: progress)
                .help("Trascrizione \(Int(progress * 100))%")
                .accessibilityLabel("Avanzamento trascrizione")
                .accessibilityValue(percentAccessibilityValue(progress))
        } else {
            JobProgressBadge(progress: nil)
                .help(transcriptionModel.state.statusMessage ?? "Trascrizione in corso")
                .accessibilityLabel("Stato trascrizione")
                .accessibilityValue(
                    transcriptionModel.state.statusMessage ?? "Trascrizione in corso"
                )
        }
    }

    private func percentAccessibilityValue(_ progress: Double) -> String {
        "\(Int(min(max(progress, 0), 1) * 100))%"
    }

    private func handleExternalDrop(providers: [NSItemProvider]) -> Bool {
        guard appState.canModifyQueue else { return false }
        let acceptedProviders = providers.filter { provider in
            dropTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
        guard acceptedProviders.isEmpty == false else { return false }

        Task {
            var accessibleFiles: [AccessibleFile] = []
            for provider in acceptedProviders {
                if let url = await loadFileURL(from: provider) {
                    let accessibleFile = await Task.detached(priority: .utility) {
                        Self.makeAccessibleFile(from: url)
                    }.value
                    if let accessibleFile {
                        accessibleFiles.append(accessibleFile)
                    }
                }
            }

            guard accessibleFiles.isEmpty == false else { return }
            await MainActor.run {
                let files = accessibleFiles.map {
                    AudioFile(url: $0.url, securityScopedURL: $0.securityScopedURL)
                }
                appState.addFiles(files)
            }
        }

        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        let preferredTypes = dropTypes.map(\.identifier)

        if let typeIdentifier = preferredTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
            if let url = await loadInPlaceURL(provider: provider, typeIdentifier: typeIdentifier) {
                return url
            }
        }

        if provider.canLoadObject(ofClass: URL.self) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
        }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data {
                    var isStale = false
                    if let url = try? URL(
                        resolvingBookmarkData: data,
                        options: [.withoutUI, .withoutMounting],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    ) {
                        continuation.resume(returning: url)
                    } else {
                        let url = URL(dataRepresentation: data, relativeTo: nil)
                        continuation.resume(returning: url)
                    }
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadInPlaceURL(provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private nonisolated static func makeAccessibleFile(from url: URL) -> AccessibleFile? {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()

        guard FileManager.default.fileExists(atPath: url.path), isSupportedMediaFile(url) else {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
            return nil
        }

        return AccessibleFile(
            url: url,
            securityScopedURL: hasSecurityScope ? url : nil
        )
    }

    private nonisolated static func isSupportedMediaFile(_ url: URL) -> Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey])
        if let type = resourceValues?.contentType {
            return type.conforms(to: .audio) || type.conforms(to: .movie)
        }

        if let fallbackType = UTType(filenameExtension: url.pathExtension) {
            return fallbackType.conforms(to: .audio) || fallbackType.conforms(to: .movie)
        }

        return false
    }
}

// MARK: - Previews

struct SidebarView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        SidebarView(
            section: .constant(.merger),
            transcriptionModel: TranscriptionModel()
        )
        .environmentObject(PreviewSamples.appState())
    }
}
