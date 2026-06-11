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
    static let controlCornerRadius: CGFloat = 16
    /// Superfici media (video, artwork): curva più generosa, da usare come
    /// minimum di ConcentricRectangle così gli angoli restano concentrici
    /// col contenitore quando la forma è vicina ai suoi bordi.
    static let mediaCornerRadius: CGFloat = 20
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
}
