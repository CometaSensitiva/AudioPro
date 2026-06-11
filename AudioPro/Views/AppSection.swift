import SwiftUI

/// Sezioni dell'app unificata (pattern NavigationOptions di Landmarks).
enum AppSection: String, CaseIterable, Identifiable {
    case merger
    case player

    var id: String { rawValue }

    var name: String {
        switch self {
        case .merger: "Esportazione"
        case .player: "Trascrizione"
        }
    }

    var symbolName: String {
        switch self {
        case .merger: "waveform.badge.plus"
        case .player: "captions.bubble"
        }
    }
}
