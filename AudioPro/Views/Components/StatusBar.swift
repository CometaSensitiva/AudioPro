import SwiftUI

struct StatusBar: View {
    let state: ProcessingState
    var onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            switch state {
            case .idle:
                Text("Pronto")
                    .foregroundStyle(.secondary)
            case .running(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Annulla", role: .destructive, action: onCancel)
                    .buttonStyle(.link)
            case .completed:
                Label("Esportazione completata", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
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
            StatusBar(state: .completed, onCancel: {})
        }
        .padding()
    }
}
