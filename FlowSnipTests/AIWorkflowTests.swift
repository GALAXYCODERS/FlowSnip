import XCTest
import Carbon

final class AIWorkflowTests: XCTestCase {
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