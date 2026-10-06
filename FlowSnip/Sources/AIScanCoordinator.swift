import Cocoa
import Combine

@MainActor
final class AIScanCoordinator: ObservableObject {
    let configuration: AIConfiguration
    let localModels: LocalModelManager
    let catalog: OpenRouterCatalog
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var sourceImage: NSImage?
    @Published private(set) var messages: [AIConversationMessage] = []
    @Published private(set) var extractedText = ""
    @Published private(set) var error: String?
    @Published private(set) var providerLabel = ""
    @Published private(set) var modelLabel = ""
    @Published private(set) var metadata: AIResponseMetadata?
    @Published private(set) var clipboardFeedback = ""
    private var sourceCGImage: CGImage?
    private var imageData: Data?
    private var provider: (any AIProvider)?
    private var gate = ScanSessionGate()
    private var work: Task<Void, Never>?
    private var committedHistory: [AIConversationMessage] = []
    private var lastPrompt = ""
    private var lockedProvider: AIProviderChoice?
    private var lockedModelID = ""
    private var lockedCredentialRevision: UUID?
    private var streamFilter = ReasoningStreamFilter()
    private var clipboardFeedbackTask: Task<Void, Never>?

    var isBusy: Bool { phase == .preparing || phase == .analyzing || phase == .capturing }
    var canSend: Bool { imageData != nil && provider != nil && !isBusy }
    var latestAnswer: String { messages.last(where: { $0.role == .assistant })?.text ?? "" }

    init(configuration: AIConfiguration, localModels: LocalModelManager, catalog: OpenRouterCatalog) {
        self.configuration = configuration
        self.localModels = localModels
        self.catalog = catalog
    }

    func checkReadiness() throws {
        switch configuration.provider {
        case .local:
            guard !localModels.isCalibrating else { throw AIError.busy }
            guard let model = LocalModelSpec.find(configuration.localModelID), configuration.hardware.supports(model) else {
                throw AIError.unsupportedHardware
            }
            guard localModels.directory(for: model) != nil else { throw AIError.modelMissing }
        case .openRouter:
            guard configuration.cloudConsent else { throw AIError.cloudConsentRequired }
            guard !configuration.cloudModelID.isEmpty, catalog.model(configuration.cloudModelID) != nil else { throw AIError.noCloudModel }
            configuration.refreshKeyStatus()
            _ = try configuration.apiKey()
        }
    }

    func begin(image: CGImage, providerOverride: (any AIProvider)? = nil) {
        let previous = work
        previous?.cancel()
        reset()
        sourceCGImage = image
        sourceImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let identifier = gate.begin()
        gate.advance(identifier, to: .preparing)
        phase = .preparing
        do {
            if let providerOverride {
                provider = providerOverride
                providerLabel = "UI validation"
                modelLabel = "Synthetic crop"
            } else {
                try checkReadiness()
                lockedProvider = configuration.provider
                switch configuration.provider {
                case .local:
                    guard let model = LocalModelSpec.find(configuration.localModelID) else { throw AIError.modelMissing }
                    lockedModelID = model.id
                    provider = LocalAIProvider(manager: localModels, model: model)
                    providerLabel = "On This Mac"
                    modelLabel = model.name + " / 4-bit"
                case .openRouter:
                    guard let model = catalog.model(configuration.cloudModelID) else { throw AIError.noCloudModel }
                    lockedModelID = model.id
                    lockedCredentialRevision = configuration.credentialRevision
                    provider = OpenRouterAIProvider(client: catalog.client, model: model, apiKey: try configuration.apiKey())
                    providerLabel = "OpenRouter"
                    modelLabel = model.name
                }
            }
        } catch {
            self.error = error.localizedDescription
            phase = .failed
            gate.advance(identifier, to: .failed)
            return
        }
        work = Task { [weak self] in
            await previous?.value
            guard let self, self.gate.contains(identifier), !Task.isCancelled else { return }
            do {
                let encoding = Task.detached(priority: .userInitiated) { try ScanImageProcessing.pngData(for: image) }
                let prepared = try await withTaskCancellationHandler(operation: { try await encoding.value }, onCancel: { encoding.cancel() })
                let text = (try? await ScanImageProcessing.extractText(from: image)) ?? ""
                try Task.checkCancellation()
                guard self.gate.contains(identifier) else { return }
                self.imageData = prepared
                self.extractedText = text
                await self.generate(prompt: "Explain this selected region briefly and helpfully.", identifier: identifier)
            } catch is CancellationError {} catch {
                guard self.gate.contains(identifier) else { return }
                self.error = error.localizedDescription
                self.phase = .failed
                self.gate.advance(identifier, to: .failed)
            }
        }
    }

