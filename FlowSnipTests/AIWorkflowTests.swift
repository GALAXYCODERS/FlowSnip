import XCTest
import Carbon
import WebKit

final class AIWorkflowTests: XCTestCase {
    @MainActor
    func testCloudKeyIsReadOnlyOncePerAppSession() throws {
        var reads = 0
        let credentials = APICredentialAccess(containsKey: { true }, read: { reads += 1; return "test-key" }, save: { _ in }, remove: {})
        let configuration = AIConfiguration(credentials: credentials)
        configuration.refreshKeyStatus()
        XCTAssertEqual(reads, 0)
        for _ in 0..<10 { XCTAssertEqual(try configuration.apiKey(), "test-key") }
        configuration.refreshKeyStatus()
        XCTAssertEqual(reads, 1)
        let nextSession = AIConfiguration(credentials: credentials)
        XCTAssertEqual(try nextSession.apiKey(), "test-key")
        XCTAssertEqual(reads, 2)
    }

    @MainActor
    func testSavingAndRemovingKeysUpdatesSessionWithoutExtraReads() throws {
        var stored: String?
        var reads = 0
        let credentials = APICredentialAccess(containsKey: { stored != nil }, read: { reads += 1; return stored },
            save: { stored = $0 }, remove: { stored = nil })
        let configuration = AIConfiguration(credentials: credentials)
        let originalRevision = configuration.credentialRevision
        try configuration.saveKey("  test-first  ")
        XCTAssertEqual(try configuration.apiKey(), "test-first")
        XCTAssertEqual(reads, 0)
        XCTAssertNotEqual(configuration.credentialRevision, originalRevision)
        try configuration.saveKey("test-replacement")
        XCTAssertEqual(try configuration.apiKey(), "test-replacement")
        XCTAssertEqual(reads, 0)
        try configuration.removeKey()
        XCTAssertFalse(configuration.hasAPIKey)
        XCTAssertThrowsError(try configuration.apiKey())
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testDeniedKeychainReadDoesNotCacheFailure() throws {
        var reads = 0
        let credentials = APICredentialAccess(containsKey: { true }, read: {
            reads += 1
            if reads == 1 { throw AIError.message("Access denied") }
            return "test-key"
        }, save: { _ in }, remove: {})
        let configuration = AIConfiguration(credentials: credentials)
        XCTAssertThrowsError(try configuration.apiKey())
        XCTAssertEqual(try configuration.apiKey(), "test-key")
        XCTAssertEqual(try configuration.apiKey(), "test-key")
        XCTAssertEqual(reads, 2)
    }

    @MainActor
    func testBundledRendererTypesetsMathAndPreservesCode() async throws {
        let webView = try await renderer()
        let text = #"The domain requires (x\ge \tfrac12). Only the smaller root works."#
            + "\n[\nx^2-104x+208=0,\n]\n\n"
            + #"\[\boxed{x=52-8\sqrt{39}}\]"#
            + "\n\n```latex\n\\sqrt{39}\n```\n\n**Result**\n\n| Root | Valid |\n| --- | --- |\n| Small | Yes |"
        _ = try await webView.callAsyncJavaScript("window.renderAnswer(text)", arguments: ["text": text], in: nil, contentWorld: .page)
        let mathCount = try await webView.evaluateJavaScript("document.querySelectorAll('.katex').length") as? Int
        XCTAssertEqual(mathCount, 3)
        let displayCount = try await webView.evaluateJavaScript("document.querySelectorAll('.katex-display').length") as? Int
        XCTAssertEqual(displayCount, 2)
        let radicalPaths = try await webView.evaluateJavaScript("document.querySelectorAll('.katex svg path').length") as? Int
        XCTAssertGreaterThan(radicalPaths ?? 0, 0)
        let radicalVisible = try await webView.evaluateJavaScript("document.querySelector('.katex svg path').getBoundingClientRect().height > 0") as? Bool
        XCTAssertEqual(radicalVisible, true)
        let code = try await webView.evaluateJavaScript("document.querySelector('pre code').textContent") as? String
        XCTAssertEqual(code?.trimmingCharacters(in: .whitespacesAndNewlines), #"\sqrt{39}"#)
        let tableCount = try await webView.evaluateJavaScript("document.querySelectorAll('table').length") as? Int
        XCTAssertEqual(tableCount, 1)
    }

    @MainActor
    func testRendererHandlesStreamingMathAndBlocksActiveContent() async throws {
        let webView = try await renderer()
        for text in [#"Answer: $$\boxed{x=52"#, #"Answer: $x=52-8\sqrt{39}$"#,
                     "<script>window.compromised=true</script><img src='https://example.com/pixel' onerror='window.compromised=true'>\n\n[Bad](javascript:alert(1))\n\n$$\\notacommand{x}$$"] {
            _ = try await webView.callAsyncJavaScript("window.renderAnswer(text)", arguments: ["text": text], in: nil, contentWorld: .page)
        }
        let activeContent = try await webView.evaluateJavaScript("document.querySelector('#answer').querySelectorAll('img,script,iframe,object').length") as? Int
        let compromised = try await webView.evaluateJavaScript("window.compromised === true") as? Bool
        let unsafeLinks = try await webView.evaluateJavaScript("document.querySelectorAll('a[href^=\"javascript:\"]').length") as? Int
        let fallbacks = try await webView.evaluateJavaScript("document.querySelectorAll('.math-fallback').length") as? Int
        XCTAssertEqual(activeContent, 0)
        XCTAssertEqual(compromised, false)
        XCTAssertEqual(unsafeLinks, 0)
        XCTAssertEqual(fallbacks, 1)
    }

    @MainActor
    private func renderer() async throws -> WKWebView {
        _ = NSApplication.shared
        let bundle = Bundle(for: AIWorkflowTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "index", withExtension: "html", subdirectory: "AnswerRenderer"))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 420, height: 600), configuration: AnswerWebView.configuration())
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        for _ in 0..<200 {
            if let ready = try? await webView.evaluateJavaScript("typeof window.renderAnswer === 'function'"), ready as? Bool == true { return webView }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AIError.message("The bundled answer renderer did not load.")
    }

