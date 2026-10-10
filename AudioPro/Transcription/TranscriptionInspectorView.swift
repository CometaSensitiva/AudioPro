import SwiftUI

/// Inspector dei setting tecnici della trascrizione, speculare a
/// CompressionInspectorView dell'Esportazione: formato output e gestione del
/// modello vivono qui, così la schermata principale resta pulita e uniforme.
struct TranscriptionInspectorView: View {
    @ObservedObject var model: TranscriptionModel

    var body: some View {
        Form {
            Section {
                Picker("Formato", selection: $model.outputSelection) {
                    ForEach(TranscriptionOutputSelection.allCases) { selection in
                        Text(selection.displayName).tag(selection)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.canConfigureOutput == false)
            } header: {
                Text("Formato di output")
            } footer: {
                Text("SRT per sottotitoli sincronizzati, TXT per il testo semplice. La trascrizione avviene sul Mac, in italiano.")
            }

            Section("Modello") {
                modelDownloadArea
            }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var modelDownloadArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isModelAvailable {
                // Stessa forma delle altre righe dell'inspector: etichetta a
                // sinistra, valore a destra; il colore resta solo sull'icona.
                LabeledContent("Whisper Large v3") {
                    Label("Pronto", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.multicolor)
                }
            } else {
                switch model.modelDownloadState {
                case .idle, .completed:
                    Label(model.modelStatusMessage, systemImage: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Scaricalo una sola volta per abilitare la trascrizione locale.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        model.startModelDownload()
                    } label: {
                        Label("Scarica il modello", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.canDownloadModel == false)
                case .downloading(let progress):
                    JobProgressLine(
                        title: "Download del modello in corso",
                        progress: progress,
                        systemImage: "arrow.down.circle",
                        message: "AudioPro salverà il modello nella cartella Application Support."
                    )

                    Button("Interrompi", role: .destructive) {
                        model.cancelModelDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                case .cancelling:
                    JobProgressLine(
                        title: "Interruzione del download",
                        progress: nil,
                        systemImage: "xmark.circle",
                        message: "AudioPro attende la chiusura sicura del download."
                    )
                case .failed(let message):
                    FeatureNotice(
                        systemImage: "exclamationmark.triangle.fill",
                        title: "Download del modello non riuscito",
                        message: message,
                        tint: LiquidGlassStatusColor.failure
                    )

                    Button {
                        model.startModelDownload()
                    } label: {
                        Label("Riprova il download", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.canDownloadModel == false)
                }
            }
        }
    }
}

struct TranscriptionInspectorView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        TranscriptionInspectorView(model: TranscriptionModel())
    }
}
