import SwiftUI
import AppKit

struct CompressionInspectorView: View {
    @EnvironmentObject private var appState: AudioAppState
    @State private var isAdvancedExpanded = false
    @State private var maxSizeInput = ""
    @FocusState private var isMaxSizeFieldFocused: Bool

    private var preview: ExportPreview {
        appState.exportPreview
    }

    private enum InspectorField {
        case exportMode
        case preset
        case maxSize
        case applyTarget
        case advanced
        case codec
        case quality
        case sampleRate
        case copyMode
        case reset
    }

    var body: some View {
        Form {
            outputModeSection
            summarySection
            primarySection
            advancedSection

            if let videoCapabilityNoticeMessage {
                Section {
                    noticePanel(
                        icon: "film.stack",
                        title: "Video compresso non disponibile",
                        message: videoCapabilityNoticeMessage
                    )
                }
            }

            Section {
                HStack {
                    Spacer()
                    tracked(.reset) {
                        Button {
                            appState.compression = CompressionSettings.medium
                                .preservingExportMode(appState.compression.exportMode)
                            syncMaxSizeInput()
                        } label: {
                            Label("Ripristina standard", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                }
            }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .simultaneousGesture(TapGesture().onEnded {
            dismissMaxSizeFieldFocus()
        })
        .onAppear {
            syncMaxSizeInput()
        }
        .onChange(of: appState.compression.maxOutputSizeMB) { _, _ in
            syncMaxSizeInput()
        }
    }

    @ViewBuilder
    private var outputModeSection: some View {
        if preview.isVideoCompressionEligible {
            Section("Output") {
                tracked(.exportMode) {
                    Picker("Output", selection: binding(\.exportMode)) {
                        ForEach(ExportMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if preview.isVideoModeActive {
                    noticePanel(
                        icon: "video.badge.waveform",
                        title: "Preset video fisso",
                        message: VideoCompressionPreset.teamsLecture.inspectorMessage
                    )
                } else {
                    noticePanel(
                        icon: "waveform",
                        title: "Solo audio",
                        message: "Il video viene usato come sorgente, ma l'export finale resta audio-only."
                    )
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Profilo attivo") {
                Text(activeCompressionModeLabel)
                    .foregroundStyle(.secondary)
            }

            if let targetLabel = preview.targetSizeLabel {
                LabeledContent("Target") {
                    Text(targetLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            LabeledContent(summarySecondaryLabel) {
                Text(activeBitrateSummary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if case .loadingMetadata(let message) = preview.validation {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .failedPreflight(let message) = preview.validation {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            Text(summaryFooterText)
        }
    }

    private var primarySection: some View {
        Section("Rapido") {
            if preview.isVideoModeActive {
                noticePanel(
                    icon: "video.fill",
                    title: "Video compresso attivo",
                    message: VideoCompressionPreset.teamsLecture.inspectorMessage
                )
            } else if appState.compression.codec == .copy {
                tracked(.copyMode) {
                    noticePanel(
                        icon: "bolt.horizontal.circle",
                        title: "Copia Stream attiva",
                        message: preview.usesMergeReencodeFallback
                            ? "Con piu file Copia Stream non e disponibile. AudioPro usera AAC per concatenare i contenuti."
                            : "L'audio viene estratto senza ricodifica. Preset e dimensione massima non vengono applicati."
                    )
                }
            } else {
                tracked(.preset) {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Preset") {
                            Text(appState.compression.preset.rawValue)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Picker("Preset", selection: binding(\.preset)) {
                            ForEach(Preset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .disabled(isTargetSizeActive)
                        .opacity(isTargetSizeActive ? 0.55 : 1)

                        if isTargetSizeActive {
                            Text("Preset bloccato: con un target in MB è la dimensione massima a guidare il bitrate finale.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                }

                tracked(.maxSize) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dimensione massima")

                        HStack(spacing: 8) {
                            TextField("", text: $maxSizeInput)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1)
                                .focused($isMaxSizeFieldFocused)
                                .frame(width: 96)
                                .onSubmit {
                                    commitMaxSizeInput()
                                    dismissMaxSizeFieldFocus()
                                }

                            Text("MB")
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            tracked(.applyTarget) {
                                Button("Applica") {
                                    commitMaxSizeInput()
                                    dismissMaxSizeFieldFocus()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(canApplyMaxSizeChange == false)
                            }

                            if appState.compression.maxOutputSizeMB != nil || maxSizeInput.isEmpty == false {
                                Button("Cancella") {
                                    maxSizeInput = ""
                                    commitMaxSizeInput()
                                    dismissMaxSizeFieldFocus()
                                }
                                .buttonStyle(.link)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(maxSizeCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var advancedSection: some View {
        Section("Tecnico") {
            if preview.isVideoModeActive {
                noticePanel(
                    icon: "lock.rectangle.stack",
                    title: "Controlli tecnici sospesi",
                    message: "In Video compresso usiamo un preset fisso. Codec audio, qualità fine, sample rate e target MB restano memorizzati per quando torni a Solo audio."
                )
            } else {
                DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        tracked(.codec) {
                            compactPickerRow(
                                title: "Codec",
                                selection: binding(\.codec),
                                values: Codec.allCases
                            )
                        }

                        if appState.compression.codec == .copy {
                            tracked(.copyMode) {
                                Text("In Copia Stream il codec originale viene mantenuto e le altre regolazioni non intervengono.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Divider()

                            tracked(.quality) {
                                VStack(alignment: .leading, spacing: 10) {
                                    LabeledContent("Qualità") {
                                        Text(preview.bitrateLabel)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }

                                    Slider(value: binding(\.quality), in: 0...1)
                                        .disabled(appState.compression.maxOutputSizeMB != nil)

                                    HStack {
                                        Text("Più leggero")
                                        Spacer()
                                        Text("Più fedele")
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                    if appState.compression.maxOutputSizeMB != nil {
                                        Text("Con una dimensione massima impostata, il bitrate viene adattato automaticamente e questo cursore resta in standby.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .opacity(appState.compression.maxOutputSizeMB != nil ? 0.65 : 1)
                            }

                            Divider()

                            tracked(.sampleRate) {
                                compactPickerRow(
                                    title: "Sample rate",
                                    selection: binding(\.sampleRate),
                                    values: SampleRate.allCases
                                )
                            }
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    tracked(.advanced) {
                        HStack(spacing: 10) {
                            Label("Avanzate", systemImage: "slider.horizontal.3")
                                .labelStyle(.titleAndIcon)
                            Spacer()
                            Text(advancedSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.primary)
            }
        }
    }

    private var advancedSummary: String {
        if preview.isVideoModeActive {
            return "Preset video fisso"
        }
        if preview.effectiveCodec == .copy {
            return "Copia Stream"
        }
        return "\(preview.effectiveCodec.rawValue) • \(appState.compression.sampleRate.rawValue)"
    }

    private var activeCompressionModeLabel: String {
        if preview.isVideoModeActive {
            return "Video compresso"
        }
        if preview.usesMergeReencodeFallback {
            return "Merge ricodificato"
        }
        if preview.effectiveCodec == .copy {
            return "Copia Stream"
        }
        if isTargetSizeActive {
            return "Target dimensione"
        }
        return "Preset \(appState.compression.preset.rawValue)"
    }

    private var activeBitrateSummary: String {
        if preview.isVideoModeActive {
            return VideoCompressionPreset.teamsLecture.summary
        }
        return preview.bitrateLabel
    }

    private var summarySecondaryLabel: String {
        preview.isVideoModeActive ? "Preset video" : "Bitrate stimato"
    }

    private var summaryFooterText: String {
        if preview.isVideoModeActive {
            return "La modalità video usa un preset fisso. Per tornare a codec, qualità fine, sample rate o target MB seleziona Solo audio."
        }
        return "Regola il risultato in modo rapido con preset e target; apri Avanzate solo se vuoi intervenire su codec, qualità fine o sample rate."
    }

    private var maxSizeCaption: String {
        if maxSizeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           parsedDraftMaxSizeMB == nil {
            return "Inserisci un numero valido maggiore di zero, poi premi Applica."
        }

        if case .loadingMetadata(let message) = preview.validation,
           appState.compression.maxOutputSizeMB != nil {
            return message
        }

        if case .failedPreflight(let message) = preview.validation,
           appState.compression.maxOutputSizeMB != nil {
            return message
        }

        if let target = preview.targetSizeMB {
            let bitrate = preview.bitrateLabel
            return "Target attivo: circa \(target.formatted(.number.precision(.fractionLength(0)))) MB. Bitrate stimato \(bitrate)."
        }

        return "Lascia vuoto per usare preset e qualità. Se inserisci un target in MB, premi Applica: il target prevale sulla qualità fine e blocca il preset."
    }

    private var isTargetSizeActive: Bool {
        appState.compression.maxOutputSizeMB != nil
    }

    private var parsedDraftMaxSizeMB: Double? {
        let trimmed = maxSizeInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard trimmed.isEmpty == false else { return nil }
        guard let parsedValue = Double(trimmed), parsedValue > 0 else { return nil }
        return min(parsedValue, 10_000)
    }

    private var canApplyMaxSizeChange: Bool {
        let trimmed = maxSizeInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return appState.compression.maxOutputSizeMB != nil
        }

        guard let parsedDraftMaxSizeMB else { return false }
        return appState.compression.maxOutputSizeMB != parsedDraftMaxSizeMB
    }

    private var videoCapabilityNoticeMessage: String? {
        preview.videoModeAvailabilityMessage
    }

    private func compactPickerRow<Value: Hashable & Identifiable & RawRepresentable>(
        title: String,
        selection: Binding<Value>,
        values: [Value]
    ) -> some View where Value.RawValue == String {
        LabeledContent(title) {
            Picker("", selection: selection) {
                ForEach(values) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 132)
        }
    }

    private func noticePanel(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tracked<Content: View>(_ field: InspectorField, @ViewBuilder content: () -> Content) -> some View {
        content()
            .contentShape(Rectangle())
            .help(tooltip(for: field))
    }

    private func tooltip(for field: InspectorField) -> String {
        switch field {
        case .preset:
            return "Profilo rapido di compressione."
        case .exportMode:
            return "Scegli se esportare solo audio oppure mantenere e comprimere il video."
        case .maxSize:
            return "Limite opzionale della dimensione finale in MB."
        case .applyTarget:
            return "Applica il target di dimensione massima."
        case .advanced:
            return "Mostra i controlli tecnici di compressione."
        case .codec:
            return "Formato di codifica dell'audio esportato."
        case .quality:
            return "Regola il bitrate fine quando non è attivo un target in MB."
        case .sampleRate:
            return "Frequenza di campionamento dell'export."
        case .copyMode:
            return "Nessuna ricodifica: copia la traccia audio originale."
        case .reset:
            return "Ripristina i valori di default."
        }
    }

    private func syncMaxSizeInput() {
        if let value = appState.compression.maxOutputSizeMB {
            maxSizeInput = String(Int(value.rounded()))
        } else {
            maxSizeInput = ""
        }
    }

    private func commitMaxSizeInput() {
        let trimmed = maxSizeInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            Task { @MainActor in
                appState.compression.maxOutputSizeMB = nil
            }
            maxSizeInput = ""
            return
        }

        guard let parsedDraftMaxSizeMB else { return }

        Task { @MainActor in
            appState.compression.maxOutputSizeMB = parsedDraftMaxSizeMB
        }

        maxSizeInput = String(Int(parsedDraftMaxSizeMB.rounded()))
    }

    private func dismissMaxSizeFieldFocus() {
        isMaxSizeFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CompressionSettings, Value>) -> Binding<Value> {
        Binding(
            get: { appState.compression[keyPath: keyPath] },
            set: { newValue in
                Task { @MainActor in
                    appState.compression[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

struct CompressionInspectorView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        CompressionInspectorView()
            .environmentObject(PreviewSamples.appState())
    }
}
