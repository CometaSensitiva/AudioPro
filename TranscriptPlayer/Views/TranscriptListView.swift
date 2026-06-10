import SwiftUI

struct TranscriptListView: View, Equatable {
    let transcriptRevision: UUID
    let cues: [SubtitleCue]
    let activeCueID: SubtitleCue.ID?
    let canSeek: Bool
    let onSelect: (SubtitleCue) -> Void

    static func == (lhs: TranscriptListView, rhs: TranscriptListView) -> Bool {
        lhs.transcriptRevision == rhs.transcriptRevision
            && lhs.activeCueID == rhs.activeCueID
            && lhs.canSeek == rhs.canSeek
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(cues) { cue in
                        cueButton(for: cue)
                            .id(cue.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: activeCueID) { _, cueID in
                guard let cueID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(cueID, anchor: .center)
                }
            }
        }
        .liquidGlassSurface()
    }

    @ViewBuilder
    private func cueButton(for cue: SubtitleCue) -> some View {
        let isActive = cue.id == activeCueID
        let row = Button {
            onSelect(cue)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(formatTime(cue.start)) → \(formatTime(cue.end))")
                    .font(.caption)
                    .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
                    .frame(width: 100, alignment: .leading)

                Text(cue.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSeek)

        if isActive {
            row
                .foregroundStyle(.primary)
                .background {
                    Color.accentColor.opacity(0.18)
                        .liquidGlassSurface(shape: .fixed(10))
                }
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }
        } else {
            row
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainingSeconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
