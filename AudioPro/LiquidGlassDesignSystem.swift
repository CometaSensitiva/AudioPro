import SwiftUI

// ============================================================================
// FILE: LiquidGlassDesignSystem.swift
// Design System Layer per l'adozione di Liquid Glass (macOS 26+)
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
    /// Raggio calcolato concentricamente (raggio genitore - padding)
    case concentric(parentRadius: CGFloat, padding: CGFloat)
    
    var shape: AnyShape {
        switch self {
        case .fixed(let radius):
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule:
            return AnyShape(Capsule())
        case .concentric(let parent, let padding):
            let childRadius = max(0, parent - padding)
            return AnyShape(RoundedRectangle(cornerRadius: childRadius, style: .continuous))
        }
    }
}

// MARK: - Modifiers

extension View {
    /// Applica una superficie Liquid Glass standard
    /// - Parameter shape: La forma da applicare (default: fixed 12pt)
    func liquidGlassSurface(shape: LiquidGlassShape = .fixed(LiquidGlassDesign.cornerRadius)) -> some View {
        self.glassEffect(Glass.regular, in: shape.shape)
    }
    
    /// Applica una superficie Liquid Glass interattiva
    /// - Parameter shape: La forma da applicare (default: fixed 12pt)
    func liquidGlassControl(shape: LiquidGlassShape = .fixed(LiquidGlassDesign.cornerRadius)) -> some View {
        self.glassEffect(Glass.interactive, in: shape.shape)
    }
    
    /// Estende l'effetto di sfondo dietro la sidebar (Mock)
    func glassBackgroundExtension() -> some View {
        self // In macOS 26 questo estenderebbe il materiale nella window chrome
            .background(Material.ultraThinMaterial)
    }
}

/// Spaziatore per Toolbar (Mock)
struct ToolbarSpacer: ToolbarContent {
    enum Kind {
        case flexible
        case fixed
    }
    
    private let kind: Kind
    
    init(_ kind: Kind = .flexible) {
        self.kind = kind
    }
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Spacer(minLength: kind == .fixed ? 12 : nil)
        }
    }
}

// MARK: - Button Styles

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
                            .glassEffect(Glass.interactive, in: shape.shape)
                    } else {
                        // Standard glass
                        Color.clear
                            .glassEffect(Glass.interactive, in: shape.shape)
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

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle { LiquidGlassButtonStyle() }
    
    static func liquidGlass(shape: LiquidGlassShape) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(shape: shape)
    }
    
    static var liquidGlassProminent: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(shape: .capsule, isProminent: true)
    }
}

// MARK: - Stub Liquid Glass API (compatibility)

/// Minimal placeholder for the future Glass style used by glassEffect.
struct Glass: Equatable {
    enum Kind {
        case regular
        case interactive
        case systemMaterial
    }
    let kind: Kind
    static let regular = Glass(kind: .regular)
    static let interactive = Glass(kind: .interactive)
    static let systemMaterial = Glass(kind: .systemMaterial)
    
    var material: Material {
        switch kind {
        case .interactive: return .ultraThinMaterial
        case .regular: return .regularMaterial
        case .systemMaterial: return .bar
        }
    }
}

/// Backport/stub for the `glassEffect(_:in:)` modifier used throughout the design system.
extension View {
    func glassEffect(_ glass: Glass, in shape: AnyShape) -> some View {
        // Simple approximation: material background clipped to shape, with a subtle stroke.
        self
            .background(glass.material)
            .clipShape(shape)
            .overlay {
                shape.stroke(.white.opacity(glass.kind == .interactive ? 0.25 : 0.15), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Mocks for Future APIs (macOS 26)

/// Contenitore che coordina gli effetti Liquid Glass
struct GlassEffectContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
    }
}

extension View {
    /// Identifica una vista per le transizioni Liquid Glass
    func glassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        self.matchedGeometryEffect(id: id, in: namespace)
    }
    
    /// Stub per glassEffectID se matchedGeometryEffect non è desiderato o per compatibilità
    func glassEffectID(_ id: String) -> some View {
        self
    }
}
