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
                .disabled(appState.processingState.isBusy)
            if summaryHasContent {
                summarySection
            }
            if notificationNeedsAttention {
                notificationSection
            }
            primarySection
                .disabled(appState.processingState.isBusy)
            advancedSection
                .disabled(appState.processingState.isBusy)

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
                            guard appState.canModifyQueue else { return }
                            appState.compression = CompressionSettings.medium
                                .preservingExportMode(appState.compression.exportMode)
                            syncMaxSizeInput()
                        } label: {
                            Label("Ripristina valori predefiniti", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.processingState.isBusy)
                    }
                    Spacer()
                }
            }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncMaxSizeInput()
            appState.refreshNotificationPermission()
        }
        .onChange(of: appState.compression.maxOutputSizeMB) { _, _ in
            syncMaxSizeInput()
        }
    }

    @ViewBuilder
    private var outputModeSection: some View {
        if preview.isVideoCompressionEligible {
            Section("Risultato") {
                tracked(.exportMode) {
                    Picker("Modalità", selection: binding(\.exportMode)) {
                        ForEach(ExportMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if preview.isVideoModeActive {
                    noticePanel(
                        icon: "video.badge.waveform",
                        title: "Profilo video fisso",
                        message: VideoCompressionPreset.teamsLecture.inspectorMessage
                    )
                } else {
                    noticePanel(
                        icon: "waveform",
                        title: "Solo audio",
                        message: "Il video viene usato come sorgente, ma il risultato finale contiene solo l’audio."
                    )
                }
            }
        }
    }

    private var summarySection: some View {
        // Profilo e bitrate sono già nella barra inferiore ("AAC · 96 kbps"):
        // qui restano solo limite di dimensione e avvisi di validazione.
        Section {
            if let targetLabel = preview.targetSizeLabel {
                LabeledContent("Dimensione massima") {
                    Text(targetLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
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
        } header: {
            Text("Riepilogo")
        }
    }

    @ViewBuilder
    private var notificationSection: some View {
        Section("Notifiche") {
            switch appState.notificationPermissionState {
            case .unknown:
                notificationRow(
                    icon: "bell",
                    title: "Verifica notifiche",
                    message: "AudioPro controllerà se può avvisarti a esportazione completata."
                )
                Button {
                    appState.refreshNotificationPermission()
                } label: {
                    Label("Verifica", systemImage: "arrow.clockwise")
                }
            case .notDetermined:
                notificationRow(
                    icon: "bell.badge",
                    title: "Autorizzazione necessaria",
                    message: "Consenti ad AudioPro di mostrarti una notifica quando l’esportazione finisce."
                )
                Button {
                    appState.requestNotificationPermission()
                } label: {
                    Label("Consenti notifiche", systemImage: "checkmark.circle")
                }
            case .authorized:
                notificationRow(
                    icon: "bell.fill",
                    title: "Notifiche attive",
                    message: "AudioPro può avvisarti a esportazione completata."
                )
            case .denied:
                notificationRow(
                    icon: "bell.slash",
                    title: "Notifiche disattivate",
                    message: "macOS non mostrerà altre richieste automatiche. Riattivale da Impostazioni di Sistema."
                )
                Button {
                    appState.openNotificationSettings()
                } label: {
                    Label("Apri Impostazioni di Sistema", systemImage: "gearshape")
                }
            case .unavailable(let message):
                notificationRow(
                    icon: "exclamationmark.triangle",
                    title: "Notifiche non disponibili",
                    message: message
                )
                Button {
                    appState.refreshNotificationPermission()
                } label: {
                    Label("Riprova", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var primarySection: some View {
        Section {
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
                        title: "Copia diretta attiva",
                        message: preview.usesMergeReencodeFallback
                            ? "Con più file la copia diretta non è disponibile. AudioPro userà AAC per unire i contenuti."
                            : "L’audio viene estratto senza ricodifica. Profilo e dimensione massima non vengono applicati."
                    )
                }
            } else {
                tracked(.preset) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Profilo")

                        Picker("Profilo", selection: binding(\.preset)) {
                            ForEach(Preset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(isTargetSizeActive)
                        .opacity(isTargetSizeActive ? 0.55 : 1)

                        if isTargetSizeActive {
                            Text("Profilo bloccato: il limite scelto per la dimensione massima determina il bitrate finale.")
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
                            TextField("Dimensione massima", text: $maxSizeInput, prompt: Text("Nessuna"))
                                .labelsHidden()
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
                                .buttonStyle(.bordered)
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
        } header: {
            Text("Impostazioni rapide")
        } footer: {
            // In Solo audio la didascalia della dimensione massima basta;
            // la nota serve solo quando il profilo video blocca i controlli.
            if let summaryFooterText {
                Text(summaryFooterText)
            }
        }
    }

    private var advancedSection: some View {
        Section("Impostazioni avanzate") {
            if preview.isVideoModeActive {
                noticePanel(
                    icon: "lock.rectangle.stack",
                    title: "Controlli tecnici non disponibili",
                    message: "In Video compresso usiamo un profilo fisso. Codec audio, qualità, frequenza di campionamento e dimensione massima restano memorizzati per quando torni a Solo audio."
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
                                Text("Con la copia diretta il codec originale viene mantenuto e le altre regolazioni non intervengono.")
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
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)

                                    if appState.compression.maxOutputSizeMB != nil {
                                        Text("Con una dimensione massima impostata, il bitrate viene adattato automaticamente e questo cursore resta disattivato.")
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
                                    title: "Frequenza di campionamento",
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
                            Label("Codec e qualità", systemImage: "slider.horizontal.3")
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
            return "Profilo video fisso"
        }
        if preview.effectiveCodec == .copy {
            return "Copia diretta"
        }
        return "\(preview.effectiveCodec.rawValue) · \(appState.compression.sampleRate.rawValue)"
    }

    private var summaryHasContent: Bool {
        if preview.targetSizeLabel != nil { return true }
        switch preview.validation {
        case .loadingMetadata, .failedPreflight: return true
        default: return false
        }
    }

    /// Le notifiche compaiono solo quando serve un'azione: se sono già
    /// attive non c'è niente da decidere.
    private var notificationNeedsAttention: Bool {
        if case .authorized = appState.notificationPermissionState { return false }
        return true
    }

    private var summaryFooterText: String? {
        guard preview.isVideoModeActive else { return nil }
        return "La modalità video usa un profilo fisso. Per tornare a codec, qualità, frequenza di campionamento o dimensione massima seleziona Solo audio."
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
            return "Dimensione massima: circa \(target.formatted(.number.precision(.fractionLength(0)))) MB. Bitrate stimato \(bitrate)."
        }

        return "Lascia vuoto per usare profilo e qualità. Se inserisci un limite in MB, premi Applica: la dimensione massima prevale sulla qualità e blocca il profilo."
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
        FeatureNotice(systemImage: icon, title: title, message: message)
    }

    private func notificationRow(icon: String, title: String, message: String) -> some View {
        noticePanel(icon: icon, title: title, message: message)
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
            return "Applica la dimensione massima."
        case .advanced:
            return "Mostra i controlli tecnici di compressione."
        case .codec:
            return "Formato di codifica dell’audio esportato."
        case .quality:
            return "Regola il bitrate quando non è attiva una dimensione massima."
        case .sampleRate:
            return "Frequenza di campionamento dell’esportazione."
        case .copyMode:
            return "Nessuna ricodifica: copia la traccia audio originale."
        case .reset:
            return "Ripristina i valori predefiniti."
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
        guard appState.canModifyQueue else {
            syncMaxSizeInput()
            return
        }
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
                    guard appState.canModifyQueue else { return }
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
