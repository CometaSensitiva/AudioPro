import SwiftUI

/// Colonne condivise delle tabelle file (Esportazione e Trascrizione):
/// stesse colonne, stesse larghezze, stesso stile in tutta l'app.
@MainActor
@TableColumnBuilder<AudioFile, Never>
func mediaFileColumns() -> some TableColumnContent<AudioFile, Never> {
    TableColumn("Nome") { file in
        ObservedFileCell(file: file) { file in
            // Icona in una colonna a larghezza fissa e stesso stile per audio
            // e video: i nomi restano allineati qualunque sia il tipo.
            HStack(spacing: 6) {
                Image(systemName: file.isVideo ? "video" : "waveform")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(file.name)
            .accessibilityLabel(file.name)
        }
    }
    .width(min: 180, ideal: 320)

    TableColumn("Modificato") { file in
        ObservedFileCell(file: file) { file in
            Text(file.formattedModifiedDate)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(file.formattedModifiedDate)
        }
    }
    .width(min: 130, ideal: 170)

    TableColumn("Dimensione") { file in
        ObservedFileCell(file: file) { file in
            Text(file.formattedFileSize)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
    .width(min: 75, ideal: 95)

    TableColumn("Tipo") { file in
        ObservedFileCell(file: file) { file in
            Text(file.kindLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(file.kindLabel)
        }
    }
    .width(min: 90, ideal: 150)
}

/// Le celle osservano il file: i metadati (data, dimensione) arrivano in
/// modo asincrono e la riga si aggiorna da sola, senza dipendere da chi
/// possiede la lista.
private struct ObservedFileCell<Content: View>: View {
    @ObservedObject var file: AudioFile
    @ViewBuilder let content: (AudioFile) -> Content

    var body: some View {
        content(file)
    }
}
