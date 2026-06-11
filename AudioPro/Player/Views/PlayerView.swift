import AVKit
import SwiftUI

struct PlayerView: View {
    @ObservedObject private var model: PlayerModel
    // Osservato direttamente: le @Published del controller (currentTime,
    // isPlaying...) invalidano la view senza passare dal modello.
    @ObservedObject private var playerController: PlayerController
    @State private var isScrubbing = false
    @State private var scrubValue: TimeInterval = 0
    @Namespace private var glassNamespace

    init(model: PlayerModel) {
        self._model = ObservedObject(wrappedValue: model)
        self._playerController = ObservedObject(wrappedValue: model.playerController)
    }

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) { playerBar }
            .toolbar { toolbarContent }
            .navigationSubtitle(playerController.mediaName ?? "Nessun media")
            .frame(minWidth: 460, minHeight: 540)
            .background {
                // Il glass ha bisogno di un fondo colorato dietro di sé;
                // la waveform si muove solo durante la riproduzione.
                ZStack {
                    AmbientBackdrop()
                    ReactiveWaveform(isActive: playerController.isPlaying, intensity: 0.7)
                }
                .ignoresSafeArea()
            }
            .focusedSceneValue(\.playerActions, currentActions)
            .onReceive(playerController.$currentTime) { time in
                model.updateActiveCue(at: time)
            }
    }

    private var content: some View {
        VStack(spacing: LiquidGlassDesign.spacing) {
            if playerController.hasVideo {
                VideoPlayer(player: playerController.player)
                    .aspectRatio(playerController.videoAspectRatio ?? 16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 480)
                    .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(LiquidGlassDesign.mediaCornerRadius))))
                    // "Theatre mode": ombra ambientale larga + ombra di
                    // contatto stretta, per staccare il video dallo sfondo.
                    .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 14)
                    .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                    .padding(.bottom, LiquidGlassDesign.spacing)
            }

            statusArea

            if model.cues.isEmpty {
                emptyTranscript
            } else {
                TranscriptListView(
                    cues: model.cues,
                    activeCueID: model.activeCueID,
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
                model.chooseMedia()
            } label: {
                Label("Apri media", systemImage: "play.rectangle")
            }
            .labelStyle(.iconOnly)
            .help("Apri un file audio o video (⌘O)")

            Button {
                model.chooseSRT()
            } label: {
                Label("Apri SRT", systemImage: "captions.bubble")
            }
            .labelStyle(.iconOnly)
            .help("Apri una trascrizione SRT (⇧⌘O)")

            Button(role: .destructive) {
                model.clearAll()
            } label: {
                Label("Svuota", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help("Svuota media e trascrizione")
            .disabled(model.isEmpty)
        }
    }

    /// Unico elemento glass della sezione: senza media è una capsula di invito,
    /// con media diventa la barra di trasporto (morphing via glassEffectID).
    private var playerBar: some View {
        GlassEffectContainer(spacing: 16) {
            if playerController.hasMedia {
                transportControls
                    .padding(.horizontal, LiquidGlassDesign.padding)
                    .padding(.vertical, 10)
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: LiquidGlassDesign.controlCornerRadius, style: .continuous)
                    )
                    .glassEffectID("playerBar", in: glassNamespace)
            } else {
                Button {
                    model.chooseMedia()
                } label: {
                    Label("Apri media", systemImage: "play.rectangle")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("playerBar", in: glassNamespace)
                .help("Apri un file audio o video (⌘O)")
            }
        }
        .padding(.horizontal, LiquidGlassDesign.padding)
        .padding(.bottom, LiquidGlassDesign.spacing)
        .animation(.smooth(duration: 0.35), value: playerController.hasMedia)
    }

    private var transportControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: LiquidGlassDesign.spacing) {
                Button {
                    playerController.togglePlayback()
                } label: {
                    Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                // Equivalente a livello finestra: vince sul first responder
                // (la List in sidebar consuma Spazio prima dei menu).
                .keyboardShortcut(.space, modifiers: [])
                .help(playerController.isPlaying ? "Pausa (Spazio)" : "Riproduci (Spazio)")
                .accessibilityLabel(playerController.isPlaying ? "Pausa" : "Riproduci")

                Text(displayTime.playerDisplayString)
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
                .disabled(playerController.duration <= 0)
                .accessibilityLabel("Posizione di riproduzione")
                .accessibilityValue("\(displayTime.playerDisplayString) di \(playerController.duration.playerDisplayString)")

                Text(playerController.duration.playerDisplayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack {
                Text(playerController.mediaName ?? "Nessun media selezionato")
                Spacer()
                Text(model.srtFileName.map { "\($0) · \(model.cues.count) segmenti" } ?? "Nessun SRT selezionato")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        if let message = playerController.errorMessage
            ?? model.srtErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.cues.isEmpty && !playerController.hasMedia {
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
    }

    private var displayTime: TimeInterval {
        isScrubbing ? scrubValue : playerController.currentTime
    }

    // Ricreata a ogni body (4×/s in riproduzione, currentTime è @Published su
    // un ObservableObject: l'invalidazione è a livello di oggetto). Isolare la
    // pubblicazione richiederebbe @Observable o uno split del controller —
    // rimandato, vedi decision log. Costo: alloc struct + rivalidazione menu.
    private var currentActions: PlayerActions {
        PlayerActions(
            isPlaying: playerController.isPlaying,
            hasMedia: playerController.hasMedia,
            togglePlayback: { playerController.togglePlayback() },
            seekBy: { playerController.seekBy($0) },
            openMedia: { model.chooseMedia() },
            openSRT: { model.chooseSRT() }
        )
    }
}
