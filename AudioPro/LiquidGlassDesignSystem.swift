import SwiftUI

// ============================================================================
// FILE: LiquidGlassDesignSystem.swift
// Design layer Liquid Glass condiviso tra AudioPro e TranscriptPlayer.
// macOS 26+: API native (.glassEffect, .glass/.glassProminent).
// macOS 14-15: fallback Material visivamente identico al comportamento storico.
// ============================================================================

/// Namespace per le costanti di design
enum LiquidGlassDesign {
    static let cornerRadius: CGFloat = 12
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
}

// MARK: - Shapes & Geometry

/// Rappresenta i tipi di forma per Liquid Glass
enum LiquidGlassShape {
    /// Raggio d'angolo costante (es. pannelli, card)
    case fixed(CGFloat)
    /// Raggio pari a metà dell'altezza (es. pulsanti)
    case capsule

    var shape: AnyShape {
        switch self {
        case .fixed(let radius):
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule:
            return AnyShape(Capsule())
        }
    }
}

// MARK: - Modifiers

extension View {
    /// Applica una superficie Liquid Glass standard
    /// - Parameter shape: La forma da applicare (default: fixed 12pt)
    @ViewBuilder
    func liquidGlassSurface(shape: LiquidGlassShape = .fixed(LiquidGlassDesign.cornerRadius)) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape.shape)
        } else {
            self.legacyGlassEffect(.regular, in: shape.shape)
        }
    }

    /// Applica una superficie Liquid Glass interattiva
    /// - Parameter shape: La forma da applicare (default: fixed 12pt)
    @ViewBuilder
    func liquidGlassControl(shape: LiquidGlassShape = .fixed(LiquidGlassDesign.cornerRadius)) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape.shape)
        } else {
            self.legacyGlassEffect(.interactive, in: shape.shape)
        }
    }

    /// Stile bottone Liquid Glass: nativo su macOS 26, custom sotto.
    /// I nativi .glass/.glassProminent sono PrimitiveButtonStyle, quindi il
    /// branch di disponibilità deve vivere in una View extension.
    /// Nota: la forma è decisa dallo stile (capsule nel fallback, metriche
    /// native su macOS 26) e volutamente non parametrizzabile.
    @ViewBuilder
    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(LiquidGlassButtonStyle(isProminent: prominent))
        }
    }
}

/// Contenitore che coordina effetti glass adiacenti (morphing su macOS 26).
struct LiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

// MARK: - Button Styles (fallback macOS 14-15)

struct LiquidGlassButtonStyle: ButtonStyle {
    var shape: LiquidGlassShape = .capsule
    var isProminent: Bool = false

    // Stato per gestire l'hovering
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    if isProminent {
                        // Prominent usa un effetto più forte o tint
                        Color.accentColor.opacity(isHovering ? 0.3 : 0.2)
                            .legacyGlassEffect(.interactive, in: shape.shape)
                    } else {
                        // Standard glass
                        Color.clear
                            .legacyGlassEffect(.interactive, in: shape.shape)
                            .background(
                                isHovering ? Color.white.opacity(0.1) : Color.clear
                            )
                            .clipShape(shape.shape)
                    }
                }
            }
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.02 : 1.0))
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// MARK: - Legacy fallback (macOS 14-15)

/// Approssimazione Material del glass per macOS < 26. Il rendering è
/// volutamente identico allo storico: nessuna regressione visiva sotto Tahoe.
private struct LegacyGlass {
    enum Kind {
        case regular
        case interactive
    }
    let kind: Kind
    static let regular = LegacyGlass(kind: .regular)
    static let interactive = LegacyGlass(kind: .interactive)

    var material: Material {
        switch kind {
        case .interactive: return .ultraThinMaterial
        case .regular: return .regularMaterial
        }
    }
}

private extension View {
    func legacyGlassEffect(_ glass: LegacyGlass, in shape: AnyShape) -> some View {
        self
            .background(glass.material)
            .clipShape(shape)
            .overlay {
                shape.stroke(.white.opacity(glass.kind == .interactive ? 0.25 : 0.15), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
