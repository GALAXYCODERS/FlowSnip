import SwiftUI
import Cocoa
import ScreenCaptureKit

/// A multi-step onboarding window shown on first launch.
/// Walks the user through: Welcome → Accessibility → Screen Recording → AI Setup → How to Use.
struct OnboardingView: View {
    @ObservedObject var configuration: AIConfiguration
    @ObservedObject var localModels: LocalModelManager
    let catalog: OpenRouterCatalog
    let recorder: AIShortcutRecorder

    @State private var currentStep = 0
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    @State private var permissionMessage: String? = nil
    @State private var permissionMessageIsError = false

    let onComplete: () -> Void

    init(configuration: AIConfiguration, localModels: LocalModelManager, catalog: OpenRouterCatalog,
         recorder: AIShortcutRecorder, initialStep: Int = 0, onComplete: @escaping () -> Void) {
        self.configuration = configuration
        self.localModels = localModels
        self.catalog = catalog
        self.recorder = recorder
        self.onComplete = onComplete
        _currentStep = State(initialValue: initialStep)
    }

    private let totalSteps = 5

    private var aiReady: Bool {
        if configuration.provider == .local {
            guard let model = LocalModelSpec.find(configuration.localModelID) else { return false }
            return configuration.hardware.supports(model) && localModels.downloadedModels.contains(model.id)
        }
        return configuration.cloudConsent && configuration.hasAPIKey && catalog.model(configuration.cloudModelID) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: accessibilityStep
                case 2: screenRecordingStep
                case 3: AISettingsView(configuration: configuration, localModels: localModels,
                                       catalog: catalog, recorder: recorder, isOnboarding: true)
                case 4: howToUseStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Divider()

            bottomBar
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
        }
        .frame(width: 640, height: 640)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .onAppear {
            refreshPermissionStatus()
        }
        .onChange(of: currentStep) {
            permissionMessage = nil
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "scissors")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .blue.opacity(0.3), radius: 12)

            Text("Welcome to FlowSnip")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Capture to your clipboard or analyze a selected\nregion with local or cloud AI.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            VStack(spacing: 10) {
                featureRow(icon: "keyboard", text: "Screenshot: " + ShortcutChord.screenshot.label)
                featureRow(icon: "sparkles", text: "AI Scan: " + configuration.aiShortcut.label)
                featureRow(icon: "crop", text: "Drag to select any region")
                featureRow(icon: "doc.on.clipboard", text: "Screenshots copy instantly to clipboard")
            }

            Spacer()
        }
        .padding(36)
    }

    private func featureRow(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.secondary)
    }

    // MARK: - Step 2: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.blue)
                .shadow(color: .blue.opacity(0.3), radius: 12)

            Text("Accessibility Permission")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("FlowSnip needs Accessibility access to detect\nyour keyboard shortcut globally — even when\nother apps are in focus.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            if accessibilityGranted {
                permissionGrantedBadge("Accessibility granted!")
            } else {
                VStack(spacing: 14) {
                    stepsCard(steps: [
                        "Click \"Open System Settings\" below",
                        "Find  FlowSnip  in the list",
                        "If you see multiple FlowSnip entries, remove old ones first (select \u{2192} minus button)",
                        "Toggle it  ON",
                        "Come back and click \"Verify Permission\""
                    ])

                    HStack(spacing: 12) {
                        Button("Open System Settings") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Verify Permission") {
                            verifyAccessibility()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let message = permissionMessage {
                        Label(message, systemImage: permissionMessageIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(permissionMessageIsError ? .red : .green)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .animation(.easeOut(duration: 0.2), value: permissionMessage)
                    }
                }
            }

            Spacer()
        }
        .padding(36)
    }

    // MARK: - Step 3: Screen Recording

    private var screenRecordingStep: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.purple)
                .shadow(color: .purple.opacity(0.3), radius: 12)

            Text("Screen Recording Permission")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("FlowSnip needs Screen Recording access to\ncapture the region you select on screen.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            if screenRecordingGranted {
                permissionGrantedBadge("Screen Recording granted!")
            } else {
                VStack(spacing: 14) {
                    stepsCard(steps: [
                        "Click \"Open System Settings\" below",
                        "Find  FlowSnip  in the list",
                        "Toggle it  ON",
                        "You may need to quit & reopen the app",
                        "Come back and click \"Verify Permission\""
                    ])

                    HStack(spacing: 12) {
                        Button("Open System Settings") {
                            openScreenRecordingSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)

                        Button("Verify Permission") {
                            verifyScreenRecording()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let message = permissionMessage {
                        Label(message, systemImage: permissionMessageIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(permissionMessageIsError ? .red : .green)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .animation(.easeOut(duration: 0.2), value: permissionMessage)
                    }
                }
            }

            Spacer()
        }
        .padding(36)
    }

    // MARK: - Step 4: How to Use

    private var howToUseStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange, .pink],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .orange.opacity(0.3), radius: 12)

            Text("You're All Set!")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            VStack(spacing: 12) {
                Text("Try your shortcut now:")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                HStack(spacing: 5) {
                    keyCapView("\u{2318}")
                    keyCapView("\u{21E7}")
                    keyCapView("2")
                }

                Text("Press  \u{2318} + Shift + 2  to test it!")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                    )
            )

            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                howToRow(icon: "command", iconColor: .blue,
                         title: "\u{2318} + Shift + 2",
                         subtitle: "Instantly opens the capture overlay")
                howToRow(icon: "rectangle.dashed", iconColor: .purple,
                         title: "Click and drag to select",
                         subtitle: "A liquid glass box follows your cursor")
                howToRow(icon: "doc.on.clipboard.fill", iconColor: .green,
                         title: "Release to copy",
                         subtitle: "Image goes straight to your clipboard")
                howToRow(icon: "escape", iconColor: .gray,
                         title: "Esc — Cancel",
                         subtitle: "Dismiss without capturing")
                howToRow(icon: "sparkles", iconColor: .mint,
                         title: configuration.aiShortcut.label,
                         subtitle: aiReady ? "AI Scan opens an assistant for your crop" : "Finish AI setup later in AI Settings")
            }

            Spacer()

            Text("FlowSnip lives in your menu bar  \u{2702}\u{FE0F}")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(32)
    }

    private func keyCapView(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
            )
    }

    // MARK: - Shared Components

    private func permissionGrantedBadge(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.green)
            .padding(.vertical, 8)
    }

    private func stepsCard(steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 18, alignment: .trailing)
                    Text(step)
                        .font(.system(size: 13))
                        .foregroundColor(.primary.opacity(0.8))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func howToRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step == currentStep ? Color.accentColor : Color.primary.opacity(0.2))
                        .frame(width: 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: currentStep)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                if currentStep < totalSteps - 1 {
                    if currentStep == 3 {
                        Button("Set Up Later") { withAnimation { currentStep += 1 } }
                            .buttonStyle(.borderless)
                    }
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(currentStep == 3 && !aiReady)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
        }
    }

    // MARK: - Permission Verification

    private func refreshPermissionStatus() {
        accessibilityGranted = AXIsProcessTrusted()
        Task {
            let granted = await checkScreenRecordingPermission()
            await MainActor.run {
                screenRecordingGranted = granted
            }
        }
    }

    private func verifyAccessibility() {
        // Prompt the system dialog if not yet trusted
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let granted = AXIsProcessTrustedWithOptions(options) as Bool
        withAnimation {
            accessibilityGranted = granted
            if granted {
                permissionMessage = "Accessibility is enabled!"
                permissionMessageIsError = false
            } else {
                permissionMessage = "Not yet enabled. If you see multiple FlowSnip entries, remove old ones first, then toggle ON the correct one."
                permissionMessageIsError = true
            }
        }
    }

    private func verifyScreenRecording() {
        Task {
            await requestScreenRecordingPermission()
            let granted = await checkScreenRecordingPermission()
            await MainActor.run {
                withAnimation {
                    screenRecordingGranted = granted
                    if granted {
                        permissionMessage = "Screen Recording is enabled!"
                        permissionMessageIsError = false
                    } else {
                        permissionMessage = "Not yet enabled \u{2014} toggle FlowSnip ON, then restart the app"
                        permissionMessageIsError = true
                    }
                }
            }
        }
    }

    private func requestScreenRecordingPermission() async {
        CGRequestScreenCaptureAccess()
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func checkScreenRecordingPermission() async -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Ready Screen (shown on restart when all permissions granted)

struct ReadyScreenView: View {

    let onDismiss: () -> Void

    @State private var arrowOffset: CGFloat = 0
    @State private var arrowOpacity: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                // Animated arrow pointing up to menu bar
                VStack(spacing: 6) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.accentColor.opacity(0.6))
                        .offset(y: arrowOffset - 8)
                        .opacity(arrowOpacity * 0.5)

                    Image(systemName: "chevron.up")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.accentColor.opacity(0.8))
                        .offset(y: arrowOffset - 4)
                        .opacity(arrowOpacity * 0.75)

                    Image(systemName: "chevron.up")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.accentColor)
                        .offset(y: arrowOffset)
                        .opacity(arrowOpacity)
                }
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                    ) {
                        arrowOffset = -8
                        arrowOpacity = 0.7
                    }
                }

                Text("Look up at your menu bar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Divider()
                    .padding(.horizontal, 48)

                // Status badge
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .green.opacity(0.3), radius: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FlowSnip is ready!")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("All permissions are set up.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }

                // Menu bar hint
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "crop")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.1))
                            )

                        Text("You'll find the FlowSnip icon (\u{2702}) in your Mac menu bar.")
                            .font(.system(size: 13))
                            .foregroundColor(.primary.opacity(0.75))
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.1))
                            )

                        HStack(spacing: 4) {
                            Text("Press")
                                .font(.system(size: 13))
                                .foregroundColor(.primary.opacity(0.75))
                            Text("\u{2318}+\u{21E7}+2")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.blue)
                            Text("to capture a region.")
                                .font(.system(size: 13))
                                .foregroundColor(.primary.opacity(0.75))
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.04))
                )

            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("Got it") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: 480, height: 460)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
    }
}

// MARK: - NSVisualEffectView wrapper for SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
