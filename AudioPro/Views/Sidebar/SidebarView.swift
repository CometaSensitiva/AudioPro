import SwiftUI

struct SidebarView: View {
    @Binding var section: AppSection
    @ObservedObject var transcriptionModel: TranscriptionModel
    @EnvironmentObject private var appState: AudioAppState

    var body: some View {
        // Sidebar nativa (Liquid Glass di sistema), senza sfondo su misura.
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
        .navigationTitle("AudioPro")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        // La coda file vive ora nel contenuto principale: la sidebar accetta
        // comunque il drop esterno per aggiungere file rapidamente.
        .mediaDropDestination(isEnabled: appState.canModifyQueue) { files in
            appState.addFiles(files.map { AudioFile(url: $0.url, securityScopedURL: $0.securityScopedURL) })
        }
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
