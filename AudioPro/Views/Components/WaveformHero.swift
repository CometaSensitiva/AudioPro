import SwiftUI

/// Sfondo ondulato per le viste di dettaglio, con movimento organico ispirato al mock.
struct WaveformBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(colors: [
                Color.accentColor.opacity(0.28),
                Color.blue.opacity(0.2),
                Color.purple.opacity(0.18)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(
                stops: [
                    .init(color: Color(red: 0.91, green: 0.95, blue: 1.00), location: 0.0),
                    .init(color: Color(red: 0.86, green: 0.92, blue: 0.99), location: 0.28),
                    .init(color: Color(red: 0.90, green: 0.90, blue: 0.99), location: 0.58),
                    .init(color: Color(red: 0.96, green: 0.89, blue: 0.97), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        backgroundGradient
        .overlay {
            if colorScheme == .light {
                ZStack {
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.blue.opacity(0.08),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 24,
                        endRadius: 420
                    )
                    .offset(x: -80, y: -60)

                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 360
                    )
                    .offset(x: -40, y: 10)

                    RadialGradient(
                        colors: [
                            Color.pink.opacity(0.16),
                            Color.purple.opacity(0.08),
                            Color.clear
                        ],
                        center: .bottomTrailing,
                        startRadius: 30,
                        endRadius: 340
                    )
                    .offset(x: 80, y: 120)
                }
            }
        }
        .overlay {
            AnimatedWave(colorScheme: colorScheme)
                .scaleEffect(1.5, anchor: .center)
                .blur(radius: colorScheme == .dark ? 10 : 7)
                .opacity(colorScheme == .dark ? 0.55 : 0.92)
                .blendMode(colorScheme == .dark ? .screen : .normal)
                .offset(y: -12)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill((colorScheme == .dark ? Color.white : Color.black).opacity(colorScheme == .dark ? 0.06 : 0.04))
                .frame(width: 240, height: 240)
                .blur(radius: 26)
                .offset(x: 50, y: 90)
        }
    }
}

private struct AnimatedWave: View {
    let colorScheme: ColorScheme
    @State private var t: CGFloat = 0

    private func waveShading(in size: CGSize) -> GraphicsContext.Shading {
        if colorScheme == .dark {
            return .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(0.30),
                    Color.cyan.opacity(0.18),
                    Color.purple.opacity(0.16)
                ]),
                startPoint: CGPoint(x: size.width * 0.2, y: 0),
                endPoint: CGPoint(x: size.width * 0.8, y: size.height)
            )
        } else {
            return .linearGradient(
                Gradient(colors: [
                    Color(red: 0.15, green: 0.22, blue: 0.34).opacity(0.28),
                    Color(red: 0.28, green: 0.34, blue: 0.48).opacity(0.22),
                    Color(red: 0.43, green: 0.34, blue: 0.52).opacity(0.18)
                ]),
                startPoint: CGPoint(x: 0, y: size.height * 0.2),
                endPoint: CGPoint(x: size.width, y: size.height * 0.85)
            )
        }
    }
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.03)) { context in
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let midY = h / 2
                let step = w / 64
                var path = Path()
                
                for i in 0..<64 {
                    let x = CGFloat(i) * step + step / 2
                    let base = sin((CGFloat(i) / 8) + (t * 0.6)) * 0.35 + 0.55
                    let secondary = sin((CGFloat(i) / 5) + (t * 0.8)) * 0.15
                    let wobble = sin(t * 0.2) * 0.18
                    let value = base + secondary + wobble
                    let clamped = max(0, min(1, value))
                    let barHeight = h * 0.3 * clamped
                    let rect = CGRect(
                        x: x - (step * 0.36 / 2),
                        y: midY - barHeight,
                        width: step * 0.36,
                        height: barHeight * 2
                    )
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
                }
                
                ctx.fill(path, with: waveShading(in: size))
            }
            .onChange(of: context.date) { _, _ in t += 0.02 }
        }
    }
}

struct WaveformBackdrop_Previews: PreviewProvider {
    static var previews: some View {
        WaveformBackdrop()
            .frame(height: 240)
            .padding()
    }
}
