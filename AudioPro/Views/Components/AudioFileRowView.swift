import SwiftUI

/// Componente atomico per visualizzare una riga di file audio nella sidebar con look alla LandmarkSelectionListItem.
/// Completamente stateless - accetta solo parametri primitivi per massima riusabilità e preview istantanee.
struct AudioFileRowView: View {
    let fileName: String
    let subtitle: String?
    let mediaSymbolName: String?
    let isSelected: Bool

    init(
        fileName: String,
        subtitle: String? = nil,
        mediaSymbolName: String? = nil,
        isSelected: Bool
    ) {
        self.fileName = fileName
        self.subtitle = subtitle
        self.mediaSymbolName = mediaSymbolName
        self.isSelected = isSelected
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Tile icona in stile lista Musica/Finder: quadratino arrotondato
            // che si accende in accento quando la riga è selezionata.
            Image(systemName: mediaSymbolName ?? "waveform")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Selezione pulita e nativa: solo evidenziazione accentata,
            // niente cartoncino/bordo/ombra.
            RoundedRectangle(cornerRadius: LiquidGlassDesign.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

extension AudioFileRowView {
    /// Convenience init to costruire la riga direttamente da un AudioFile
    init(file: AudioFile, isSelected: Bool) {
        let subtitle: String

        switch file.metadataState {
        case .loading:
            subtitle = "Analisi del file…"
        case .failed:
            subtitle = "Metadati non disponibili"
        case .ready:
            let duration = file.duration != nil ? file.formattedDuration : nil
            let size = file.fileSize != nil ? file.formattedFileSize : nil
            subtitle = [duration, size].compactMap { $0 }
                .joined(separator: " · ")
        }

        self.init(
            fileName: file.name,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            mediaSymbolName: file.isVideo ? "video.fill" : "waveform",
            isSelected: isSelected
        )
    }
}

// MARK: - Previews

struct AudioFileRowView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AudioFileRowView(fileName: "demo_audio.m4a", subtitle: "1:24 · 2.1 MB", mediaSymbolName: "waveform", isSelected: false)
            AudioFileRowView(fileName: "demo_video.mp4", subtitle: "24:54 · 314,6 MB", mediaSymbolName: "video.fill", isSelected: true)
            AudioFileRowView(fileName: "very_long_filename_that_might_need_truncation.wav", subtitle: nil, isSelected: false)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
