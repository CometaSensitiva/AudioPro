import SwiftUI

struct FileInfoBlock: View {
    let preview: ExportPreview
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Output stimato")
                .font(.title3.weight(.semibold))

            HStack(alignment: .top, spacing: 28) {
                SummaryMetric(label: "Durata finale", value: preview.totalDurationLabel, icon: "clock")
                SummaryMetric(label: "Output", value: preview.estimatedOutputLabel, icon: "externaldrive")
                SummaryMetric(label: "Risparmio", value: preview.savingsLabel, icon: "arrow.down.circle")
            }

            Divider()

            LabeledContent("Compressione") {
                Text(preview.compressionSummary)
                    .foregroundStyle(.secondary)
            }
            
            if let message = preview.inspectorStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SummaryMetric: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FileInfoBlock_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let appState = PreviewSamples.appState()
        FileInfoBlock(preview: appState.exportPreview)
            .padding()
    }
}
