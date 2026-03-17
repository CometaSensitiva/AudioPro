import SwiftUI
import Foundation
enum PreviewSamples {
    @MainActor
    static func appState() -> AudioAppState {
        let state = AudioAppState()
        let urls = [
            URL(fileURLWithPath: "/tmp/demo1.m4a"),
            URL(fileURLWithPath: "/tmp/demo2.wav"),
            URL(fileURLWithPath: "/tmp/demo3.aiff")
        ]
        let files = urls.map { AudioFile(url: $0, loadMetadata: false) }
        
        // Mock metadata per la preview
        if files.indices.contains(0) {
            files[0].duration = 192
            files[0].fileSize = 4_200_000
            files[0].codec = "aac "
        }
        if files.indices.contains(1) {
            files[1].duration = 65
            files[1].fileSize = 12_000_000
            files[1].codec = "lpcm"
        }
        if files.indices.contains(2) {
            files[2].duration = 48
            files[2].fileSize = 8_100_000
            files[2].codec = "aiff"
        }
        
        state.addFiles(files)
        state.selectedFile = files.first
        return state
    }
    
    /// Crea un singolo AudioFile mock con metadata personalizzati
    @MainActor
    static func mockFile(
        name: String = "demo.m4a",
        duration: TimeInterval = 120,
        size: Int64 = 5_000_000,
        codec: String = "aac "
    ) -> AudioFile {
        let file = AudioFile(url: URL(fileURLWithPath: "/tmp/\(name)"), loadMetadata: false)
        file.duration = duration
        file.fileSize = size
        file.codec = codec
        return file
    }
    
    /// Crea un array di AudioFile mock per testing
    @MainActor
    static func mockFiles(count: Int = 3) -> [AudioFile] {
        let configs: [(String, TimeInterval, Int64, String)] = [
            ("recording_001.m4a", 192, 4_200_000, "aac "),
            ("interview.wav", 65, 12_000_000, "lpcm"),
            ("podcast_episode.aiff", 480, 18_100_000, "aiff"),
            ("voice_memo.mp3", 45, 2_800_000, "mp3 "),
            ("music_track.m4a", 240, 8_500_000, "aac ")
        ]
        
        return (0..<min(count, configs.count)).map { index in
            let (name, duration, size, codec) = configs[index]
            return mockFile(name: name, duration: duration, size: size, codec: codec)
        }
    }
}
