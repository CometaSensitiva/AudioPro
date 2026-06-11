import SwiftUI

// ============================================================================
// FILE: LiquidGlassDesignSystem.swift
// Design layer Liquid Glass nativo (macOS 26+).
// Regola guida: il glass appartiene al layer funzionale (toolbar, controlli
// flottanti), mai al layer contenuto.
// ============================================================================

/// Namespace per le costanti di design (pattern Constants del sample Landmarks)
enum LiquidGlassDesign {
    static let cornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 16
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
}

// MARK: - Modifiers

extension View {
    /// Superficie Liquid Glass standard.
    /// Wrapper di transizione: i call site sul layer contenuto vengono
    /// de-glassati nelle fasi di polish, poi il wrapper sparisce.
    func liquidGlassSurface(cornerRadius: CGFloat = LiquidGlassDesign.cornerRadius) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Superficie Liquid Glass interattiva (controlli).
    func liquidGlassControl(cornerRadius: CGFloat = LiquidGlassDesign.cornerRadius) -> some View {
        glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
