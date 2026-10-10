import SwiftUI

struct TranscriptCueVisualState: Equatable {
    let isActive: Bool
    let isMatch: Bool
    let isCurrentMatch: Bool

    init(
        cueID: SubtitleCue.ID,
        activeCueID: SubtitleCue.ID?,
        matchIDs: Set<SubtitleCue.ID>,
        currentMatchID: SubtitleCue.ID?
    ) {
        self.isActive = cueID == activeCueID
        self.isMatch = matchIDs.contains(cueID)
        self.isCurrentMatch = cueID == currentMatchID
    }

    var showsActiveAccent: Bool { isActive }
    var showsSearchIndicator: Bool { isMatch || isCurrentMatch }
    var showsCurrentMatchOutline: Bool { isCurrentMatch }
}

struct TranscriptListView: View, Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cues: [SubtitleCue]
    let activeCueID: SubtitleCue.ID?
    let matchIDs: Set<SubtitleCue.ID>
    let currentMatchID: SubtitleCue.ID?
    let canSeek: Bool
    let onSelect: (SubtitleCue) -> Void

    @State private var hoveredCueID: SubtitleCue.ID?
    @ScaledMetric(relativeTo: .caption) private var timecodeColumnWidth: CGFloat = 112

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
                scroll(to: cueID, using: proxy)
            }
            .onChange(of: currentMatchID) { _, matchID in
                guard let matchID else { return }
                scroll(to: matchID, using: proxy)
            }
            // La lista è layer contenuto: niente glass, scorre sotto la
            // toolbar con un edge effect morbido.
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ViewBuilder
    private func cueButton(for cue: SubtitleCue) -> some View {
        let visualState = TranscriptCueVisualState(
            cueID: cue.id,
            activeCueID: activeCueID,
            matchIDs: matchIDs,
            currentMatchID: currentMatchID
        )
        let rowContent =
            HStack(alignment: .top, spacing: 10) {
                cueIndicator(for: visualState)

                Text(timecodeLabel(for: cue))
                    .font(.caption)
                    .foregroundStyle(
                        visualState.isActive
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(.secondary)
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: timecodeColumnWidth, alignment: .leading)

                Text(cue.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .contentShape(Rectangle())

        let row = Group {
            if canSeek {
                Button {
                    onSelect(cue)
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Da \(cue.start.playerDisplayString) a \(cue.end.playerDisplayString). \(cue.text)"
        )
        .accessibilityValue(
            accessibilityStatus(for: visualState)
        )
        .accessibilityHint(
            canSeek
                ? "Riproduce il segmento da questo punto."
                : "Testo selezionabile. Apri un file multimediale per riprodurre il segmento."
        )
        .accessibilityAddTraits(visualState.isActive ? .isSelected : [])

        row
            .foregroundStyle(.primary)
            .background(
                rowFill(for: cue, visualState: visualState),
                in: RoundedRectangle(cornerRadius: LiquidGlassDesign.rowCornerRadius, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if visualState.showsActiveAccent {
                    // Barra accento sottile: raggio quasi retto, dettaglio locale.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }
            }
            .overlay {
                if visualState.showsCurrentMatchOutline {
                    RoundedRectangle(cornerRadius: LiquidGlassDesign.rowCornerRadius, style: .continuous)
                        .stroke(Color.yellow.opacity(0.7), lineWidth: 1.5)
                }
            }
            .onHover { hovering in
                hoveredCueID = hovering ? cue.id : nil
            }
    }

    private func rowFill(
        for cue: SubtitleCue,
        visualState: TranscriptCueVisualState
    ) -> Color {
        if visualState.isActive {
            return Color.accentColor.opacity(0.15)
        }
        if visualState.isCurrentMatch {
            return Color.yellow.opacity(0.28)
        }
        if visualState.isMatch {
            return Color.yellow.opacity(0.14)
        }
        if hoveredCueID == cue.id && canSeek {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }

    private func timecodeLabel(for cue: SubtitleCue) -> String {
        "\(cue.start.playerDisplayString) → \(cue.end.playerDisplayString)"
    }

    private func scroll(to cueID: SubtitleCue.ID, using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(cueID, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(cueID, anchor: .center)
            }
        }
    }

    private func accessibilityStatus(for visualState: TranscriptCueVisualState) -> String {
        var states: [String] = []
        if visualState.isActive {
            states.append("Segmento in riproduzione")
        }
        if visualState.isCurrentMatch {
            states.append("Risultato di ricerca corrente")
        } else if visualState.isMatch {
            states.append("Risultato di ricerca")
        }
        if canSeek == false {
            states.append("Apri un file audio o video per riprodurre questo segmento")
        }
        return states.isEmpty ? "Segmento" : states.joined(separator: ". ")
    }

    private func cueIndicator(for visualState: TranscriptCueVisualState) -> some View {
        HStack(spacing: 2) {
            if visualState.isActive {
                Image(systemName: "play.fill")
                    .foregroundStyle(.tint)
            }
            if visualState.isCurrentMatch {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundStyle(.primary)
            } else if visualState.showsSearchIndicator {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2.weight(.semibold))
        .frame(width: 28, height: 16, alignment: .leading)
        .accessibilityHidden(true)
    }
}
