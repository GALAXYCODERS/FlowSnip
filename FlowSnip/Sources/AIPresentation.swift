import Cocoa
import SwiftUI

@MainActor
final class AIShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private let configuration: AIConfiguration
    private let onRecordingChanged: (Bool) -> Void

    init(configuration: AIConfiguration, onRecordingChanged: @escaping (Bool) -> Void) {
        self.configuration = configuration
        self.onRecordingChanged = onRecordingChanged
    }

    func start() {
        stop()
        configuration.shortcutError = nil
        isRecording = true
        onRecordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stop(); return nil }
            let chord = ShortcutChord(event: event)
            guard chord.isValid, chord != .screenshot else {
                self.configuration.shortcutError = "Use Command or Control, and choose a shortcut different from the screenshot shortcut."
                return nil
            }
            self.configuration.aiShortcut = chord
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            onRecordingChanged(false)
        }
    }
}

@MainActor
struct AssistantPanelView: View {
    @ObservedObject var coordinator: AIScanCoordinator
    let onSettings: () -> Void
    let onNewScan: () -> Void
    let onClose: () -> Void
    var opaquePreviewBackdrop = false
    @State private var selectedTab = 0
    @State private var prompt = ""
    @State private var showSource = false
    @FocusState private var promptFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            header.padding(16)
            Divider()
            Picker("Result", selection: $selectedTab) {
                Text("Answer").tag(0)
                Text("Extracted Text").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            if selectedTab == 0 { conversation } else { textResult }
            if let error = coordinator.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
            actions.padding(.horizontal, 12).padding(.bottom, 10)
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about this crop", text: $prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                    .focused($promptFocused).onSubmit(submit)
                    .disabled(!coordinator.canSend)
                Button(action: submit) { Image(systemName: "arrow.up").frame(width: 24, height: 24) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.canSend || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send question").accessibilityLabel("Send question")
            }
            .padding(12)
        }
        .frame(minWidth: 360, minHeight: 420)
        .background {
            if reduceTransparency || opaquePreviewBackdrop { Color(nsColor: .windowBackgroundColor) }
            else { Rectangle().fill(.regularMaterial) }
        }
        .onExitCommand(perform: onClose)
        .onChange(of: prompt) { if prompt.count > 3_000 { prompt = String(prompt.prefix(3_000)) } }
        .onChange(of: coordinator.phase) { if coordinator.phase == .ready { promptFocused = true } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let image = coordinator.sourceImage {
                Button { showSource.toggle() } label: {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: 76, height: 48).background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain).help("Show captured region").accessibilityLabel("Show captured region")
                .popover(isPresented: $showSource) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 560, maxHeight: 640).padding(12)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Label("FlowSnip AI", systemImage: "sparkles").font(.system(size: 15, weight: .semibold))
                Text(coordinator.providerLabel + " | " + coordinator.modelLabel)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            tool("New AI scan", symbol: "crop", action: onNewScan)
            tool("AI Settings", symbol: "slider.horizontal.3", action: onSettings)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(coordinator.messages.enumerated()), id: \.element.id) { index, message in
                        if index != 0 || message.role != .user {
                            VStack(alignment: .leading, spacing: 6) {
                                if message.role == .user {
                                    Text("You").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                }
                                if !message.text.isEmpty {
                                    Text(LocalizedStringKey(message.text)).font(.system(size: 13)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if coordinator.isBusy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(coordinator.phase == .preparing ? "Preparing crop..." : "Analyzing...")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    if coordinator.metadata?.truncated == true {
                        Text("Response limit reached.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("answer-end")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: coordinator.messages.count) { proxy.scrollTo("answer-end", anchor: .bottom) }
        }
    }

    private var textResult: some View {
        ScrollView {
            Text(coordinator.extractedText.isEmpty ? (coordinator.isBusy ? "Recognizing text..." : "No text detected in this crop.") : coordinator.extractedText)
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            tool(selectedTab == 0 ? "Copy answer" : "Copy extracted text", symbol: "doc.on.doc",
                disabled: selectedTab == 0 ? coordinator.latestAnswer.isEmpty : coordinator.extractedText.isEmpty) {
                coordinator.copyText(selectedTab == 0 ? coordinator.latestAnswer : coordinator.extractedText)
            }
            tool("Copy captured image", symbol: "photo.on.rectangle", disabled: coordinator.sourceImage == nil) { coordinator.copyImage() }
            Menu {
                ForEach(["English", "German", "French", "Spanish", "Japanese"], id: \.self) { language in
                    Button(language) { coordinator.send("Translate the text in this crop to \(language). Preserve numbers and layout where possible.") }
                }
            } label: { Image(systemName: "globe").frame(width: 28, height: 28) }
            .menuStyle(.borderlessButton).fixedSize().disabled(!coordinator.canSend)
            .help("Translate captured text").accessibilityLabel("Translate captured text")
            tool("Retry last question", symbol: "arrow.clockwise", disabled: !coordinator.canSend || coordinator.messages.isEmpty) { coordinator.retry() }
            Spacer(minLength: 6)
            if !coordinator.clipboardFeedback.isEmpty {
                Label(coordinator.clipboardFeedback, systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(.green)
            } else if let metrics = coordinator.metadata?.localMetrics {
                Text(String(format: "%.1f s", metrics.totalSeconds)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            } else if let tokens = coordinator.metadata?.outputTokens {
                Text("\(tokens) tokens").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            if coordinator.isBusy { tool("Stop response", symbol: "stop.fill") { coordinator.stop() } }
        }
    }

    private func tool(_ title: String, symbol: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .buttonStyle(.borderless).disabled(disabled).help(title).accessibilityLabel(title)
    }

    private func submit() {
        guard coordinator.canSend else { return }
        coordinator.send(prompt)
        prompt = ""
    }
}

@MainActor
struct AISettingsView: View {
    @ObservedObject var configuration: AIConfiguration
    @ObservedObject var localModels: LocalModelManager
    @ObservedObject var catalog: OpenRouterCatalog
    @ObservedObject var recorder: AIShortcutRecorder
    @State private var modelSearch = ""
    @State private var enteredKey = ""
    @State private var keyMessage = ""
    @State private var isCheckingKey = false
    @State private var pendingDownload: LocalModelSpec?
    @State private var pendingDeletion: LocalModelSpec?
    @State private var operationError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("AI Settings", systemImage: "sparkles.rectangle.stack")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Picker("Provider", selection: $configuration.provider) {
                    ForEach(AIProviderChoice.allCases) { provider in Text(provider.title).tag(provider) }
                }
                .pickerStyle(.segmented)
                if configuration.provider == .local { localSettings } else { cloudSettings }
                Divider()
                shortcutSettings
                Toggle("Thorough responses", isOn: $configuration.extendedReasoning)
                if let operationError {
                    Label(operationError, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.red)
                }
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            configuration.refreshKeyStatus()
            if configuration.provider == .openRouter { await catalog.refresh() }
        }
        .onChange(of: configuration.provider) {
            recorder.stop()
            if configuration.provider == .openRouter { Task { await catalog.refresh() } }
        }
        .onDisappear { enteredKey = ""; recorder.stop() }
        .alert("Download local model?", isPresented: Binding(get: { pendingDownload != nil }, set: { if !$0 { pendingDownload = nil } })) {
            Button("Cancel", role: .cancel) { pendingDownload = nil }
            Button("Download") {
                if let model = pendingDownload { localModels.startDownload(model) }
                pendingDownload = nil
            }
        } message: {
            if let model = pendingDownload { Text("\(model.name), approximately \(model.downloadLabel), will be stored on this Mac. No crop is uploaded for local analysis.") }
        }
        .alert("Remove local model?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Remove", role: .destructive) {
                if let model = pendingDeletion { Task { do { try await localModels.delete(model) } catch { operationError = error.localizedDescription } } }
                pendingDeletion = nil
            }
        } message: { Text("The downloaded weights will be deleted. You can download them again later.") }
    }

    private var localSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "cpu").font(.system(size: 20)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(configuration.hardware.description).font(.system(size: 13, weight: .medium))
                    Text(configuration.hardware.primaryProfile ? "M4 / M5 profile" : "Experimental hardware profile")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if !configuration.hardware.supported {
                Label(AIError.unsupportedHardware.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.red)
            }
            Picker("Local model", selection: $configuration.localModelID) {
                ForEach(LocalModelSpec.all) { model in
                    HStack(spacing: 8) {
                        Text(model.name)
                        Text("\(model.profile) | 4-bit | \(model.downloadLabel)").foregroundStyle(.secondary)
                        if model == configuration.hardware.recommendation {
                            Text("Recommended").foregroundStyle(.green).font(.system(size: 11, weight: .medium))
                        }
                    }
                    .tag(model.id).disabled(!configuration.hardware.supports(model))
                }
            }
            .pickerStyle(.radioGroup).disabled(localModels.isGenerating || localModels.isCalibrating)
            if let selected = LocalModelSpec.find(configuration.localModelID) {
                modelControls(selected)
            }
            if let metrics = localModels.lastMetrics {
                HStack(spacing: 20) {
                    metric("First token", value: String(format: "%.1f s", metrics.firstTokenSeconds))
                    metric("Answer", value: String(format: "%.1f s", metrics.totalSeconds))
                    metric("Peak MLX memory", value: ByteCountFormatter.string(fromByteCount: Int64(metrics.peakMemoryBytes), countStyle: .memory))
                }
            }
            Button { NSWorkspace.shared.open(localModels.storageDirectory) } label: {
                Label("Show Model Files", systemImage: "folder")
            }
            .buttonStyle(.borderless)
        }
    }

    private func modelControls(_ model: LocalModelSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if localModels.downloadModelID == model.id {
                ProgressView(value: localModels.downloadProgress)
                HStack {
                    Text(localModels.downloadStatus).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button { localModels.cancelDownload() } label: { Label("Pause", systemImage: "pause.fill") }
                }
            } else if localModels.downloadedModels.contains(model.id) {
                HStack {
                    Label("Downloaded", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
                    Spacer()
                    if localModels.isCalibrating {
                        Button { localModels.cancelCalibration() } label: { Label("Stop Check", systemImage: "stop.fill") }
                    } else {
                        Button { localModels.startCalibration(model) } label: { Label("Check Performance", systemImage: "gauge.with.dots.needle.50percent") }
                            .disabled(localModels.isGenerating)
                    }
                    Button(role: .destructive) { pendingDeletion = model } label: { Image(systemName: "trash") }
                        .help("Remove model").accessibilityLabel("Remove model")
                        .disabled(localModels.isGenerating || localModels.isCalibrating || localModels.downloadModelID != nil)
                }
            } else {
                Button { pendingDownload = model } label: { Label("Download \(model.name)", systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!configuration.hardware.supports(model) || localModels.downloadModelID != nil)
            }
            if !localModels.calibrationStatus.isEmpty {
                Text(localModels.calibrationStatus).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let error = localModels.downloadError {
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.red)
            }
        }
    }

    private var cloudSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Allow cloud processing", isOn: $configuration.cloudConsent)
            Text("Selected crops are sent to OpenRouter and the chosen provider. Their data policies apply.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField("OpenRouter API key", text: $enteredKey).textFieldStyle(.roundedBorder)
                Button { saveKey() } label: { Label("Save", systemImage: "lock") }.disabled(enteredKey.isEmpty)
                Button { verifyKey() } label: { Image(systemName: "checkmark.shield") }
                    .disabled(isCheckingKey || (!configuration.hasAPIKey && enteredKey.isEmpty)).help("Verify API key").accessibilityLabel("Verify API key")
                Button(role: .destructive) {
                    do { try configuration.removeKey(); keyMessage = "Key removed."; enteredKey = "" }
                    catch { keyMessage = error.localizedDescription }
                } label: { Image(systemName: "trash") }
                .disabled(!configuration.hasAPIKey).help("Remove API key").accessibilityLabel("Remove API key")
            }
            HStack {
                Label(configuration.hasAPIKey ? "Key saved in Keychain" : "No key saved", systemImage: configuration.hasAPIKey ? "lock.fill" : "lock.open")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Link("Manage OpenRouter Key", destination: URL(string: "https://openrouter.ai/settings/keys")!).font(.system(size: 11))
            }
            if !keyMessage.isEmpty { Text(keyMessage).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                TextField("Search image-capable models", text: $modelSearch).textFieldStyle(.roundedBorder)
                Button { Task { await catalog.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(catalog.isRefreshing).help("Refresh model catalog").accessibilityLabel("Refresh model catalog")
            }
            if !configuration.cloudModelID.isEmpty {
                Text("Selected: " + (catalog.model(configuration.cloudModelID)?.name ?? configuration.cloudModelID))
                    .font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No model selected").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredModels) { model in
                        Button { configuration.cloudModelID = model.id } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: configuration.cloudModelID == model.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(configuration.cloudModelID == model.id ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(model.name).font(.system(size: 12, weight: .medium))
                                        if model.suggested { Text("Suggested").font(.system(size: 10)).foregroundStyle(.green) }
                                    }
                                    Text(model.priceLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 10).padding(.horizontal, 8)
                            .background(configuration.cloudModelID == model.id ? Color.accentColor.opacity(0.08) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Select " + model.name)
                        Divider()
                    }
                    if filteredModels.isEmpty { Text("No matching image-capable models.").font(.system(size: 12)).foregroundStyle(.secondary).padding() }
                }
            }
            .frame(height: 180)
            if let error = catalog.error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
        }
    }

    private var filteredModels: [OpenRouterModel] {
        catalog.models.filter { modelSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(modelSearch) || $0.id.localizedCaseInsensitiveContains(modelSearch) }
    }

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("AI Scan Shortcut", systemImage: "keyboard").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(recorder.isRecording ? "Recording..." : configuration.aiShortcut.label)
                    .font(.system(size: 11, design: .monospaced)).lineLimit(2)
                    .frame(maxWidth: 240, alignment: .trailing)
                Button { recorder.isRecording ? recorder.stop() : recorder.start() } label: {
                    Label(recorder.isRecording ? "Cancel" : "Record", systemImage: recorder.isRecording ? "xmark" : "record.circle")
                }
                Button { recorder.stop(); configuration.aiShortcut = .aiScan } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Reset AI shortcut").accessibilityLabel("Reset AI shortcut")
            }
            if let error = configuration.shortcutError { Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.red) }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    private func saveKey() {
        do { try configuration.saveKey(enteredKey); enteredKey = ""; keyMessage = "Key saved securely." }
        catch { keyMessage = error.localizedDescription }
    }

    private func verifyKey() {
        isCheckingKey = true
        Task {
            defer { isCheckingKey = false }
            do {
                let key = enteredKey.isEmpty ? try KeychainCredentialStore.read() ?? "" : enteredKey
                try await catalog.client.verifyKey(key)
                if !enteredKey.isEmpty { try configuration.saveKey(enteredKey); enteredKey = "" }
                keyMessage = "Key verified."
            } catch { keyMessage = error.localizedDescription }
        }
    }
}

