import AVKit
import SwiftUI

/// Player AppKit completo. Evita il bridge SwiftUI di `VideoPlayer`, ma
/// conserva i controlli nativi sul video oltre alla transport bar di AudioPro.
struct PlayerVideoView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerVideoNSView {
        PlayerVideoNSView(player: player)
    }

    func updateNSView(_ nsView: PlayerVideoNSView, context: Context) {
        nsView.player = player
    }

    static func dismantleNSView(_ nsView: PlayerVideoNSView, coordinator: Void) {
        nsView.player = nil
    }
}

final class PlayerVideoNSView: AVPlayerView {
    init(player: AVPlayer) {
        super.init(frame: .zero)
        self.player = player
        controlsStyle = .inline
        videoGravity = .resizeAspect
        showsFullScreenToggleButton = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }
}