    func testDefaultShortcutsAreDistinctAndValid() {
        XCTAssertTrue(ShortcutChord.screenshot.isValid)
        XCTAssertTrue(ShortcutChord.aiScan.isValid)
        XCTAssertNotEqual(ShortcutChord.screenshot, .aiScan)
        XCTAssertEqual(ShortcutChord.aiScan.label, "Option + Shift + Command + 2")
    }

    func testUnsafeShortcutsAreRejected() {
        XCTAssertFalse(ShortcutChord(keyCode: 0, modifiers: 0).isValid)
        XCTAssertFalse(ShortcutChord(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey)).isValid)
        XCTAssertFalse(ShortcutChord(keyCode: 200, modifiers: UInt32(cmdKey)).isValid)
        XCTAssertFalse(ShortcutChord(keyCode: 0, modifiers: UInt32(cmdKey) | 0x8000_0000).isValid)
    }

    func testShortcutRoundTripsThroughSettings() throws {
        let encoded = try JSONEncoder().encode(ShortcutChord.aiScan)
        XCTAssertEqual(try JSONDecoder().decode(ShortcutChord.self, from: encoded), .aiScan)
    }

    func testCarbonAndMonitorDuplicatesDispatchOnce() {
        var dispatcher = ShortcutDeduplicator()
        XCTAssertTrue(dispatcher.accepts(.aiScan, at: 10))
        XCTAssertFalse(dispatcher.accepts(.aiScan, at: 10.01))
        XCTAssertTrue(dispatcher.accepts(.aiScan, at: 10.3))
    }

    func testDifferentActionsAreNotSuppressed() {
        var dispatcher = ShortcutDeduplicator()
        XCTAssertTrue(dispatcher.accepts(.screenshot, at: 10))
        XCTAssertTrue(dispatcher.accepts(.aiScan, at: 10.01))
        XCTAssertFalse(dispatcher.accepts(.aiScan, at: 11, isRepeat: true))
    }

    func testCancelledSessionsRejectLateResults() {
        var gate = ScanSessionGate()
        let previous = gate.begin()
        gate.cancel()
        XCTAssertEqual(gate.phase, .idle)
        XCTAssertFalse(gate.advance(previous, to: .ready))
        XCTAssertFalse(gate.contains(previous))
    }

    func testNewScanInvalidatesPreviousSession() {
        var gate = ScanSessionGate()
        let previous = gate.begin()
        let current = gate.begin()
        XCTAssertFalse(gate.advance(previous, to: .failed))
        XCTAssertTrue(gate.advance(current, to: .capturing))
        XCTAssertTrue(gate.advance(current, to: .analyzing))
        XCTAssertTrue(gate.advance(current, to: .ready))
        XCTAssertEqual(gate.phase, .ready)
    }

    func testHardwareRecommendationsRespectMemoryAndMetalBudget() {
        func hardware(memory: Int, metal: Int = 12) -> MacHardwareSnapshot {
            MacHardwareSnapshot(chip: "Apple M5", memoryBytes: UInt64(memory) * 1_073_741_824,
                metalWorkingSetBytes: UInt64(metal) * 1_073_741_824, majorOS: 27, nativeAppleSilicon: true)
        }
        XCTAssertNil(hardware(memory: 8).recommendation)
        XCTAssertEqual(hardware(memory: 16).recommendation, .balanced)
        XCTAssertEqual(hardware(memory: 24, metal: 18).recommendation, .quality)
        XCTAssertEqual(hardware(memory: 48, metal: 32).recommendation, .quality)
        XCTAssertFalse(hardware(memory: 16).supports(.quality))
        XCTAssertFalse(hardware(memory: 48, metal: 4).supports(.large))
    }

    func testLocalModelsArePinnedAndRetainSafeResourceRequirements() {
        for model in LocalModelSpec.all {
            XCTAssertEqual(model.revision.count, 40)
            XCTAssertTrue(model.id.hasPrefix("mlx-community/"))
            XCTAssertGreaterThanOrEqual(model.minimumMemoryGB, 16)
            XCTAssertGreaterThan(model.weightBytes, 0)
        }
    }

    func testOlderAndNonNativeDevicesDoNotReceiveLocalRecommendation() {
        let older = MacHardwareSnapshot(chip: "Apple M5", memoryBytes: 16 * 1_073_741_824,
            metalWorkingSetBytes: 12 * 1_073_741_824, majorOS: 26, nativeAppleSilicon: true)
        let nonNative = MacHardwareSnapshot(chip: "Intel", memoryBytes: 32 * 1_073_741_824,
            metalWorkingSetBytes: 24 * 1_073_741_824, majorOS: 27, nativeAppleSilicon: false)
        XCTAssertNil(older.recommendation)
        XCTAssertNil(nonNative.recommendation)
    }

    func testConversationHistoryIsBoundedAndStartsWithUser() {
        let history = (0..<10).map { index in
            AIConversationMessage(role: index.isMultiple(of: 2) ? .user : .assistant, text: String(repeating: "a", count: 5_000))
        }
        let request = AIRequest(imageData: Data(), prompt: "Explain", history: history, extendedReasoning: false)
        XCTAssertLessThanOrEqual(request.boundedHistory.count, 6)
        XCTAssertEqual(request.boundedHistory.first?.role, .user)
        XCTAssertTrue(request.boundedHistory.allSatisfy { $0.text.count <= 3_000 })
    }

    @MainActor
    func testSettingsDefaultToLocalAndRequireExplicitCloudChoice() throws {
        let suite = "FlowSnipTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = AIConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.provider, .local)
        XCTAssertEqual(configuration.cloudModelID, "")
        XCTAssertFalse(configuration.cloudConsent)
        configuration.cloudModelID = "google/gemini-3.8-flash"
        configuration.provider = .openRouter
        let restored = AIConfiguration(defaults: defaults)
        XCTAssertEqual(restored.cloudModelID, "google/gemini-3.8-flash")
        XCTAssertEqual(restored.provider, .openRouter)
        XCTAssertFalse(restored.cloudConsent)
    }

    func testPanelPlacementRemainsInsideSecondaryDisplay() {
        let visible = CGRect(x: -1_920, y: 900, width: 1_920, height: 1_080)
        for selection in [CGRect(x: -1_900, y: 910, width: 100, height: 100), CGRect(x: -100, y: 1_880, width: 90, height: 90)] {
            XCTAssertTrue(visible.contains(AssistantPanelPlacement.frame(near: selection, visibleFrame: visible)))
        }
    }

    func testReasoningTagsSplitAcrossChunksAreNotDisplayed() {
        var filter = ReasoningStreamFilter()
        XCTAssertEqual(filter.consume("<thi"), "")
        XCTAssertEqual(filter.consume("nk>private analysis</thi"), "")
        XCTAssertEqual(filter.consume("nk>Visible answer"), "Visible answer")
        XCTAssertEqual(filter.finish(), "")
    }

    func testImplicitThinkingPrefixIsHiddenUntilAnswer() {
        var filter = ReasoningStreamFilter(thinking: true)
        XCTAssertEqual(filter.consume("analysis </think>Answer"), "Answer")
    }
}