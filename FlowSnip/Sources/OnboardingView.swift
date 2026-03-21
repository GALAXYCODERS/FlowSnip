import SwiftUI
import Cocoa
import ScreenCaptureKit

/// A multi-step onboarding window shown on first launch.
/// Walks the user through: Welcome → Accessibility Permission → Screen Recording Permission → How to Use.
struct OnboardingView: View {

    @State private var currentStep = 0
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    @State private var permissionMessage: String? = nil
    @State private var permissionMessageIsError = false

    let onComplete: () -> Void

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: accessibilityStep
                case 2: screenRecordingStep
                case 3: howToUseStep
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

            // Bottom bar with dots & buttons
            bottomBar
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
        }
        .frame(width: 600, height: 520)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .onAppear {
            refreshPermissionStatus()
        }
        .onChange(of: currentStep) { _ in
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

            Text("A lightning-fast screen capture tool\nthat copies directly to your clipboard.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            VStack(spacing: 10) {
                featureRow(icon: "keyboard", text: "Press  ⌘ + Shift + 2  to capture")
                featureRow(icon: "crop", text: "Drag to select any region")
                featureRow(icon: "doc.on.clipboard", text: "Instantly copied to clipboard")
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
                        "If you see multiple FlowSnip entries, remove old ones first (select → minus button)",
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

                    // Feedback message
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

                    // Feedback message
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

            // Shortcut test area
            VStack(spacing: 12) {
                Text("Try your shortcut now:")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                HStack(spacing: 5) {
                    keyCapView("⌘")
                    keyCapView("⇧")
                    keyCapView("2")
                }

                Text("Press  ⌘ + Shift + 2  to test it!")
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
                         title: "⌘ + Shift + 2",
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
            }

            Spacer()

            Text("FlowSnip lives in your menu bar  ✂️")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(32)
    }

    /// A single keyboard key cap visual.
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
            // Step indicators
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
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
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
        // Screen recording check is async
        Task {
            let granted = await checkScreenRecordingPermission()
            await MainActor.run {
                screenRecordingGranted = granted
            }
        }
    }

    private func verifyAccessibility() {
        let granted = AXIsProcessTrusted()
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
            // First explicitly request it so the prompt appears if needed
            await requestScreenRecordingPermission()
            
            let granted = await checkScreenRecordingPermission()
            await MainActor.run {
                withAnimation {
                    screenRecordingGranted = granted
                    if granted {
                        permissionMessage = "Screen Recording is enabled!"
                        permissionMessageIsError = false
                    } else {
                        permissionMessage = "Not yet enabled — toggle FlowSnip ON, then restart the app"
                        permissionMessageIsError = true
                    }
                }
            }
        }
    }

    /// Explicitly requests permission, forcing the OS prompt to appear.
    private func requestScreenRecordingPermission() async {
        if #available(macOS 14.4, *) {
            CGRequestScreenCaptureAccess()
        } else {
            // Legacy way to force the prompt on macOS 13/14: request a display stream
            if let display = CGMainDisplayID() as CGDirectDisplayID? {
                let _ = CGDisplayStream(
                    display: display,
                    outputWidth: 1,
                    outputHeight: 1,
                    pixelFormat: Int32(kCVPixelFormatType_32BGRA),
                    properties: nil,
                    handler: { _, _, _, _ in }
                )
            }
        }
        
        // Give the OS a tiny fraction of a second to register the prompt
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    /// Reliable Screen Recording permission check.
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

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
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
