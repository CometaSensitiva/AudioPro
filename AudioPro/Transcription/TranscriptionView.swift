import SwiftUI

struct TranscriptionView: View {
    @ObservedObject var model: TranscriptionModel
    let onOpenInPlayback: (TranscriptionResult) -> Void

    var body: some View {
        ZStack {
            ZStack {
                AmbientBackdrop()
                ReactiveWaveform(isActive: model.state.activatesWaveform)
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: LiquidGlassDesign.spacing) {
                    introduction
                    outputCard
                    sourceCard
                    stateCard
                }
                .frame(maxWidth: 720)
                .padding(LiquidGlassDesign.padding)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
        .navigationTitle("")
        .navigationSubtitle(model.selectedMediaName ?? "Nessun audio selezionato")
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.chooseMedia()
                } label: {
                    Label("Scegli audio", systemImage: "waveform")
                }
                .labelStyle(.iconOnly)
                .help("Scegli un file audio o video")
                .disabled(model.state.isBusy)

                Button(role: .destructive) {
                    model.clearSelection()
                } label: {
                    Label("Svuota", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Rimuovi il file selezionato")
                .disabled(model.selectedMediaURL == nil || model.state.isBusy)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trascrizione locale")
                .font(.largeTitle.bold())
            Text("Crea sottotitoli sincronizzati e/o una copia di testo usando Whisper sul Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Output trascrizione")
                .font(.title3.weight(.semibold))

            HStack(alignment: .top, spacing: 28) {
                SummaryMetric(label: "Elaborazione", value: "Sul Mac", icon: "desktopcomputer")
                SummaryMetric(label: "Lingua", value: "Italiano", icon: "character.book.closed")

                VStack(alignment: .leading, spacing: 6) {
                    Label("Formato", systemImage: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Formato", selection: $model.outputSelection) {
                        ForEach(TranscriptionOutputSelection.allCases) { selection in
                            Text(selection.displayName).tag(selection)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(model.canConfigureOutput == false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            LabeledContent("Modello") {
                Label(
                    model.modelStatusMessage,
                    systemImage: model.isModelAvailable
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(model.isModelAvailable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }

            if model.isModelAvailable == false {
                Text("La trascrizione sarà disponibile dopo aver incluso il modello e ricompilato AudioPro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(.regularMaterial, in: cardShape)
    }

    @ViewBuilder
    private var sourceCard: some View {
        if let mediaURL = model.selectedMediaURL {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("File da trascrivere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(mediaURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(mediaURL.deletingLastPathComponent().path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding()
            .background(.regularMaterial, in: cardShape)
        } else {
            ContentUnavailableView {
                Label("Nessun audio selezionato", systemImage: "waveform.slash")
            } description: {
                Text("Scegli una registrazione oppure usa “Trascrivi output” dopo un’esportazione.")
            } actions: {
                Button("Scegli audio") {
                    model.chooseMedia()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(.regularMaterial, in: cardShape)
        }
    }

    @ViewBuilder
    private var stateCard: some View {
        switch model.state {
        case .idle, .selectingDestination:
            EmptyView()
        case .loadingModel:
            progressCard {
                ProgressView()
                    .controlSize(.small)
                Text("Caricamento del modello Whisper locale…")
            }
        case .transcribing(let progress):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Trascrizione in corso", systemImage: "waveform.and.mic")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.headline.monospacedDigit())
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("Puoi cambiare sezione: il lavoro continuerà in background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: cardShape)
        case .cancelling:
            progressCard {
                ProgressView()
                    .controlSize(.small)
                Text("Interruzione sicura e pulizia dei file temporanei…")
            }
        case .completed(let result):
            VStack(alignment: .leading, spacing: 8) {
                Label("Trascrizione completata", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                ForEach(result.generatedURLs, id: \.self) { url in
                    Text(url.lastPathComponent)
                }
                Text(completionSummary(for: result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: cardShape)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.regularMaterial, in: cardShape)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if model.selectedMediaURL != nil || model.state.isBusy {
            HStack(spacing: 12) {
                switch model.state {
                case .selectingDestination:
                    ProgressView()
                        .controlSize(.small)
                    Text("Concedi l'accesso alla cartella nel pannello macOS")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Interrompi", role: .destructive) {
                        model.cancel()
                    }
                case .loadingModel, .transcribing:
                    if let progress = model.state.progressValue {
                        ProgressView(value: progress)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(model.state.statusMessage ?? "Trascrizione in corso")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Interrompi", role: .destructive) {
                        model.cancel()
                    }
                case .cancelling:
                    ProgressView()
                        .controlSize(.small)
                    Text("Attendi la pulizia…")
                        .foregroundStyle(.secondary)
                    Spacer()
                case .completed(let result):
                    Button("Mostra nel Finder") {
                        model.showResultInFinder()
                    }
                    Spacer()
                    if result.canOpenInPlayback {
                        Button("Apri in Riproduzione") {
                            onOpenInPlayback(result)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                case .idle, .failed:
                    Text("macOS chiederà nome e accesso alla cartella prima di iniziare.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Scegli nome e cartella") {
                        model.startTranscription()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.canStart == false)
                }
            }
            .padding(.horizontal, LiquidGlassDesign.padding)
            .padding(.vertical, 12)
            .glassEffect(
                .regular.interactive(),
                in: .rect(cornerRadius: LiquidGlassDesign.controlCornerRadius, style: .continuous)
            )
            .padding(.horizontal, LiquidGlassDesign.padding)
            .padding(.bottom, LiquidGlassDesign.spacing)
        }
    }

    private func progressCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: cardShape)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiquidGlassDesign.cornerRadius, style: .continuous)
    }

    private func completionSummary(for result: TranscriptionResult) -> String {
        if result.canOpenInPlayback {
            return "\(result.cues.count) segmenti pronti per la riproduzione sincronizzata."
        }
        return "\(result.cues.count) segmenti salvati come testo semplice."
    }
}
