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
    private var lightColors: [Color] {
        switch style {
        case .detail:
            return [
                Color(red: 0.91, green: 0.95, blue: 1.00),
                Color(red: 0.88, green: 0.93, blue: 1.00),
                Color(red: 0.86, green: 0.92, blue: 0.99),
                Color(red: 0.88, green: 0.92, blue: 0.99),
                Color(red: 0.90, green: 0.90, blue: 0.99),
                Color(red: 0.92, green: 0.90, blue: 0.99),
                Color(red: 0.93, green: 0.90, blue: 0.98),
                Color(red: 0.95, green: 0.89, blue: 0.97),
                Color(red: 0.96, green: 0.89, blue: 0.97)
            ]
        case .sidebar:
            return [
                Color(red: 0.93, green: 0.96, blue: 1.00),
                Color(red: 0.92, green: 0.95, blue: 1.00),
                Color(red: 0.91, green: 0.94, blue: 0.99),
                Color(red: 0.92, green: 0.94, blue: 0.99),
                Color(red: 0.93, green: 0.93, blue: 0.99),
                Color(red: 0.94, green: 0.93, blue: 0.99),
                Color(red: 0.94, green: 0.93, blue: 0.98),
                Color(red: 0.95, green: 0.92, blue: 0.98),
                Color(red: 0.96, green: 0.92, blue: 0.98)
            ]
        }
    }

    private var darkColors: [Color] {
        switch style {
        case .detail:
            return [
                Color(red: 0.10, green: 0.14, blue: 0.24),
                Color(red: 0.09, green: 0.12, blue: 0.21),
                Color(red: 0.08, green: 0.10, blue: 0.18),
                Color(red: 0.10, green: 0.12, blue: 0.21),
                Color(red: 0.11, green: 0.11, blue: 0.20),
                Color(red: 0.12, green: 0.11, blue: 0.20),
                Color(red: 0.12, green: 0.10, blue: 0.19),
                Color(red: 0.13, green: 0.11, blue: 0.21),
                Color(red: 0.14, green: 0.11, blue: 0.21)
            ]
        case .sidebar:
            return [
                Color(red: 0.09, green: 0.12, blue: 0.20),
                Color(red: 0.09, green: 0.11, blue: 0.18),
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.09, green: 0.11, blue: 0.18),
                Color(red: 0.10, green: 0.10, blue: 0.17),
                Color(red: 0.10, green: 0.10, blue: 0.17),
                Color(red: 0.10, green: 0.09, blue: 0.16),
                Color(red: 0.11, green: 0.10, blue: 0.17),
                Color(red: 0.11, green: 0.10, blue: 0.17)
            ]
        }
    }

    @ViewBuilder
    private var highlight: some View {
        if colorScheme == .light {
            RadialGradient(
                colors: [
                    Color.white.opacity(style == .detail ? 0.45 : 0.25),
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

struct AmbientBackdrop_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AmbientBackdrop()
            AmbientBackdrop(style: .sidebar)
        }
        .frame(width: 360, height: 240)
    }
}
