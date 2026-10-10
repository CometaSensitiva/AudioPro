import AVKit
import SwiftUI
import XCTest
@testable import AudioPro

@MainActor
final class PlayerVideoViewTests: XCTestCase {
    func testNativeVideoSurfaceKeepsFullPlaybackControls() {
        let player = AVPlayer()
        let view = PlayerVideoNSView(player: player)

        XCTAssertTrue(view.player === player)
        XCTAssertEqual(view.controlsStyle, .floating)
        XCTAssertEqual(view.videoGravity, .resizeAspect)
        XCTAssertTrue(view.showsFullScreenToggleButton)
    }

    func testSwiftUIWrapperConstructsAVPlayerView() {
        let player = AVPlayer()
        let hostingView = NSHostingView(
            rootView: PlayerVideoView(player: player)
                .frame(width: 640, height: 360)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        hostingView.layoutSubtreeIfNeeded()

        let playerView = findPlayerView(in: hostingView)
        XCTAssertNotNil(playerView)
        XCTAssertTrue(playerView?.player === player)
    }

    func testVideoSizeModesHaveStableLabelsAndResponsiveHeights() {
        let generousContainer = CGSize(width: 1_200, height: 900)

        XCTAssertEqual(PlayerVideoSizeMode.allCases.map(\.displayName), [
            "Piccolo",
            "Medio",
            "Grande",
            "Teatro"
        ])
        XCTAssertLessThan(
            PlayerVideoSizeMode.small.frame(in: generousContainer, aspectRatio: 16 / 9).height,
            PlayerVideoSizeMode.medium.frame(in: generousContainer, aspectRatio: 16 / 9).height
        )
        XCTAssertLessThan(
            PlayerVideoSizeMode.medium.frame(in: generousContainer, aspectRatio: 16 / 9).height,
            PlayerVideoSizeMode.large.frame(in: generousContainer, aspectRatio: 16 / 9).height
        )
        XCTAssertGreaterThan(
            PlayerVideoSizeMode.theater.frame(in: generousContainer, aspectRatio: 16 / 9).height,
            PlayerVideoSizeMode.large.frame(in: generousContainer, aspectRatio: 16 / 9).height
        )
        XCTAssertEqual(
            PlayerVideoSizeMode.mode(forStoredRawValue: "fit"),
            .theater
        )
    }

    private func findPlayerView(in view: NSView) -> AVPlayerView? {
        if let playerView = view as? AVPlayerView {
            return playerView
        }

        return view.subviews.lazy.compactMap(findPlayerView(in:)).first
    }
}
