import SwiftUI

/// Vista principale: split view con Esportazione, Trascrizione e Riproduzione.
struct ContentView: View {
    @ObservedObject private var session: AppSession
    @ObservedObject private var appState: AudioAppState
    @ObservedObject private var transcriptionModel: TranscriptionModel
    @StateObject private var playbackCommandBridge: PlaybackCommandBridge
    @State private var isTranscriptionInspectorPresented = false

    init(session: AppSession) {
        self._session = ObservedObject(wrappedValue: session)
        self._appState = ObservedObject(wrappedValue: session.appState)
        self._transcriptionModel = ObservedObject(wrappedValue: session.transcriptionModel)
        self._playbackCommandBridge = StateObject(
            wrappedValue: PlaybackCommandBridge(
                playerController: session.playerModel.playerController
            )
        )
    }

    var body: some View {
        navigation
            .environmentObject(appState)
            .environmentObject(playbackCommandBridge)
            .frame(minWidth: minimumContentWidth, minHeight: 540)
    }

    private var navigation: some View {
        NavigationSplitView {
            SidebarView(
                section: $session.section,
                transcriptionModel: transcriptionModel
            )
        } detail: {
            switch session.section {
            case .merger:
                MergerDetailView(
                    canTranscribeOutput: session.canTranscribeExportedFile,
                    onTranscribeOutput: { url in
                        _ = session.transcribeExportedFile(url)
                    }
                )
            case .transcription:
                TranscriptionView(
                    model: transcriptionModel,
                    onOpenInPlayback: session.openInPlayback,
                    isInspectorPresented: $isTranscriptionInspectorPresented
                )
            case .player:
                PlayerView(model: session.playerModel)
            }
        }
    }

    /// Con un inspector aperto preserva sidebar, contenuto e impostazioni senza
    /// comprimere il dettaglio. Lo stato Trascrizione resta locale a questa
    /// shell perché serve sia alla vista figlia sia al vincolo della finestra.
    private var minimumContentWidth: CGFloat {
        let isCurrentInspectorPresented = switch session.section {
        case .merger:
            appState.isInspectorPresented
        case .transcription:
            isTranscriptionInspectorPresented
        case .player:
            false
        }

        return isCurrentInspectorPresented ? 1_000 : 760
    }
}

struct ContentView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        ContentView(session: AppSession())
    }
}
