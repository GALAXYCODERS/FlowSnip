import Cocoa
import SwiftUI
import ScreenCaptureKit

/// The main application delegate. Creates the menu bar status item and
/// coordinates all managers (event tap, overlay, capture).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private let eventTapManager = EventTapManager()
    private let overlayManager = OverlayWindowManager()
    private let captureEngine = CaptureEngine()
    private var onboardingWindow: NSWindow?
    private var aiConfiguration: AIConfiguration?
    private var localModels: LocalModelManager?
    private var cloudCatalog: OpenRouterCatalog?
    private var scanCoordinator: AIScanCoordinator?
    private var aiWindows: AIWindowManager?
    private var captureTask: Task<Void, Never>?
    private var captureGate = ScanSessionGate()
    private var configurationObserver: NSObjectProtocol?
    private var recordedPreviousShortcut: ShortcutChord?
    private var lastShortcutError: String?

    /// UserDefaults key to track whether onboarding has been completed.
    private let onboardingCompletedKey = "FlowSnip_OnboardingCompleted"
    /// UserDefaults key to track screenshot count.
    private let screenshotCountKey = "FlowSnip_ScreenshotCount"

    private var statsMenuItem: NSMenuItem?

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
            guard let self else { return }
            DispatchQueue.main.async { self.showOnboarding() }
        }

        showStartupScreen()
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureTask?.cancel()
        captureGate.cancel()
        overlayManager.dismissOverlay(animated: false)
        eventTapManager.stop()
        aiWindows?.shutdown()
        localModels?.cancelDownload()
        localModels?.cancelCalibration()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    // MARK: - Startup Screen

    private func showStartupScreen() {
        Task {
            let axGranted = AXIsProcessTrusted()
            let screenGranted = await checkScreenRecordingPermission()

            await MainActor.run {
                if axGranted && screenGranted && UserDefaults.standard.bool(forKey: "FlowSnip_AI_OnboardingCompleted") {
                    showReadyScreen()
                } else {
                    showOnboarding()
                }
            }
        }
    }

    private func showReadyScreen() {
        if let existingWindow = onboardingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let readyView = ReadyScreenView {
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
        }

        let hostingView = NSHostingView(rootView: readyView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        if let existingWindow = onboardingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        _ = prepareAI()
        guard let configuration = aiConfiguration, let models = localModels, let catalog = cloudCatalog else { return }
        let recorder = AIShortcutRecorder(configuration: configuration) { [weak self] active in
            self?.shortcutRecordingChanged(active)
        }
        let onboardingView = OnboardingView(configuration: configuration, localModels: models, catalog: catalog, recorder: recorder) {
            // Onboarding complete
            UserDefaults.standard.set(true, forKey: self.onboardingCompletedKey)
            UserDefaults.standard.set(true, forKey: "FlowSnip_AI_OnboardingCompleted")
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            self.checkScreenRecording()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
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
        menu.addItem(NSMenuItem(title: "AI Scan", action: #selector(triggerAIScan), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "AI Settings...", action: #selector(showAISettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let statsView = StatsMenuItemView(frame: NSRect(x: 0, y: 0, width: 220, height: 32))
        statsView.count = UserDefaults.standard.integer(forKey: screenshotCountKey)
        let stats = NSMenuItem()
        stats.view = statsView
        statsMenuItem = stats
        menu.addItem(stats)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Setup Guide…", action: #selector(showOnboardingTapped), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check Permissions…", action: #selector(checkPermissionsTapped), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FlowSnip", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Event Tap

    private func setupEventTapManager() {
        if let data = UserDefaults.standard.data(forKey: "FlowSnip_AI_Shortcut"), let chord = try? JSONDecoder().decode(ShortcutChord.self, from: data) {
            eventTapManager.updateAIShortcut(chord)
        }
        eventTapManager.onActionTriggered = { [weak self] mode in
            guard let self else { return }
            DispatchQueue.main.async { self.startCaptureFlow(mode: mode) }
        }
        eventTapManager.onRegistrationError = { [weak self] message in
            guard let self else { return }
            DispatchQueue.main.async {
                self.lastShortcutError = message
                self.aiConfiguration?.shortcutError = message
            }
        }
        configurationObserver = NotificationCenter.default.addObserver(forName: .flowSnipAIConfigurationChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let configuration = self.aiConfiguration else { return }
                self.scanCoordinator?.configurationChanged()
                guard self.recordedPreviousShortcut == nil else { return }
                if !self.eventTapManager.updateAIShortcut(configuration.aiShortcut) {
                    configuration.aiShortcut = self.eventTapManager.aiShortcut
                }
            }
        }
        eventTapManager.start()
    }

    // MARK: - Capture Flow

    private func startCaptureFlow(mode: CaptureMode = .screenshot) {
        captureTask?.cancel()
        captureGate.cancel()
        overlayManager.dismissOverlay(animated: false)
        aiWindows?.closeAssistant()
        if mode == .aiScan {
            let windows = prepareAI()
            do { try scanCoordinator?.checkReadiness() }
            catch {
                windows.showSettings()
                return
            }
        }
        guard CGPreflightScreenCaptureAccess() else {
            showOnboarding()
            return
        }
        let identifier = captureGate.begin()
        overlayManager.showOverlay(mode: mode) { [weak self] selectedRect, screen in
            guard let self, self.captureGate.contains(identifier) else { return }
            self.captureGate.advance(identifier, to: .capturing)
            self.overlayManager.hideOverlay()
            self.overlayManager.dismissOverlay(animated: false)
            self.captureTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: .milliseconds(80))
                    let image = try await self.captureEngine.captureImage(rect: selectedRect, screen: screen)
                    try Task.checkCancellation()
                    guard self.captureGate.contains(identifier) else { return }
                    self.captureGate.cancel()
                    if mode == .screenshot {
                        if self.captureEngine.copyToClipboard(image) {
                            self.incrementScreenshotCount()
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                            self.overlayManager.showClipboardToast(on: screen)
                        } else {
                            self.showCaptureError(AIError.message("The image could not be copied to the clipboard."))
                        }
                    } else {
                        self.scanCoordinator?.begin(image: image)
                        self.aiWindows?.showAssistant(near: selectedRect, on: screen)
                    }
                } catch is CancellationError {} catch {
                    guard self.captureGate.contains(identifier) else { return }
                    self.captureGate.cancel()
                    if !CGPreflightScreenCaptureAccess() { self.showOnboarding() }
                    else { self.showCaptureError(error) }
                }
            }
        }
        overlayManager.onDismiss = { [weak self] in
            guard let self, self.captureGate.contains(identifier), self.captureGate.phase == .selecting else { return }
            self.captureGate.cancel()
            self.captureTask?.cancel()
        }
    }

    private func prepareAI() -> AIWindowManager {
        if let aiWindows { return aiWindows }
        let configuration = AIConfiguration()
        configuration.shortcutError = lastShortcutError
        let models = LocalModelManager(hardware: configuration.hardware)
        let catalog = OpenRouterCatalog(storageDirectory: models.storageDirectory)
        let coordinator = AIScanCoordinator(configuration: configuration, localModels: models, catalog: catalog)
        let windows = AIWindowManager(coordinator: coordinator)
        windows.onNewScan = { [weak self] in self?.startCaptureFlow(mode: .aiScan) }
        windows.onShortcutRecordingChanged = { [weak self] active in self?.shortcutRecordingChanged(active) }
        aiConfiguration = configuration
        localModels = models
        cloudCatalog = catalog
        scanCoordinator = coordinator
        aiWindows = windows
        return windows
    }

    private func shortcutRecordingChanged(_ active: Bool) {
        if active {
            recordedPreviousShortcut = eventTapManager.aiShortcut
            eventTapManager.stop()
        } else if let previous = recordedPreviousShortcut, let configuration = aiConfiguration {
            let requested = configuration.aiShortcut
            recordedPreviousShortcut = nil
            eventTapManager.updateAIShortcut(previous)
            eventTapManager.start()
            if !eventTapManager.updateAIShortcut(requested) { configuration.aiShortcut = previous }
        }
    }

    private func showCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Capture could not be completed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

    @objc private func triggerAIScan() { startCaptureFlow(mode: .aiScan) }

    @objc private func showAISettings() { prepareAI().showSettings() }

    @objc private func showOnboardingTapped() {
        showOnboarding()
    }

    @objc private func checkPermissionsTapped() {
        showOnboarding()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Stats

    private func incrementScreenshotCount() {
        let current = UserDefaults.standard.integer(forKey: screenshotCountKey)
        let newCount = current + 1
        UserDefaults.standard.set(newCount, forKey: screenshotCountKey)
        (statsMenuItem?.view as? StatsMenuItemView)?.count = newCount
    }
}

// MARK: - Stats Menu Item View

private final class StatsMenuItemView: NSView {

    var count: Int = 0 {
        didSet { updateCount() }
    }

    private let iconView   = NSImageView()
    private let labelView  = NSTextField(labelWithString: "Screenshots")
    private let badgeBack  = NSView()
    private let badgeLabel = NSTextField(labelWithString: "0")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // Icon
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Label
        labelView.font = .systemFont(ofSize: 12, weight: .medium)
        labelView.textColor = .secondaryLabelColor
        labelView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelView)

        // Badge background
        badgeBack.wantsLayer = true
        badgeBack.layer?.cornerRadius = 8
        badgeBack.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        badgeBack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeBack)

        // Badge count label
        badgeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        badgeLabel.textColor = .controlAccentColor
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeBack.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            labelView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            labelView.centerYAnchor.constraint(equalTo: centerYAnchor),

            badgeBack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            badgeBack.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeBack.heightAnchor.constraint(equalToConstant: 18),
            badgeBack.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),

            badgeLabel.leadingAnchor.constraint(equalTo: badgeBack.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeBack.trailingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeBack.centerYAnchor),
        ])

        updateCount()
    }

    private func updateCount() {
        badgeLabel.stringValue = "\(count)"
        // Slightly dim when zero
        badgeBack.layer?.backgroundColor = count == 0
            ? NSColor.tertiaryLabelColor.withAlphaComponent(0.12).cgColor
            : NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        badgeLabel.textColor = count == 0 ? .tertiaryLabelColor : .controlAccentColor
    }
}
