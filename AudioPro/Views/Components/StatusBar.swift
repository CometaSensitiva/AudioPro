import SwiftUI

struct StatusBar: View {
    let state: ProcessingState
    var onCancel: () -> Void
    var onTranscribeOutput: (() -> Void)? = nil
    var onShowResult: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    
    var body: some View {
        switch state {
        case .idle:
            // Mai visibile: il call site mostra la barra solo fuori da idle.
            EmptyView()
        case .running(let progress):
            ResponsiveActionRow {
                JobProgressLine(
                    title: "Esportazione in corso",
                    progress: progress,
                    systemImage: "square.and.arrow.up",
                    message: "Puoi cambiare sezione: il lavoro continuerà in secondo piano."
                )
            } actions: {
                Button("Interrompi", role: .destructive, action: onCancel)
                    .buttonStyle(.bordered)
            }
        case .completed:
            ResponsiveActionRow {
                Label("Esportazione completata", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(LiquidGlassStatusColor.success)
            } actions: {
                HStack(spacing: 8) {
                    if let onShowResult {
                        Button("Mostra nel Finder", action: onShowResult)
                            .buttonStyle(.bordered)
                    }

                    if let onTranscribeOutput {
                        Button("Trascrivi il risultato", action: onTranscribeOutput)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        case .failed(let message):
            ResponsiveActionRow {
                FeatureNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Esportazione non riuscita",
                    message: message,
                    tint: LiquidGlassStatusColor.failure,
                    isSingleLine: true
                )
            } actions: {
                if let onRetry {
                    Button("Riprova…", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

extension ProcessingState {
    var isBusy: Bool {
        if case .running = self { return true }
        return false
    }
}

struct StatusBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            StatusBar(state: .running(progress: 0.42), onCancel: {})
            StatusBar(
                state: .completed,
                onCancel: {},
                onTranscribeOutput: {},
                onShowResult: {}
            )
            StatusBar(state: .failed(message: "Il file non può essere scritto."), onCancel: {}, onRetry: {})
        }
        .padding()
    }
}
