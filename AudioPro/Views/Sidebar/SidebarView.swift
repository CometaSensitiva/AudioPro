import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var appState: AudioAppState
    @State private var draggingFileID: UUID?
    @State private var activeDropTargetID: UUID?
    @State private var isDropAtEndActive = false
    
    private let dropTypes: [UTType] = [.audio, .movie, .fileURL]
    private let internalDragTypes: [UTType] = [.plainText, .text]

    private struct AccessibleFile {
        let url: URL
        let securityScopedURL: URL?
    }
    
    var body: some View {
        ZStack {
            SidebarBackdrop()
            List {
                ForEach(appState.filteredFiles, id: \.id, content: row)
                    .onMove { offsets, destination in
                        guard appState.searchText.isEmpty else { return }
                        withAnimation {
                            appState.moveFiles(from: offsets, to: destination)
                        }
                    }
                    .onDelete(perform: appState.remove(atOffsets:))
            }
            .onDrop(
                of: internalDragTypes,
                delegate: ListEndDropDelegate(
                    files: appState.audioFiles,
                    isEnabled: appState.searchText.isEmpty,
                    draggingFileID: $draggingFileID,
                    activeDropTargetID: $activeDropTargetID,
                    isDropAtEndActive: $isDropAtEndActive,
                    moveFile: { from, destination in
                        withAnimation {
                            appState.moveFiles(from: IndexSet(integer: from), to: destination)
                        }
                    }
                )
            )
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onDeleteCommand {
                if let selected = appState.selectedFile {
                    appState.remove(selected)
                }
            }
        }
        .navigationTitle("File")
        // Drop esterno gestito a livello di container per non interferire con il reordering interno
        .onDrop(of: dropTypes, isTargeted: nil, perform: handleExternalDrop(providers:))
    }
    
    @ViewBuilder
    private func row(for file: AudioFile) -> some View {
        let isSelected = appState.selectedFile?.id == file.id
        AudioFileRowView(
            file: file,
            isSelected: isSelected
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedFile = file
        }
        .onDrag {
            draggingFileID = file.id
            activeDropTargetID = nil
            isDropAtEndActive = false
            return NSItemProvider(object: file.id.uuidString as NSString)
        }
        .onDrop(
            of: internalDragTypes,
            delegate: FileReorderDropDelegate(
                targetFileID: file.id,
                files: appState.audioFiles,
                isEnabled: appState.searchText.isEmpty,
                draggingFileID: $draggingFileID,
                activeDropTargetID: $activeDropTargetID,
                isDropAtEndActive: $isDropAtEndActive,
                moveFile: { from, destination in
                    withAnimation {
                        appState.moveFiles(from: IndexSet(integer: from), to: destination)
                    }
                }
            )
        )
        .contextMenu {
            Button("Elimina", role: .destructive) {
                appState.remove(file)
            }
        }
    }
    
    private func handleExternalDrop(providers: [NSItemProvider]) -> Bool {
        // Non intercettare i drag interni (riordino) che usano provider di tipo testo
        if providers.contains(where: { provider in
            internalDragTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }) {
            return false
        }
        
        let acceptedProviders = providers.filter { provider in
            dropTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
        guard acceptedProviders.isEmpty == false else { return false }
        
        Task {
            var files: [AudioFile] = []
            for provider in acceptedProviders {
                if let url = await loadFileURL(from: provider),
                   let accessibleFile = makeAccessibleFile(from: url) {
                    files.append(AudioFile(url: accessibleFile.url, securityScopedURL: accessibleFile.securityScopedURL))
                }
            }
            
            guard files.isEmpty == false else { return }
            await MainActor.run {
                appState.addFiles(files)
            }
        }
        
        return true
    }
    
    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        let preferredTypes = dropTypes.map(\.identifier)
        
        // Prova in-place per il primo tipo supportato
        if let typeIdentifier = preferredTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
            if let url = await loadInPlaceURL(provider: provider, typeIdentifier: typeIdentifier) {
                return url
            }
        }
        
        // Fallback: prova a caricare l'URL come oggetto
        if provider.canLoadObject(ofClass: URL.self) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
        }
        
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data {
                    // Se i provider espongono bookmark data, tenta la risoluzione
                    var isStale = false
                    if let url = try? URL(
                        resolvingBookmarkData: data,
                        options: [.withoutUI, .withoutMounting],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    ) {
                        continuation.resume(returning: url)
                    } else {
                        let url = URL(dataRepresentation: data, relativeTo: nil)
                        continuation.resume(returning: url)
                    }
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func loadInPlaceURL(provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _, _ in
                continuation.resume(returning: url)
            }
        }
    }
    
    private func makeAccessibleFile(from url: URL) -> AccessibleFile? {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()

        guard FileManager.default.fileExists(atPath: url.path), isSupportedMediaFile(url) else {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
            return nil
        }

        return AccessibleFile(
            url: url,
            securityScopedURL: hasSecurityScope ? url : nil
        )
    }
    
    private func isSupportedMediaFile(_ url: URL) -> Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey])
        if let type = resourceValues?.contentType {
            return type.conforms(to: .audio) || type.conforms(to: .movie)
        }
        
        if let fallbackType = UTType(filenameExtension: url.pathExtension) {
            return fallbackType.conforms(to: .audio) || fallbackType.conforms(to: .movie)
        }
        
        return false
    }
}

