import SwiftUI

/// Sezioni dell'app unificata (pattern NavigationOptions di Landmarks).
enum AppSection: String, CaseIterable, Identifiable {
    case merger
    case transcription
    case player

    var id: String { rawValue }

    var name: String {
        switch self {
        case .merger: "Esportazione"
        case .transcription: "Trascrizione"
        case .player: "Riproduzione"
        }
    }

    var symbolName: String {
        switch self {
        case .merger: "waveform.badge.plus"
        case .transcription: "waveform.and.mic"
        case .player: "play.rectangle"
        }
    }
}
