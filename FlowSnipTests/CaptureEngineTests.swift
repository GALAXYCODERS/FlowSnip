import Cocoa
import ScreenCaptureKit
import SwiftUI
import XCTest

@MainActor
final class CaptureEngineTests: XCTestCase {

    func testOverlayWindowsUseGlobalDisplayFramesAndLocalContentFrames() throws {
        let frames = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            CGRect(x: 1512, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: 982, width: 1920, height: 1080),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080),
            CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        ]
        let manager = OverlayWindowManager()

        for frame in frames {
            for mode in CaptureMode.allCases {
                for pixelScale: CGFloat in [1, 2] {
                    let screen = CaptureTestScreen()
                    screen.testFrame = frame
                    screen.testPixelScale = pixelScale
                    let window = manager.createOverlayWindow(for: screen, mode: mode)
                    defer { window.orderOut(nil) }
                    let content = try XCTUnwrap(window.contentView as? NSHostingView<LiquidOverlayView>)

                    XCTAssertEqual(window.frame, frame)
                    XCTAssertEqual(content.frame, CGRect(origin: .zero, size: frame.size))
                    XCTAssertEqual(content.rootView.screenFrame, frame)
                    XCTAssertEqual(content.rootView.mode, mode)
                    XCTAssertEqual(content.rootView.pixelScale, pixelScale)
                }
            }
        }
    }

    func testPrimaryDisplayCropUsesTopLeftCoordinatesAndRetinaPixels() throws {
        let configuration = try CaptureEngine.configuration(
            for: CGRect(x: 100, y: 200, width: 300, height: 150),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            pixelScale: 2
        )

        XCTAssertEqual(configuration.sourceRect, CGRect(x: 100, y: 550, width: 300, height: 150))
        XCTAssertEqual(configuration.width, 600)
        XCTAssertEqual(configuration.height, 300)
        XCTAssertFalse(configuration.showsCursor)
        XCTAssertEqual(configuration.captureResolution, .best)
    }

    func testNonRetinaDisplayKeepsPointDimensions() throws {
        let configuration = try CaptureEngine.configuration(
            for: CGRect(x: 100, y: 200, width: 300, height: 150),
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            pixelScale: 1
        )

        XCTAssertEqual(configuration.width, 300)
        XCTAssertEqual(configuration.height, 150)
    }

    func testDisplayToTheLeftUsesDisplayLocalCoordinates() throws {
        let configuration = try CaptureEngine.configuration(
            for: CGRect(x: -1820, y: 200, width: 300, height: 150),
            screenFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            pixelScale: 1
        )

        XCTAssertEqual(configuration.sourceRect, CGRect(x: 100, y: 730, width: 300, height: 150))
    }

    func testDisplayAboveUsesItsOwnTopEdge() throws {
        let configuration = try CaptureEngine.configuration(
            for: CGRect(x: 100, y: 1000, width: 300, height: 150),
            screenFrame: CGRect(x: 0, y: 900, width: 1440, height: 900),
            pixelScale: 2
        )

        XCTAssertEqual(configuration.sourceRect, CGRect(x: 100, y: 650, width: 300, height: 150))
    }

    func testDisplayBelowAndToTheRightUsesLocalCoordinates() throws {
        let configuration = try CaptureEngine.configuration(
            for: CGRect(x: 1900, y: -1000, width: 300, height: 150),
            screenFrame: CGRect(x: 1800, y: -1200, width: 1600, height: 1000),
            pixelScale: 1
        )

        XCTAssertEqual(configuration.sourceRect, CGRect(x: 100, y: 650, width: 300, height: 150))
    }

    func testWholeDisplayCaptureHasZeroSourceOrigin() throws {
        let screenFrame = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let configuration = try CaptureEngine.configuration(for: screenFrame, screenFrame: screenFrame, pixelScale: 1)

        XCTAssertEqual(configuration.sourceRect, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testFractionalSelectionRoundsOutputPixelsUp() throws {
        let configuration = try CaptureEngine.configuration(
            for: CGRect(x: 10.25, y: 20.5, width: 40.25, height: 30.25),
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pixelScale: 2
        )

        XCTAssertEqual(configuration.sourceRect, CGRect(x: 10.25, y: 49.25, width: 40.25, height: 30.25))
        XCTAssertEqual(configuration.width, 81)
        XCTAssertEqual(configuration.height, 61)
    }

    func testEmptyAndNegativeSelectionsAreRejected() {
        let selections = [
            CGRect.zero,
            CGRect(x: 10, y: 10, width: 0, height: 20),
            CGRect(x: 10, y: 10, width: 20, height: 0),
            CGRect(x: 10, y: 10, width: -5, height: 20),
            CGRect(x: 10, y: 10, width: 20, height: -5)
        ]

        for selection in selections {
            assertInvalidSelection(selection)
        }
    }

    func testOutOfBoundsAndCrossDisplaySelectionsAreRejected() {
        let selections = [
            CGRect(x: -1, y: 10, width: 20, height: 20),
            CGRect(x: 10, y: -1, width: 20, height: 20),
            CGRect(x: 90, y: 10, width: 20, height: 20),
            CGRect(x: 10, y: 90, width: 20, height: 20)
        ]

        for selection in selections {
            assertInvalidSelection(selection)
        }
    }

    func testNonFiniteSelectionsAreRejected() {
        assertInvalidSelection(CGRect(x: CGFloat.nan, y: 10, width: 20, height: 20))
        assertInvalidSelection(CGRect(x: 10, y: CGFloat.infinity, width: 20, height: 20))
        assertInvalidSelection(CGRect(x: 10, y: 10, width: CGFloat.infinity, height: 20))
    }

    func testInvalidPixelScalesAreRejected() {
        let scales: [CGFloat] = [0, -1, .nan, .infinity]

        for scale in scales {
            XCTAssertThrowsError(try CaptureEngine.configuration(
                for: CGRect(x: 10, y: 10, width: 20, height: 20),
                screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                pixelScale: scale
            )) { error in
                XCTAssertEqual(error as? CaptureEngine.CaptureError, .invalidRegion)
            }
        }
    }

    func testPixelDimensionOverflowIsRejected() {
        let selection = CGRect(x: 0, y: 0, width: CGFloat(Int.max), height: 20)

        XCTAssertThrowsError(try CaptureEngine.configuration(for: selection, screenFrame: selection, pixelScale: 2)) { error in
            XCTAssertEqual(error as? CaptureEngine.CaptureError, .invalidRegion)
        }
    }

    func testExplicitClipboardDeliveryCopiesImageToRequestedPasteboard() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Existing clipboard text", forType: .string)
        let image = try makeImage(width: 4, height: 3)

        XCTAssertTrue(CaptureEngine().copyToClipboard(image, pasteboard: pasteboard))

        let copiedImage = try XCTUnwrap(pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage)
        XCTAssertEqual(copiedImage.size, NSSize(width: 4, height: 3))
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testCancellationIsCheckedBeforeScreenPermission() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let capture = Task { @MainActor in
            try await CaptureEngine().captureImage(rect: .zero, screen: screen)
        }
        capture.cancel()

        do {
            _ = try await capture.value
            XCTFail("A cancelled capture must not request screen content.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testLiveImageOnlyCapturePreservesClipboard() async throws {
        guard ProcessInfo.processInfo.environment["FLOWSNIP_CAPTURE_SMOKE_TEST"] == "1" else {
            throw XCTSkip("Set FLOWSNIP_CAPTURE_SMOKE_TEST=1 to opt into the live capture check.")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Screen Recording permission must already be granted; this test does not request it.")
        }
        let screens = NSScreen.screens
        XCTAssertFalse(screens.isEmpty)
        let clipboardChangeCount = NSPasteboard.general.changeCount

        for screen in screens {
            let selection = CGRect(x: screen.frame.minX + 10, y: screen.frame.maxY - 16, width: 8, height: 6)
            let image = try await CaptureEngine().captureImage(rect: selection, screen: screen)

            XCTAssertEqual(image.width, Int((selection.width * screen.backingScaleFactor).rounded(.up)), screen.localizedName)
            XCTAssertEqual(image.height, Int((selection.height * screen.backingScaleFactor).rounded(.up)), screen.localizedName)
            XCTAssertEqual(NSPasteboard.general.changeCount, clipboardChangeCount)
        }
    }

    private func assertInvalidSelection(_ selection: CGRect) {
        XCTAssertThrowsError(try CaptureEngine.configuration(
            for: selection,
            screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pixelScale: 1
        )) { error in
            XCTAssertEqual(error as? CaptureEngine.CaptureError, .invalidRegion)
        }
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

private final class CaptureTestScreen: NSScreen {
    var testFrame = CGRect.zero
    var testPixelScale: CGFloat = 1

    override var frame: NSRect { testFrame }
    override var backingScaleFactor: CGFloat { testPixelScale }
}