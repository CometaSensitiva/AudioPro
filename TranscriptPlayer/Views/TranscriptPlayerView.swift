import AVKit
import SwiftUI

struct TranscriptPlayerView: View {
    @StateObject private var playerController = PlayerController()
    @StateObject private var fileSelectionService = FileSelectionService()
    @State private var cues: [SubtitleCue] = []
    @State private var transcriptRevision = UUID()
    @State private var activeCueID: SubtitleCue.ID?
    @State private var srtFileName: String?
    @State private var srtErrorMessage: String?
    @State private var isScrubbing = false
    @State private var scrubValue: TimeInterval = 0

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
                    transcriptRevision: transcriptRevision,
                    cues: cues,
                    activeCueID: activeCueID,
                    canSeek: playerController.hasMedia
                ) { cue in
                    playerController.seek(to: cue.start)
                    playerController.play()
                }
                .equatable()
            }
        }
        .padding(18)
        .frame(minWidth: 460, minHeight: 540)
        .background {
            // Le superfici glass sono Material: senza un fondo colorato rendono
            // grigio. Stesso backdrop del DetailView di AudioPro.
            WaveformBackdrop()
                .ignoresSafeArea()
        }
        .onReceive(playerController.$currentTime) { time in
            updateActiveCue(at: time)
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
                Task {
                    guard let url = await fileSelectionService.selectMedia() else { return }
                    playerController.loadMedia(from: url)
                }
            } label: {
                Label("Scegli media", systemImage: "play.rectangle")
            }
            .buttonStyle(.liquidGlass)

            Button {
                Task {
                    guard let url = await fileSelectionService.selectSRT() else { return }
                    handleSRTImport(url)
                }
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

    private func handleSRTImport(_ url: URL) {
        do {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let parsedCues = try SRTParser.load(from: url)
            cues = parsedCues
            transcriptRevision = UUID()
            srtFileName = url.lastPathComponent
            srtErrorMessage = parsedCues.isEmpty
                ? "Il file SRT non contiene segmenti validi."
                : nil
            updateActiveCue(at: playerController.currentTime)
        } catch {
            cues = []
            transcriptRevision = UUID()
            activeCueID = nil
            srtFileName = nil
            srtErrorMessage = "Impossibile leggere il file SRT: \(error.localizedDescription)"
        }
    }

    private func updateActiveCue(at time: TimeInterval) {
        let nextCueID = SubtitleCueLookup.activeCueID(in: cues, at: time)
        guard nextCueID != activeCueID else { return }
        activeCueID = nextCueID
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
