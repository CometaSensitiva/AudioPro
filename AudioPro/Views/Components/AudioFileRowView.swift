import SwiftUI

/// Componente atomico per visualizzare una riga di file audio nella sidebar con look alla LandmarkSelectionListItem.
/// Completamente stateless - accetta solo parametri primitivi per massima riusabilità e preview istantanee.
struct AudioFileRowView: View {
    let fileName: String
    let subtitle: String?
    let isSelected: Bool
    
    private let cardRadius: CGFloat = LiquidGlassDesign.cornerRadius + 2
    
    init(fileName: String, subtitle: String? = nil, isSelected: Bool) {
        self.fileName = fileName
        self.subtitle = subtitle
        self.isSelected = isSelected
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.forward")
                .font(.body.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary.opacity(0.65))
                .imageScale(.medium)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            Color.clear
                .liquidGlassSurface(shape: .fixed(cardRadius))
                .overlay {
                    shape
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.05))
                }
                .overlay {
                    shape.stroke(
                        isSelected ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 1.2 : 1
                    )
                }
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

extension AudioFileRowView {
    /// Convenience init to costruire la riga direttamente da un AudioFile
    init(file: AudioFile, isSelected: Bool) {
        let ext = file.url.pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "mkv", "avi", "webm"].contains(ext)
        let badge = isVideo ? "🎬 " : ""
        let subtitle: String

        switch file.metadataState {
        case .loading:
            subtitle = badge + "Analisi file..."
        case .failed:
            subtitle = badge + "Metadata non disponibili"
        case .ready:
            let duration = file.duration != nil ? file.formattedDuration : nil
            let size = file.fileSize != nil ? file.formattedFileSize : nil
            subtitle = badge + [duration, size].compactMap { $0 }
                .joined(separator: " · ")
        }

        self.init(
            fileName: file.name,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            isSelected: isSelected
        )
    }
}

// MARK: - Previews

struct AudioFileRowView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AudioFileRowView(fileName: "demo_audio.m4a", subtitle: "1:24 · 2.1 MB", isSelected: false)
            AudioFileRowView(fileName: "demo_audio.m4a", subtitle: "1:24 · 2.1 MB", isSelected: true)
            AudioFileRowView(fileName: "very_long_filename_that_might_need_truncation.wav", subtitle: nil, isSelected: false)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
