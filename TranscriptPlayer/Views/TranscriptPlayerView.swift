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
        content
            .safeAreaInset(edge: .bottom, spacing: 0) { playerBar }
            .toolbar { toolbarContent }
            .navigationTitle("TranscriptPlayer")
            .navigationSubtitle(playerController.mediaName ?? "Nessun media")
            .frame(minWidth: 460, minHeight: 540)
            .background {
                // Le superfici glass sono Material: senza un fondo colorato rendono
                // grigio. Stesso backdrop del DetailView di AudioPro.
                WaveformBackdrop()
                    .ignoresSafeArea()
            }
            .focusedSceneValue(\.transcriptPlayerActions, currentActions)
            .onReceive(playerController.$currentTime) { time in
                updateActiveCue(at: time)
            }
    }

    private var content: some View {
        VStack(spacing: LiquidGlassDesign.spacing) {
            if playerController.hasVideo {
                VideoPlayer(player: playerController.player)
                    .frame(minHeight: 180, idealHeight: 220, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidGlassDesign.cornerRadius, style: .continuous))
            }

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
        .padding([.horizontal, .top], LiquidGlassDesign.padding)
        .padding(.bottom, LiquidGlassDesign.spacing)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                chooseMedia()
            } label: {
                Label("Apri media", systemImage: "play.rectangle")
            }
            .labelStyle(.iconOnly)
            .help("Apri un file audio o video (⌘O)")

            Button {
                chooseSRT()
            } label: {
                Label("Apri SRT", systemImage: "captions.bubble")
            }
            .labelStyle(.iconOnly)
            .help("Apri una trascrizione SRT (⇧⌘O)")
        }
    }

    private var playerBar: some View {
        LiquidGlassContainer {
            VStack(spacing: 8) {
                HStack(spacing: LiquidGlassDesign.spacing) {
                    Button {
                        playerController.togglePlayback()
                    } label: {
                        Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 18)
                    }
                    .liquidGlassButtonStyle(prominent: true)
                    .disabled(!playerController.hasMedia)
                    .help(playerController.isPlaying ? "Pausa (Spazio)" : "Riproduci (Spazio)")
                    .accessibilityLabel(playerController.isPlaying ? "Pausa" : "Riproduci")

                    Text(formatTime(displayTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Slider(
                        value: Binding(
                            get: { displayTime },
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
                    .accessibilityLabel("Posizione di riproduzione")
                    .accessibilityValue("\(formatTime(displayTime)) di \(formatTime(playerController.duration))")

                    Text(formatTime(playerController.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Text(playerController.mediaName ?? "Nessun media selezionato")
                    Spacer()
                    Text(srtFileName.map { "\($0) · \(cues.count) segmenti" } ?? "Nessun SRT selezionato")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, LiquidGlassDesign.padding)
            .padding(.vertical, 10)
            .liquidGlassControl(shape: .fixed(16))
        }
        .padding(.horizontal, LiquidGlassDesign.padding)
        .padding(.bottom, LiquidGlassDesign.spacing)
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
            Text("Apri un file .srt dalla toolbar o dal menu File per visualizzare i segmenti.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassSurface()
    }

    private var displayTime: TimeInterval {
        isScrubbing ? scrubValue : playerController.currentTime
    }

    private var currentActions: TranscriptPlayerActions {
        TranscriptPlayerActions(
            isPlaying: playerController.isPlaying,
            hasMedia: playerController.hasMedia,
            togglePlayback: { playerController.togglePlayback() },
            seekBy: { playerController.seekBy($0) },
            openMedia: { chooseMedia() },
            openSRT: { chooseSRT() }
        )
    }

    private func chooseMedia() {
        Task {
            guard let url = await fileSelectionService.selectMedia() else { return }
            playerController.loadMedia(from: url)
        }
    }

    private func chooseSRT() {
        Task {
            guard let url = await fileSelectionService.selectSRT() else { return }
            handleSRTImport(url)
        }
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
