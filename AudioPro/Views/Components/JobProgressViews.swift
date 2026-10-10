import SwiftUI

struct JobProgressBadge: View {
    let progress: Double?
    var tint: Color = .accentColor

    var body: some View {
        Group {
            if let progress {
                ProgressView(value: clamped(progress))
                    .progressViewStyle(.circular)
            } else {
                ProgressView()
            }
        }
        .controlSize(.small)
        .tint(tint)
        .frame(width: 18, height: 18)
    }
}

struct JobProgressLine: View {
    let title: String
    let progress: Double?
    let systemImage: String
    var message: String?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                Spacer()

                if let progress {
                    Text(percentLabel(for: progress))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let progress {
                ProgressView(value: clamped(progress))
                    .progressViewStyle(.linear)
                    .tint(tint)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
            }

            if let message {
                // Una riga sola: un testo che va a capo in base alla larghezza
                // rende l'altezza minima dipendente dalla larghezza. Nella barra
                // inferiore (safeAreaInset) questo cambiava di continuo la
                // dimensione minima della colonna dello split view e AppKit
                // chiudeva l'app ("Update Constraints in Window" in loop).
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func clamped(_ progress: Double) -> Double {
    min(max(progress, 0), 1)
}

private func percentLabel(for progress: Double) -> String {
    "\(Int(clamped(progress) * 100))%"
}