@MainActor
final class AIWindowManager: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var recorder: AIShortcutRecorder?
    let coordinator: AIScanCoordinator
    var onNewScan: (() -> Void)?
    var onShortcutRecordingChanged: ((Bool) -> Void)?

    init(coordinator: AIScanCoordinator) { self.coordinator = coordinator }

    func showAssistant(near selection: CGRect, on screen: NSScreen) {
        closeAssistant(cancel: false)
        let frame = AssistantPanelPlacement.frame(near: selection, visibleFrame: screen.visibleFrame)
        let panel = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "FlowSnip AI"
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 360, height: 420)
        panel.contentView = NSHostingView(rootView: AssistantPanelView(coordinator: coordinator,
            onSettings: { [weak self] in self?.showSettings() },
            onNewScan: { [weak self] in self?.onNewScan?() }, onClose: { [weak self] in self?.closeAssistant() }))
        panel.delegate = self
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeAssistant(cancel: Bool = true) {
        let existing = panel
        panel = nil
        existing?.delegate = nil
        existing?.close()
        if cancel { coordinator.cancel() }
    }

    func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let recorder = AIShortcutRecorder(configuration: coordinator.configuration) { [weak self] active in self?.onShortcutRecordingChanged?(active) }
        self.recorder = recorder
        let view = AISettingsView(configuration: coordinator.configuration, localModels: coordinator.localModels,
            catalog: coordinator.catalog, recorder: recorder)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 660),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "FlowSnip AI Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 560, height: 520)
        window.contentView = NSHostingView(rootView: view)
        window.delegate = self
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === panel { panel = nil; coordinator.cancel() }
        if notification.object as? NSWindow === settingsWindow {
            recorder?.stop()
            recorder = nil
            settingsWindow = nil
        }
    }

    func shutdown() {
        recorder?.stop()
        closeAssistant()
        settingsWindow?.close()
        settingsWindow = nil
    }
}