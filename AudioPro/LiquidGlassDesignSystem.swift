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
    /// Superfici media (video, artwork): curva più generosa e FISSA.
    /// Niente ConcentricRectangle qui: risolve contro la finestra e
    /// collassa al ridimensionamento quando la forma fluttua nel contenuto.
    static let mediaCornerRadius: CGFloat = 24
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
}
