import SwiftUI

/// Empty state condiviso dalle tre feature. Mantiene identici gerarchia,
/// spaziatura e posizione dell'azione primaria senza nascondere il pattern
/// nativo di macOS fornito da `ContentUnavailableView`.
struct FeatureEmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    let message: String
    let actions: Actions

    init(
        _ title: String,
        systemImage: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            actions
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Messaggio informativo condiviso per inspector e card di stato. Il colore
/// resta un rinforzo semantico: icona, titolo e testo rendono il significato
/// comprensibile anche senza colore.
struct FeatureNotice: View {
    let systemImage: String
    let title: String
    let message: String
    var tint: Color = .secondary
    /// Nelle barre inferiori il messaggio resta su una riga: l'altezza della
    /// safeAreaInset non deve dipendere dalla larghezza (vedi JobProgressLine).
    var isSingleLine = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if isSingleLine {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(message)
                } else {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Stati condivisi") {
    VStack(spacing: 24) {
        FeatureEmptyState(
            "Nessun file in coda",
            systemImage: "waveform",
            message: "Aggiungi un file audio o video per iniziare."
        ) {
            Button("Aggiungi file…") {}
        }

        FeatureNotice(
            systemImage: "info.circle",
            title: "Elaborazione sul Mac",
            message: "Il contenuto resta sul dispositivo."
        )
        .padding()
    }
    .frame(width: 520, height: 360)
}
