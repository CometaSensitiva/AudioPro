import SwiftUI

// ============================================================================
// FILE: LiquidGlassDesignSystem.swift
// Tokens di design condivisi (pattern Constants del sample Landmarks).
// Il glass si applica direttamente con le API native (.glassEffect,
// GlassEffectContainer, .buttonStyle(.glass/.glassProminent)) e appartiene
// al solo layer funzionale: player bar, status bar export, toolbar.
// ============================================================================

enum LiquidGlassDesign {
    static let cornerRadius: CGFloat = 12
    /// Raggio delle card di contenuto: curva morbida moderna (macOS 26),
    /// concentrica coi controlli.
    static let cardCornerRadius: CGFloat = 16
    static let controlCornerRadius: CGFloat = 16
    /// Righe di lista/trascrizione (livello contenuto): leggermente più
    /// morbide della card ma non quanto un controllo.
    static let rowCornerRadius: CGFloat = 10
    /// Superfici media (video, artwork): curva più generosa e FISSA.
    /// Niente ConcentricRectangle qui: risolve contro la finestra e
    /// collassa al ridimensionamento quando la forma fluttua nel contenuto.
    static let mediaCornerRadius: CGFloat = 24
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
    /// Larghezza di lettura massima delle colonne di contenuto testuale,
    /// condivisa fra le sezioni per una misura di riga coerente.
    static let contentMaxWidth: CGFloat = 720
    /// Un solo dimensionamento per le colonne impostazioni delle feature.
    /// Evita che Esportazione e Trascrizione cambino densità quando si passa
    /// da una sezione all'altra.
    static let inspectorMinWidth: CGFloat = 320
    static let inspectorIdealWidth: CGFloat = 360
    static let inspectorMaxWidth: CGFloat = 420
}

/// Colori semantici condivisi: un'unica sorgente per gli stati, così le
/// sezioni non divergono (es. errore .orange vs .red). Successo verde,
/// avviso non bloccante arancione, errore/fallimento rosso.
enum LiquidGlassStatusColor {
    static let success = Color.green
    static let warning = Color.orange
    static let failure = Color.red
}

extension View {
    /// Card del livello contenuto (macOS 26): material di sistema standard —
    /// NON glass (il glass appartiene al layer controlli). Bordo hairline
    /// `.separator` + ombra tenue. Legge pulito perché il canvas ambient è
    /// calmo (vedi AmbientBackdrop): la definizione la danno bordo e ombra,
    /// non un material opaco. Componente UNICO per tutte le sezioni.
    func contentCard(padding: CGFloat = LiquidGlassDesign.padding) -> some View {
        let shape = RoundedRectangle(cornerRadius: LiquidGlassDesign.cardCornerRadius, style: .continuous)
        return self
            .padding(padding)
            .background(.regularMaterial, in: shape)
            .overlay {
                shape.strokeBorder(.separator, lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    /// Vincola il contenuto testuale alla misura di riga condivisa, centrato.
    func contentReadingWidth() -> some View {
        self
            .frame(maxWidth: LiquidGlassDesign.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }
}

struct AudioProBottomGlassBar<Content: View>: View {
    let isInteractive: Bool
    let verticalPadding: CGFloat
    let content: Content

    init(
        isInteractive: Bool = true,
        verticalPadding: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.isInteractive = isInteractive
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        glassSurface
            .padding(.horizontal, LiquidGlassDesign.padding)
            .padding(.bottom, LiquidGlassDesign.spacing)
    }

    @ViewBuilder
    private var glassSurface: some View {
        if isInteractive {
            paddedContent
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: LiquidGlassDesign.controlCornerRadius, style: .continuous)
                )
        } else {
            paddedContent
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: LiquidGlassDesign.controlCornerRadius, style: .continuous)
                )
        }
    }

    private var paddedContent: some View {
        content
            .padding(.horizontal, LiquidGlassDesign.padding)
            .padding(.vertical, verticalPadding)
    }
}

/// Dispone stato e azioni sulla stessa riga quando c'è spazio e passa a una
/// composizione verticale nelle finestre strette. È la grammatica condivisa
/// delle barre inferiori di Esportazione e Trascrizione.
struct ResponsiveActionRow<Status: View, Actions: View>: View {
    let status: Status
    let actions: Actions

    init(
        @ViewBuilder status: () -> Status,
        @ViewBuilder actions: () -> Actions
    ) {
        self.status = status()
        self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LiquidGlassDesign.spacing) {
                status
                    .frame(maxWidth: .infinity, alignment: .leading)
                actions
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 10) {
                status
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
    }
}
