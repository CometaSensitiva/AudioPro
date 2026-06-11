import SwiftUI

/// Vista principale: split view con le sezioni dell'app in sidebar
/// (Esportazione, Trascrizione) e dettaglio per sezione, stile Landmarks.
struct ContentView: View {
    @StateObject private var appState = AudioAppState()
    @StateObject private var playerModel = PlayerModel()
    @State private var section: AppSection = .merger

    var body: some View {
        NavigationSplitView {
            SidebarView(section: $section)
        } detail: {
            switch section {
            case .merger:
                MergerDetailView()
            case .player:
                PlayerView(model: playerModel)
            }
        }
        // Placement .sidebar: la ricerca filtra la Coda file, che vive in
        // sidebar (caso documentato di SearchFieldPlacement.sidebar); così
        // l'inspector toggle resta l'unico elemento trailing della toolbar.
        .searchable(text: $appState.searchText, placement: .sidebar, prompt: "Cerca nella coda file")
        .environmentObject(appState)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
