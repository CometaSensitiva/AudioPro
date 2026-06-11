import SwiftUI

struct TranscriptListView: View, Equatable {
    let cues: [SubtitleCue]
    let activeCueID: SubtitleCue.ID?
    let matchIDs: Set<SubtitleCue.ID>
    let currentMatchID: SubtitleCue.ID?
    let canSeek: Bool
    let onSelect: (SubtitleCue) -> Void

    @State private var hoveredCueID: SubtitleCue.ID?

    // onSelect è escluso di proposito: viene ricreato a ogni body del parent.
    // Il confronto di cues è O(n) solo quando il resto è uguale, e corto-
    // circuita sui cambi frequenti (activeCueID).
    static func == (lhs: TranscriptListView, rhs: TranscriptListView) -> Bool {
        lhs.activeCueID == rhs.activeCueID
            && lhs.currentMatchID == rhs.currentMatchID
            && lhs.matchIDs == rhs.matchIDs
            && lhs.canSeek == rhs.canSeek
            && lhs.cues == rhs.cues
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
            .onChange(of: currentMatchID) { _, matchID in
                guard let matchID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(matchID, anchor: .center)
                }
            }
            // La lista è layer contenuto: niente glass, scorre sotto la
            // toolbar con un edge effect morbido.
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ViewBuilder
    private func cueButton(for cue: SubtitleCue) -> some View {
        let isActive = cue.id == activeCueID
        let row = Button {
            onSelect(cue)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(cue.start.playerDisplayString) → \(cue.end.playerDisplayString)")
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

        let isCurrentMatch = cue.id == currentMatchID

        if isActive {
            row
                .foregroundStyle(.primary)
                .background(
                    Color.accentColor.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }
        } else {
            row
                .background(
                    rowFill(for: cue, isCurrentMatch: isCurrentMatch),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    if isCurrentMatch {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.yellow.opacity(0.7), lineWidth: 1.5)
                    }
                }
                .onHover { hovering in
                    hoveredCueID = hovering ? cue.id : nil
                }
        }
    }

    private func rowFill(for cue: SubtitleCue, isCurrentMatch: Bool) -> Color {
        if isCurrentMatch {
            return Color.yellow.opacity(0.28)
        }
        if matchIDs.contains(cue.id) {
            return Color.yellow.opacity(0.14)
        }
        if hoveredCueID == cue.id && canSeek {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }
}
