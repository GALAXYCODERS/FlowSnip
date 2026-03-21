import Cocoa
import SwiftUI
import ScreenCaptureKit

/// The main application delegate. Creates the menu bar status item and
/// coordinates all managers (event tap, overlay, capture).
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private let eventTapManager = EventTapManager()
    private let overlayManager = OverlayWindowManager()
    private let captureEngine = CaptureEngine()
    private var onboardingWindow: NSWindow?

    /// UserDefaults key to track whether onboarding has been completed.
    private let onboardingCompletedKey = "FlowSnip_OnboardingCompleted"

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 FlowSnip: App launched")
        setupStatusBarItem()

        // Register global shortcut (Carbon + NSEvent dual approach)
        setupEventTapManager()

        // Prompt for Accessibility if not yet granted (needed for NSEvent global monitor)
        if !AXIsProcessTrusted() {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
            _ = AXIsProcessTrustedWithOptions(options)
        }

        // Observe capture failures to redirect user to onboarding
        NotificationCenter.default.addObserver(
            forName: .flowSnipCaptureFailure,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showOnboarding()
        }

        if !UserDefaults.standard.bool(forKey: onboardingCompletedKey) {
            showOnboarding()
        } else {
            checkScreenRecording()
        }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        if let existingWindow = onboardingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView {
            // Onboarding complete
            UserDefaults.standard.set(true, forKey: self.onboardingCompletedKey)
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            self.checkScreenRecording()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = NSHostingView(rootView: onboardingView)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        // Bring app to front for onboarding
        NSApp.activate(ignoringOtherApps: true)

        self.onboardingWindow = window
    }

    // MARK: - Status Bar

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "crop", accessibilityDescription: "FlowSnip")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Screen Region", action: #selector(triggerCapture), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Setup Guide…", action: #selector(showOnboardingTapped), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check Permissions…", action: #selector(checkPermissionsTapped), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FlowSnip", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Event Tap

    private func setupEventTapManager() {
        eventTapManager.onShortcutTriggered = { [weak self] in
            DispatchQueue.main.async {
                self?.startCaptureFlow()
            }
        }
        eventTapManager.start()
    }

    // MARK: - Capture Flow

    private func startCaptureFlow() {
        Task {
            let hasScreenRecording = await self.checkScreenRecordingPermission()

            await MainActor.run {
                if !hasScreenRecording {
                    print("⚠️ FlowSnip: Screen Recording permission missing. Cannot capture screen.")
                    showOnboarding()
                    return
                }

                self.overlayManager.showOverlay { [weak self] selectedRect, screen in
                    guard let self = self else { return }

                    self.overlayManager.hideOverlay()

                    // Allow window server time to fully remove overlay from compositing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.captureEngine.capture(rect: selectedRect, screen: screen) { success in
                            DispatchQueue.main.async {
                                if success {
                                    NSHapticFeedbackManager.defaultPerformer.perform(
                                        .generic,
                                        performanceTime: .default
                                    )
                                    self.overlayManager.showClipboardToast(on: screen)
                                }
                                self.overlayManager.dismissOverlay()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Permissions

    private func checkScreenRecording() {
        Task {
            let screenRecordingEnabled = await checkScreenRecordingPermission()
            if !screenRecordingEnabled {
                print("⚠️ FlowSnip: Screen Recording permission required.")
            }
        }
    }

    /// Reliable Screen Recording permission check — consistent with OnboardingView.
    private func checkScreenRecordingPermission() async -> Bool {
        if #available(macOS 14.4, *) {
            return CGPreflightScreenCaptureAccess()
        } else {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return !content.windows.isEmpty
            } catch {
                return false
            }
        }
    }

    // MARK: - Actions

    @objc private func triggerCapture() {
        startCaptureFlow()
    }

    @objc private func showOnboardingTapped() {
        showOnboarding()
    }

    @objc private func checkPermissionsTapped() {
        showOnboarding()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