    func send(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 3_000, canSend else { return }
        let previous = work
        previous?.cancel()
        let identifier = gate.begin()
        phase = .analyzing
        work = Task { [weak self] in
            await previous?.value
            guard let self, self.gate.contains(identifier), !Task.isCancelled else { return }
            await self.generate(prompt: trimmed, identifier: identifier)
        }
    }

    func retry() {
        guard canSend, !lastPrompt.isEmpty else { return }
        if phase == .ready, committedHistory.count >= 2 { committedHistory.removeLast(2) }
        if messages.last?.role == .assistant { messages.removeLast() }
        if messages.last?.role == .user { messages.removeLast() }
        send(lastPrompt)
    }

    private func generate(prompt: String, identifier: UUID) async {
        guard gate.contains(identifier), let imageData, let provider else { return }
        gate.advance(identifier, to: .analyzing)
        phase = .analyzing
        error = nil
        metadata = nil
        lastPrompt = prompt
        let question = AIConversationMessage(role: .user, text: prompt)
        let answer = AIConversationMessage(role: .assistant, text: "")
        messages.append(question)
        messages.append(answer)
        if messages.count > 14 { messages.removeFirst(messages.count - 14) }
        let request = AIRequest(imageData: imageData, prompt: prompt, history: committedHistory, extendedReasoning: configuration.extendedReasoning)
        streamFilter = ReasoningStreamFilter(thinking: lockedProvider == .local && request.extendedReasoning)
        do {
            let result = try await provider.respond(request) { [weak self] chunk in
                guard let self else { return }
                await self.receive(chunk, sessionID: identifier, answerID: answer.id)
            }
            try Task.checkCancellation()
            guard gate.contains(identifier) else { return }
            if let index = messages.firstIndex(where: { $0.id == answer.id }) { messages[index].text += streamFilter.finish() }
            guard let completed = messages.first(where: { $0.id == answer.id }), !completed.text.isEmpty else { throw AIError.emptyResponse }
            committedHistory += [question, completed]
            committedHistory = Array(committedHistory.suffix(6))
            metadata = result
            phase = .ready
            gate.advance(identifier, to: .ready)
        } catch is CancellationError {} catch {
            guard gate.contains(identifier) else { return }
            self.error = error.localizedDescription
            phase = .failed
            gate.advance(identifier, to: .failed)
        }
    }

    private func receive(_ chunk: String, sessionID: UUID, answerID: UUID) {
        guard gate.contains(sessionID), let index = messages.firstIndex(where: { $0.id == answerID }) else { return }
        messages[index].text += streamFilter.consume(chunk)
    }

    func stop() {
        work?.cancel()
        gate.cancel()
        phase = sourceImage == nil ? .idle : .ready
    }

    func cancel() {
        stop()
        reset()
    }

    func configurationChanged() {
        guard let lockedProvider else { return }
        let currentID = configuration.provider == .local ? configuration.localModelID : configuration.cloudModelID
        if lockedProvider != configuration.provider || lockedModelID != currentID || (lockedProvider == .openRouter && (!configuration.cloudConsent || !configuration.hasAPIKey || lockedCredentialRevision != configuration.credentialRevision)) {
            stop()
            provider = nil
            error = "AI settings changed. Start a new scan to use them."
        }
    }

    func copyText(_ text: String, pasteboard: NSPasteboard = .general) {
        guard !text.isEmpty else { return }
        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) { showClipboardFeedback() }
    }

    func copyImage(pasteboard: NSPasteboard = .general) {
        guard let sourceCGImage else { return }
        if CaptureEngine().copyToClipboard(sourceCGImage, pasteboard: pasteboard) { showClipboardFeedback() }
    }

    private func showClipboardFeedback() {
        clipboardFeedbackTask?.cancel()
        clipboardFeedback = "Copied"
        clipboardFeedbackTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
                self?.clipboardFeedback = ""
            } catch {}
        }
    }

    private func reset() {
        clipboardFeedbackTask?.cancel()
        gate.cancel()
        phase = .idle
        sourceImage = nil
        sourceCGImage = nil
        imageData = nil
        messages = []
        committedHistory = []
        extractedText = ""
        error = nil
        provider = nil
        metadata = nil
        clipboardFeedback = ""
        lockedProvider = nil
        lockedModelID = ""
        lockedCredentialRevision = nil
    }
}