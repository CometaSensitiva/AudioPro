import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DetailView: View {
    @EnvironmentObject private var appState: AudioAppState
    
    var body: some View {
        ZStack {
            WaveformBackdrop()
                .ignoresSafeArea(.container, edges: [.top, .leading, .bottom, .trailing])
            
            VStack(spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if appState.audioFiles.isEmpty == false {
                            FileInfoBlock(preview: appState.exportPreview)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    Color.clear
                                        .liquidGlassSurface(shape: .fixed(LiquidGlassDesign.cornerRadius))
                                }
                        } else {
                            Text("Seleziona o aggiungi un file per iniziare.")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background {
                                    Color.clear
                                        .liquidGlassSurface(shape: .fixed(LiquidGlassDesign.cornerRadius))
                                }
                        }
                    }
                    .padding()
                }
                
                StatusBar(state: appState.processingState) {
                    appState.cancelExport()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background {
                    Color.clear
                        .liquidGlassSurface(shape: .fixed(LiquidGlassDesign.cornerRadius))
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("")
        .toolbar(removing: .title)
        .inspector(isPresented: $appState.isInspectorPresented) {
            CompressionInspectorView()
                .inspectorColumnWidth(min: 320, ideal: 360, max: 420)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                addButton
                exportButton
                voiceMemosButton
                clearButton
            }

            ToolbarItem(placement: .primaryAction) {
                inspectorToggleButton
            }
        }
    }
    
    private var addButton: some View {
        Button {
            addFiles()
        } label: {
            Label("Aggiungi file", systemImage: "square.and.arrow.down.on.square")
        }
        .labelStyle(.iconOnly)
        .help("Aggiungi file")
    }

    private var exportButton: some View {
        Button {
            startExportFlow()
        } label: {
            Label("Esporta", systemImage: "square.and.arrow.up")
        }
        .labelStyle(.iconOnly)
        .help(appState.exportDisabledReason ?? "Esporta")
        .disabled(appState.isExportActionEnabled == false)
    }

    private var voiceMemosButton: some View {
        Button {
            openVoiceMemosLibrary()
        } label: {
            Label("Voice Memos", systemImage: "mic.fill")
        }
        .labelStyle(.iconOnly)
        .help("Apri Voice Memos")
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            appState.clearAll()
        } label: {
            Label("Svuota elenco", systemImage: "trash")
        }
        .labelStyle(.iconOnly)
        .help("Svuota elenco")
        .disabled(appState.audioFiles.isEmpty)
    }

    private var inspectorToggleButton: some View {
        Button {
            appState.isInspectorPresented.toggle()
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        .help(appState.isInspectorPresented ? "Nascondi inspector" : "Mostra inspector")
    }
    
    private func startExportFlow() {
        guard appState.isExportActionEnabled else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.mpeg4Audio, UTType.mpeg4Movie]
        panel.nameFieldStringValue = "Export.m4a"
        panel.message = "Salva come M4A (audio) o MP4"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                appState.startExport(to: url)
            }
        }
    }
    
    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        panel.begin { response in
            if response == .OK {
                let newFiles = panel.urls.map { url in
                    let securityScopedURL = url.startAccessingSecurityScopedResource() ? url : nil
                    return AudioFile(url: url, securityScopedURL: securityScopedURL)
                }
                appState.addFiles(newFiles)
            }
        }
    }
    
    private func openVoiceMemosLibrary() {
        let url = URL(fileURLWithPath: "/System/Applications/VoiceMemos.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }
}

struct DetailView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        DetailView()
            .environmentObject(PreviewSamples.appState())
    }
}
