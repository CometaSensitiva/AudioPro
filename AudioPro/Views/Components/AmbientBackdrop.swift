import SwiftUI

/// Sfondo statico "ambient" dietro le superfici glass: gradienti ricchi ma
/// calmi (il glass rifrange ciò che ha dietro — gli sfondi in movimento
/// continuo rendono male). Il movimento è delegato a ReactiveWaveform.
struct AmbientBackdrop: View {
    enum Style {
        case sidebar
        case detail
    }

    var style: Style = .detail
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        mesh
            .overlay { highlight }
    }

    private var mesh: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: colorScheme == .dark ? darkColors : lightColors
        )
    }

    // Palette derivata dallo storico WaveformBackdrop/SidebarBackdrop:
    // azzurri freddi in alto, viola/rosa tenui verso il basso.
    // Canvas "sussurrato": chroma minima (delta ≲ 0.02 fra gli angoli) così
    // le card material e i controlli glass risaltano invece di mescolarsi.
    private var lightColors: [Color] {
        switch style {
        case .detail:
            return [
                Color(red: 0.965, green: 0.975, blue: 0.990),
                Color(red: 0.965, green: 0.972, blue: 0.986),
                Color(red: 0.966, green: 0.970, blue: 0.982),
                Color(red: 0.970, green: 0.972, blue: 0.984),
                Color(red: 0.972, green: 0.970, blue: 0.982),
                Color(red: 0.975, green: 0.969, blue: 0.980),
                Color(red: 0.977, green: 0.968, blue: 0.978),
                Color(red: 0.980, green: 0.967, blue: 0.977),
                Color(red: 0.982, green: 0.966, blue: 0.976)
            ]
        case .sidebar:
            return [
                Color(red: 0.972, green: 0.980, blue: 0.992),
                Color(red: 0.972, green: 0.978, blue: 0.989),
                Color(red: 0.973, green: 0.976, blue: 0.986),
                Color(red: 0.975, green: 0.977, blue: 0.987),
                Color(red: 0.977, green: 0.975, blue: 0.985),
                Color(red: 0.979, green: 0.974, blue: 0.984),
                Color(red: 0.980, green: 0.973, blue: 0.983),
                Color(red: 0.982, green: 0.972, blue: 0.982),
                Color(red: 0.984, green: 0.972, blue: 0.982)
            ]
        }
    }

    private var darkColors: [Color] {
        switch style {
        case .detail:
            return [
                Color(red: 0.120, green: 0.126, blue: 0.150),
                Color(red: 0.116, green: 0.121, blue: 0.144),
                Color(red: 0.112, green: 0.116, blue: 0.138),
                Color(red: 0.116, green: 0.120, blue: 0.142),
                Color(red: 0.120, green: 0.121, blue: 0.140),
                Color(red: 0.124, green: 0.121, blue: 0.139),
                Color(red: 0.126, green: 0.119, blue: 0.137),
                Color(red: 0.130, green: 0.120, blue: 0.138),
                Color(red: 0.132, green: 0.120, blue: 0.138)
            ]
        case .sidebar:
            return [
                Color(red: 0.108, green: 0.115, blue: 0.138),
                Color(red: 0.105, green: 0.111, blue: 0.133),
                Color(red: 0.102, green: 0.107, blue: 0.128),
                Color(red: 0.105, green: 0.110, blue: 0.131),
                Color(red: 0.108, green: 0.110, blue: 0.129),
                Color(red: 0.111, green: 0.110, blue: 0.128),
                Color(red: 0.113, green: 0.109, blue: 0.127),
                Color(red: 0.116, green: 0.110, blue: 0.128),
                Color(red: 0.118, green: 0.110, blue: 0.128)
            ]
        }
    }

    @ViewBuilder
    private var highlight: some View {
        if colorScheme == .light {
            RadialGradient(
                colors: [
                    Color.white.opacity(style == .detail ? 0.22 : 0.14),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 24,
                endRadius: 420
            )
            .offset(x: -80, y: -60)
        }
    }
}

/// Sfondo condiviso di sezione: backdrop ambient + waveform reattiva, con
/// `ignoresSafeArea()` uniforme. Sostituisce lo stack copiato in Esportazione,
/// Trascrizione e Riproduzione, così i tre pannelli restano identici.
struct SectionBackground: ViewModifier {
    var isActive: Bool
    var intensity: Double = 1

    // Sfondo di sistema, come nelle app Apple: niente gradiente su misura
    // né animazioni di fondo. Il modificatore resta come punto unico per
    // le tre sezioni.
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    /// Applica lo sfondo ambient di sezione con la waveform reattiva.
    func sectionBackground(isActive: Bool, intensity: Double = 1) -> some View {
        modifier(SectionBackground(isActive: isActive, intensity: intensity))
    }
}

struct AmbientBackdrop_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AmbientBackdrop()
            AmbientBackdrop(style: .sidebar)
        }
        .frame(width: 360, height: 240)
    }
}
