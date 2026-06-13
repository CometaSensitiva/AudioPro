import AVFoundation
import Combine
import Foundation

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var hasVideo = false
    /// Larghezza/altezza della traccia video (trasformata), per dimensionare
    /// il VideoPlayer sul formato reale invece che su un'altezza fissa.
    @Published private(set) var videoAspectRatio: CGFloat?
    @Published private(set) var hasMedia = false
    @Published private(set) var mediaURL: URL?
    @Published private(set) var mediaName: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var playbackRate: Float = 1.0

    static let availableRates: [Float] = [0.5, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5]

    let player = AVPlayer()

    private var timeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var timeControlCancellable: AnyCancellable?
    private var securityScopedMediaURL: URL?
    private var loadTask: Task<Void, Never>?
    private var loadIdentifier = UUID()
    private var pendingSeeks = 0

    init() {
        installTimeControlObserver()
    }

    deinit {
        loadTask?.cancel()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        securityScopedMediaURL?.stopAccessingSecurityScopedResource()
    }

    func loadMedia(from url: URL) {
        resetMedia()
        errorMessage = nil
        mediaURL = url
        mediaName = url.lastPathComponent

        if url.startAccessingSecurityScopedResource() {
            securityScopedMediaURL = url
        }

        // L'observer vive col media, non col controller: senza file caricato
        // non c'è nulla da osservare 4 volte al secondo.
        installTimeObserver()

        let identifier = UUID()
        loadIdentifier = identifier
        let asset = AVURLAsset(url: url)

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let playable = asset.load(.isPlayable)
                async let loadedDuration = asset.load(.duration)
                async let videoTracks = asset.loadTracks(withMediaType: .video)

                let (isPlayable, assetDuration, tracks) = try await (
                    playable,
                    loadedDuration,
                    videoTracks
                )
                try Task.checkCancellation()
                guard self.loadIdentifier == identifier else { return }
                guard isPlayable else {
                    throw PlayerError.mediaNotPlayable
                }

                var aspectRatio: CGFloat?
                if let track = tracks.first {
                    async let naturalSize = track.load(.naturalSize)
                    async let transform = track.load(.preferredTransform)
                    // Il transform gestisce i video registrati ruotati, dove
                    // naturalSize è invertita rispetto alla resa a schermo.
                    let rect = CGRect(origin: .zero, size: try await naturalSize)
                        .applying(try await transform)
                    if abs(rect.height) > 0 {
                        aspectRatio = abs(rect.width) / abs(rect.height)
                    }
                }
                try Task.checkCancellation()
                guard self.loadIdentifier == identifier else { return }

                let item = AVPlayerItem(asset: asset)
                // Pitch corretto anche alle alte velocità: qualità migliore
                // per il parlato delle lezioni rispetto al default.
                item.audioTimePitchAlgorithm = .spectral
                self.player.replaceCurrentItem(with: item)
                self.installPlaybackEndObserver(for: item)
                self.duration = assetDuration.seconds.isFinite ? max(0, assetDuration.seconds) : 0
                self.hasVideo = !tracks.isEmpty
                self.videoAspectRatio = aspectRatio
                self.hasMedia = true
            } catch is CancellationError {
                return
            } catch {
                guard self.loadIdentifier == identifier else { return }
                self.errorMessage = error.localizedDescription
                self.releaseSecurityScope()
                self.mediaName = nil
            }
        }
    }

    func unloadMedia() {
        resetMedia()
        errorMessage = nil
    }

    func setPlaybackRate(_ rate: Float) {
        guard Self.availableRates.contains(rate) else { return }
        playbackRate = rate
        // defaultRate è l'API nativa: play() e i riavvii ripartono da qui.
        player.defaultRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard hasMedia else { return }
        if duration > 0, currentTime >= duration {
            seek(to: 0)
        }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seekBy(_ delta: TimeInterval) {
        guard hasMedia else { return }
        seek(to: currentTime + delta)
    }

    func seek(to seconds: TimeInterval) {
        guard hasMedia else { return }
        let upperBound = duration > 0 ? duration : seconds
        let clamped = min(max(0, seconds), upperBound)
        // currentTime è aggiornato ottimisticamente qui sotto; finché il seek
        // asincrono non completa, l'observer periodico riporterebbe il tempo
        // PRE-seek facendo rimbalzare indietro slider e cue evidenziata.
        pendingSeeks += 1
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor [controller] in
                controller.pendingSeeks = max(0, controller.pendingSeeks - 1)
            }
        }
        updateCurrentTime(clamped)
    }

    private func installTimeObserver() {
        removeTimeObserverIfNeeded()
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.hasMedia, self.pendingSeeks == 0 else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.updateCurrentTime(seconds)
                }
            }
        }
    }

    private func installTimeControlObserver() {
        // isPlaying deriva dallo stato reale del player: se un media non parte
        // (file non riproducibile, errore in sandbox) il bottone non resta su "pausa".
        timeControlCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    self?.isPlaying = status != .paused
                }
            }
    }

    private func installPlaybackEndObserver(for item: AVPlayerItem) {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateCurrentTime(self.duration)
            }
        }
    }

    private func removeTimeObserverIfNeeded() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func resetMedia() {
        loadTask?.cancel()
        loadTask = nil
        loadIdentifier = UUID()
        pause()
        player.replaceCurrentItem(with: nil)
        removeTimeObserverIfNeeded()
        pendingSeeks = 0
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        releaseSecurityScope()
        updateCurrentTime(0)
        duration = 0
        hasVideo = false
        videoAspectRatio = nil
        hasMedia = false
        mediaURL = nil
        mediaName = nil
        playbackRate = 1.0
        player.defaultRate = 1.0
    }

    func updateCurrentTime(_ seconds: TimeInterval) {
        let normalized = max(0, seconds)
        guard abs(currentTime - normalized) > 0.001 else { return }
        currentTime = normalized
    }

    private func releaseSecurityScope() {
        securityScopedMediaURL?.stopAccessingSecurityScopedResource()
        securityScopedMediaURL = nil
    }
}

private enum PlayerError: LocalizedError {
    case mediaNotPlayable

    var errorDescription: String? {
        switch self {
        case .mediaNotPlayable:
            return "Il file selezionato non può essere riprodotto."
        }
    }
}