private struct FileReorderDropDelegate: DropDelegate {
    let targetFileID: UUID
    let files: [AudioFile]
    let isEnabled: Bool
    @Binding var draggingFileID: UUID?
    @Binding var activeDropTargetID: UUID?
    @Binding var isDropAtEndActive: Bool
    let moveFile: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled && draggingFileID != nil
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
        guard let draggingFileID, draggingFileID != targetFileID else { return }
        guard activeDropTargetID != targetFileID else { return }
        guard
            let from = files.firstIndex(where: { $0.id == draggingFileID }),
            let to = files.firstIndex(where: { $0.id == targetFileID }),
            from != to
        else { return }

        isDropAtEndActive = false
        activeDropTargetID = targetFileID
        moveFile(from, to > from ? to + 1 : to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        activeDropTargetID = nil
        draggingFileID = nil
        isDropAtEndActive = false
        return isEnabled
    }
}

private struct ListEndDropDelegate: DropDelegate {
    let files: [AudioFile]
    let isEnabled: Bool
    @Binding var draggingFileID: UUID?
    @Binding var activeDropTargetID: UUID?
    @Binding var isDropAtEndActive: Bool
    let moveFile: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled && draggingFileID != nil
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
        guard let draggingFileID else { return }
        guard let from = files.firstIndex(where: { $0.id == draggingFileID }) else { return }
        guard from != files.count - 1 else { return }
        guard isDropAtEndActive == false else { return }

        activeDropTargetID = nil
        isDropAtEndActive = true
        moveFile(from, files.count)
    }

    func dropExited(info: DropInfo) {
        isDropAtEndActive = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        activeDropTargetID = nil
        draggingFileID = nil
        isDropAtEndActive = false
        return isEnabled
    }
}

private struct SidebarBackdrop: View {
    var body: some View {
        LinearGradient(colors: [
            Color.blue.opacity(0.18),
            Color.purple.opacity(0.14)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
        .overlay {
            RadialGradient(colors: [
                Color.white.opacity(0.12),
                Color.clear
            ], center: .topLeading, startRadius: 40, endRadius: 360)
            .offset(x: -40, y: -80)
        }
        .ignoresSafeArea(.container, edges: [.top, .leading, .bottom])
    }
}

// MARK: - Previews

struct SidebarView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            SidebarView()
                .environmentObject(AudioAppState())

            SidebarView()
                .environmentObject(singleFileState)

            SidebarView()
                .environmentObject(PreviewSamples.appState())
        }
    }

    @MainActor
    private static var singleFileState: AudioAppState {
        let state = AudioAppState()
        state.addFiles([PreviewSamples.mockFile(name: "recording.m4a")])
        return state
    }
}
