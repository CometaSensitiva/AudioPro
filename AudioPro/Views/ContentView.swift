import SwiftUI

/// Vista principale: split view con sidebar dei file e area dettaglio stile LandmarkDetail.
struct ContentView: View {
    @StateObject private var appState = AudioAppState()
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .environmentObject(appState)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
