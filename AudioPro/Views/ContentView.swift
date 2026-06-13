import SwiftUI

/// Vista principale: split view con Esportazione, Trascrizione e Riproduzione.
struct ContentView: View {
    @ObservedObject private var session: AppSession
    @ObservedObject private var appState: AudioAppState

    init(session: AppSession) {
        self._session = ObservedObject(wrappedValue: session)
        self._appState = ObservedObject(wrappedValue: session.appState)
    }

    var body: some View {
        navigation
            .exportQueueSearchable(
                isActive: session.section == .merger,
                text: $appState.searchText
            )
            .environmentObject(appState)
    }

    private var navigation: some View {
        NavigationSplitView {
            SidebarView(
                section: $session.section,
                transcriptionModel: session.transcriptionModel
            )
        } detail: {
            switch session.section {
            case .merger:
                MergerDetailView(onTranscribeOutput: session.transcribeExportedFile)
            case .transcription:
                TranscriptionView(
                    model: session.transcriptionModel,
                    onOpenInPlayback: session.openInPlayback
                )
            case .player:
                PlayerView(model: session.playerModel)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        ContentView(session: AppSession())
    }
}

private extension View {
    @ViewBuilder
    func exportQueueSearchable(isActive: Bool, text: Binding<String>) -> some View {
        if isActive {
            searchable(text: text, placement: .sidebar, prompt: "Cerca nella coda file")
        } else {
            self
        }
    }
}
