import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MergerDetailView: View {
    @EnvironmentObject private var appState: AudioAppState
    let onTranscribeOutput: (URL) -> Void
    
    var body: some View {
        ZStack {
            ZStack {
                AmbientBackdrop()
                ReactiveWaveform(isActive: appState.processingState.isBusy)
            }
            .ignoresSafeArea(.container, edges: [.top, .leading, .bottom, .trailing])
            
            VStack(spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if appState.audioFiles.isEmpty == false {
                            FileInfoBlock(preview: appState.exportPreview)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    .regularMaterial,
                                    in: RoundedRectangle(cornerRadius: LiquidGlassDesign.cornerRadius, style: .continuous)
                                )
                        } else {
                            Text("Seleziona o aggiungi un file per iniziare.")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(
                                    .regularMaterial,
                                    in: RoundedRectangle(cornerRadius: LiquidGlassDesign.cornerRadius, style: .continuous)
                                )
                        }
                    }
                    .padding()
                }
                
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { exportStatusBar }
        .navigationTitle("")
        .detailWindowChrome()
        .inspector(isPresented: $appState.isInspectorPresented) {
            CompressionInspectorView()
                .inspectorColumnWidth(min: 320, ideal: 360, max: 420)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                addButton
                voiceMemosButton
            }

            ToolbarSpacer(.fixed, placement: .navigation)

            ToolbarItemGroup(placement: .navigation) {
                exportButton
            }

            ToolbarSpacer(.fixed, placement: .navigation)

            ToolbarItemGroup(placement: .navigation) {
                clearButton
            }

            ToolbarItem(placement: .primaryAction) {
                inspectorToggleButton
            }
        }
    }
    
    /// Unico elemento glass della sezione, speculare alla player bar:
    /// appare solo quando l'export è in corso o appena concluso.
    @ViewBuilder
    private var exportStatusBar: some View {
        if appState.processingState != .idle {
            StatusBar(
                state: appState.processingState,
                onCancel: appState.cancelExport,
                onTranscribeOutput: transcribeOutputAction
            )
            .padding(.horizontal, LiquidGlassDesign.padding)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, LiquidGlassDesign.padding)
            .padding(.bottom, LiquidGlassDesign.spacing)
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

    private var transcribeOutputAction: (() -> Void)? {
        guard let outputURL = appState.lastCompletedOutputURL else { return nil }
        return {
            onTranscribeOutput(outputURL)
        }
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
        let defaults = appState.exportDestinationDefaults
        let panel = NSSavePanel()
        panel.allowedContentTypes = defaults.allowedContentTypes
        panel.nameFieldStringValue = defaults.fileName
        panel.message = defaults.message
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

private extension View {
    func detailWindowChrome() -> some View {
        self.toolbar(removing: .title)
    }
}

struct MergerDetailView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        MergerDetailView(onTranscribeOutput: { _ in })
            .environmentObject(PreviewSamples.appState())
    }
}
