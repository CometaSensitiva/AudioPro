import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptPlayerView: View {
    @StateObject private var playerController = PlayerController()
    @State private var cues: [SubtitleCue] = []
    @State private var srtFileName: String?
    @State private var srtErrorMessage: String?
    @State private var mediaImportErrorMessage: String?
    @State private var isMediaImporterPresented = false
    @State private var isSRTImporterPresented = false
    @State private var isScrubbing = false
    @State private var scrubValue: TimeInterval = 0

    private var activeCueID: SubtitleCue.ID? {
        cues.first {
            playerController.currentTime >= $0.start
                && playerController.currentTime <= $0.end
        }?.id
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            importControls

            if playerController.hasVideo {
                VideoPlayer(player: playerController.player)
                    .frame(minHeight: 180, idealHeight: 220, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            playbackControls
            statusArea

            if cues.isEmpty {
                emptyTranscript
            } else {
                TranscriptListView(
                    cues: cues,
                    activeCueID: activeCueID,
                    canSeek: playerController.hasMedia
                ) { cue in
                    playerController.seek(to: cue.start)
                    playerController.play()
                }
            }
        }
        .padding(18)
        .frame(minWidth: 460, minHeight: 540)
        .background {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isMediaImporterPresented,
            allowedContentTypes: [.audiovisualContent],
            allowsMultipleSelection: false
        ) { result in
            handleMediaImport(result)
        }
        .fileImporter(
            isPresented: $isSRTImporterPresented,
            allowedContentTypes: srtContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleSRTImport(result)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TranscriptPlayer")
                .font(.title2.bold())
            Text("Riproduci audio o video seguendo una trascrizione SRT sincronizzata.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importControls: some View {
        HStack(spacing: 10) {
            Button {
                isMediaImporterPresented = true
            } label: {
                Label("Scegli media", systemImage: "play.rectangle")
            }
            .buttonStyle(.liquidGlass)

            Button {
                isSRTImporterPresented = true
            } label: {
                Label("Scegli SRT", systemImage: "captions.bubble")
            }
            .buttonStyle(.liquidGlass)

            Spacer()

            Text("\(cues.count) segmenti")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    playerController.togglePlayback()
                } label: {
                    Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.liquidGlassProminent)
                .disabled(!playerController.hasMedia)

                Slider(
                    value: Binding(
                        get: {
                            isScrubbing ? scrubValue : playerController.currentTime
                        },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(playerController.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            scrubValue = playerController.currentTime
                            isScrubbing = true
                        } else {
                            isScrubbing = false
                            playerController.seek(to: scrubValue)
                        }
                    }
                )
                .disabled(!playerController.hasMedia || playerController.duration <= 0)

                Text(
                    "\(formatTime(isScrubbing ? scrubValue : playerController.currentTime))"
                        + " / \(formatTime(playerController.duration))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 92, alignment: .trailing)
            }

            HStack {
                Text(playerController.mediaName ?? "Nessun media selezionato")
                Spacer()
                Text(srtFileName ?? "Nessun SRT selezionato")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(12)
        .liquidGlassSurface()
    }

    @ViewBuilder
    private var statusArea: some View {
        if let message = playerController.errorMessage
            ?? mediaImportErrorMessage
            ?? srtErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !cues.isEmpty && !playerController.hasMedia {
            Text("La trascrizione è pronta. Seleziona un media per abilitare il salto tra i segmenti.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyTranscript: some View {
        ContentUnavailableView {
            Label("Nessuna trascrizione", systemImage: "captions.bubble")
        } description: {
            Text("Seleziona manualmente un file .srt per visualizzare i segmenti.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassSurface()
    }

    private var srtContentTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let srtType = UTType(filenameExtension: "srt"), srtType != .plainText {
            types.insert(srtType, at: 0)
        }
        return types
    }

    private func handleMediaImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            mediaImportErrorMessage = nil
            playerController.loadMedia(from: url)
        } catch {
            mediaImportErrorMessage = "Impossibile selezionare il media: \(error.localizedDescription)"
        }
    }

    private func handleSRTImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
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
        } catch {
            cues = []
            srtFileName = nil
            srtErrorMessage = "Impossibile leggere il file SRT: \(error.localizedDescription)"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainingSeconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
