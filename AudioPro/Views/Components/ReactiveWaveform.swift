import SwiftUI

/// Waveform a barre che si anima solo quando l'audio "vive": riproduzione
/// nella sezione Trascrizione, export nella sezione Esportazione.
/// A riposo il TimelineView è in pausa e la view è trasparente: zero CPU.
/// Con Reduce Motion attivo resta un frame statico, mai in movimento.
struct ReactiveWaveform: View {
    var isActive: Bool
    /// Moltiplicatore dell'opacità finale (es. attenuata dietro la trascrizione).
    var intensity: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAnimating: Bool { isActive && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            // Fase derivata dal clock: nessuno stato accumulato per frame,
            // la pausa congela le barre senza render aggiuntivi.
            let t = isAnimating ? context.date.timeIntervalSinceReferenceDate : 0

            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let midY = h / 2
                let step = w / 64
                var path = Path()

                for i in 0..<64 {
                    let x = CGFloat(i) * step + step / 2
                    let base = sin((Double(i) / 8) + (t * 0.4)) * 0.35 + 0.55
                    let secondary = sin((Double(i) / 5) + (t * 0.53)) * 0.15
                    let wobble = sin(t * 0.133) * 0.18
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
        }
        .scaleEffect(1.5, anchor: .center)
        .blur(radius: colorScheme == .dark ? 10 : 7)
        .opacity(isActive ? (colorScheme == .dark ? 0.55 : 0.92) * intensity : 0)
        .blendMode(colorScheme == .dark ? .screen : .normal)
        .animation(.easeInOut(duration: 0.6), value: isActive)
        .allowsHitTesting(false)
    }

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
}

struct ReactiveWaveform_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            AmbientBackdrop()
            ReactiveWaveform(isActive: true)
        }
        .frame(width: 420, height: 240)
    }
}
