import Cocoa
import SwiftUI
import Combine

private struct UIValidationProvider: AIProvider {
    func respond(_ request: AIRequest, onChunk: @escaping @Sendable (String) async -> Void) async throws -> AIResponseMetadata {
        let answer = request.prompt.hasPrefix("Translate")
            ? "TypeError: Eigenschaften von undefined konnen nicht gelesen werden."
            : "`items` is undefined when `.map()` runs. Initialize it to an empty array, or wait until the data has loaded before mapping it.\n\nFor example: `const items = data?.items ?? [];`"
        for chunk in [String(answer.prefix(answer.count / 2)), String(answer.suffix(answer.count - answer.count / 2))] {
            try Task.checkCancellation()
            await onChunk(chunk)
            try await Task.sleep(for: .milliseconds(20))
        }
        return AIResponseMetadata()
    }
}

@MainActor
enum AIValidationRunner {
    static func run(arguments: [String]) async -> Int32 {
        do {
            let directory = URL(fileURLWithPath: value(after: "--report-directory", arguments: arguments) ?? "/tmp/FlowSnip-Validation", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if arguments.contains("--verify-local-ai") {
                let hardware = MacHardwareSnapshot.current()
                guard let model = LocalModelSpec.find(value(after: "--model", arguments: arguments) ?? LocalModelSpec.balanced.id) else { throw AIError.modelMissing }
                let manager = LocalModelManager(hardware: hardware)
                var reportedProgress = -1
                let subscription = manager.$downloadProgress.sink { progress in
                    let percent = Int(progress * 100)
                    if percent / 5 > reportedProgress / 5 {
                        reportedProgress = percent
                        print("Model download: \(percent)%")
                        fflush(stdout)
                    }
                }
                defer { subscription.cancel() }
                print("Local validation: \(model.name) on \(hardware.description)")
                fflush(stdout)
                if arguments.contains("--offline") {
                    guard manager.directory(for: model) != nil else { throw AIError.modelMissing }
                } else { try await manager.download(model) }
                print("Model files ready. Running three synthetic image checks...")
                fflush(stdout)
                let report = try await manager.calibrate(model)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(report).write(to: directory.appendingPathComponent("local-inference.json"), options: .atomic)
                for result in report.results {
                    print(String(format: "%@: first token %.2f s, total %.2f s, expected content %@", result.name,
                        result.metrics.firstTokenSeconds, result.metrics.totalSeconds, result.matchedExpectedContent ? "matched" : "not matched"))
                }
                try await verifyLocalLifecycle(manager: manager, model: model, directory: directory)
                await manager.unload()
                guard report.results.count == 3, report.results.allSatisfy({ !$0.answer.isEmpty }) else { throw AIError.emptyResponse }
            }
            if arguments.contains("--render-ai-ui") {
                try await renderUI(to: directory)
            }
            return 0
        } catch {
            fputs("FlowSnip validation failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func renderUI(to directory: URL) async throws {
        let suite = "FlowSnip.UIValidation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw AIError.message("Could not create isolated validation settings.") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = AIConfiguration(defaults: defaults)
        let manager = LocalModelManager(hardware: configuration.hardware)
        let catalog = OpenRouterCatalog(storageDirectory: manager.storageDirectory)
        let coordinator = AIScanCoordinator(configuration: configuration, localModels: manager, catalog: catalog)
        let fixture = try ScanValidationFixtures.make()[0]
        coordinator.begin(image: fixture.image, providerOverride: UIValidationProvider())
        print("UI validation: preparing the synthetic crop and OCR.")
        fflush(stdout)
        try await waitUntilReady(coordinator)
        print("UI validation: initial answer and OCR completed.")
        fflush(stdout)
        guard !coordinator.extractedText.isEmpty else { throw AIError.message("The synthetic OCR check returned no text.") }
        coordinator.send("Explain the fix in one sentence.")
        try await waitUntilReady(coordinator)
        guard coordinator.messages.count == 4 else { throw AIError.message("The assistant follow-up check failed.") }
        coordinator.retry()
        try await waitUntilReady(coordinator)
        guard coordinator.messages.count == 4 else { throw AIError.message("Retry duplicated the visible conversation.") }
        coordinator.send("Cancelled question")
        coordinator.stop()
        coordinator.send("New question after stop")
        try await waitUntilReady(coordinator)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        coordinator.copyText(coordinator.latestAnswer, pasteboard: pasteboard)
        guard pasteboard.string(forType: .string) == coordinator.latestAnswer else { throw AIError.message("The assistant copy check failed.") }
        coordinator.copyImage(pasteboard: pasteboard)
        guard pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) else { throw AIError.message("The assistant image copy check failed.") }
        let assistant = AssistantPanelView(coordinator: coordinator, onSettings: {}, onNewScan: {}, onClose: {}, opaquePreviewBackdrop: true)
        try await render(assistant, filename: "assistant-light.png", size: CGSize(width: 460, height: 560), scheme: .light, directory: directory)
        try await render(assistant, filename: "assistant-dark.png", size: CGSize(width: 460, height: 560), scheme: .dark, directory: directory)
        let recorder = AIShortcutRecorder(configuration: configuration, onRecordingChanged: { _ in })
        let settings = AISettingsView(configuration: configuration, localModels: manager, catalog: catalog, recorder: recorder)
        try await render(settings, filename: "settings-local.png", size: CGSize(width: 700, height: 660), scheme: .light, directory: directory)
        await catalog.refresh()
        configuration.provider = .openRouter
        try await render(settings, filename: "settings-cloud.png", size: CGSize(width: 700, height: 660), scheme: .light, directory: directory)
        let report: [String: Any] = ["ocr": "passed", "followUp": "passed", "privateClipboardCopy": "passed",
            "privateImageCopy": "passed", "catalogModelCount": catalog.models.count,
            "retry": "passed", "stopThenFollowUp": "passed",
            "screenRecordingPermission": CGPreflightScreenCaptureAccess(), "nativeUIRenders": 4]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("ui-validation.json"), options: .atomic)
        coordinator.cancel()
        recorder.stop()
        await manager.unload()
        print("Native UI, OCR, follow-up, and private-clipboard checks completed. Preview images: \(directory.path)")
    }

    private static func verifyLocalLifecycle(manager: LocalModelManager, model: LocalModelSpec, directory: URL) async throws {
        let fixture = try ScanValidationFixtures.make()[1]
        let request = AIRequest(imageData: try ScanImageProcessing.pngData(for: fixture.image),
            prompt: "Describe all visible details in this receipt.", history: [], extendedReasoning: false)
        let cancelled = Task { try await manager.respond(request, model: model, onChunk: { _ in }) }
        try await Task.sleep(for: .milliseconds(100))
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            throw AIError.message("The local cancellation check did not cancel the request.")
        } catch is CancellationError {}
        guard !manager.isGenerating else { throw AIError.message("The local runtime stayed busy after cancellation.") }
        let conversation = [AIConversationMessage(role: .user, text: "What is the total?"),
            AIConversationMessage(role: .assistant, text: "19.80 EUR.")]
        let followUp = AIRequest(imageData: request.imageData, prompt: "What is the currency? Answer with only its three-letter code.",
            history: conversation, extendedReasoning: false)
        let collector = ValidationTextCollector()
        _ = try await manager.respond(followUp, model: model) { chunk in await collector.append(chunk) }
        let answer = await collector.text
        guard answer.localizedCaseInsensitiveContains("EUR") else { throw AIError.message("The local image follow-up did not preserve the receipt context.") }
        let report: [String: Any] = ["cancellation": "passed", "followUp": "passed", "offlineRuntime": "local snapshot only", "model": model.id]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("local-lifecycle.json"), options: .atomic)
        print("Local cancellation and image follow-up checks passed.")
    }

    private static func waitUntilReady(_ coordinator: AIScanCoordinator) async throws {
        for _ in 0..<600 {
            try Task.checkCancellation()
            if coordinator.phase == .failed { throw AIError.message(coordinator.error ?? "The validation session failed.") }
            if coordinator.phase == .ready { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AIError.message("The validation session timed out in phase \(coordinator.phase.rawValue).")
    }

    private static func render<Content: View>(_ content: Content, filename: String, size: CGSize, scheme: ColorScheme, directory: URL) async throws {
        let hosting = NSHostingView(rootView: content.environment(\.colorScheme, scheme))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        window.center()
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw AIError.message("The native window preview could not be allocated.")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw AIError.message("The native window preview could not be encoded.")
        }
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
    }

    private static func value(after flag: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

private actor ValidationTextCollector {
    private(set) var text = ""
    func append(_ chunk: String) { text += chunk }
}