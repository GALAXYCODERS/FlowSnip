# Contributing to FlowSnip

Thanks for your interest in contributing to FlowSnip! This guide will help you get started.

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md) in all interactions.

## Development Setup

1. **Fork & clone** the repository:
   ```bash
   git clone https://github.com/<your-username>/FlowSnip.git
   cd FlowSnip
   ```

2. **Open** `FlowSnip.xcodeproj` in **Xcode 27+** with the macOS 27 SDK, on an Apple Silicon Mac running macOS 27 or later.

3. **Build & run** (`⌘R`). The app appears in the menu bar, not the Dock.

4. **Grant permissions** when prompted:
   - **Accessibility** — required for global keyboard shortcut
   - **Screen Recording** — required for screen capture

> **Note:** Xcode resolves pinned MLX/Hugging Face dependencies through Swift Package Manager. Install the Metal compiler with `xcodebuild -downloadComponent MetalToolchain`. No Python runtime, local model server, or third-party build macro is required.

## Capture and AI Tests

Select the shared **FlowSnip** scheme and press `Cmd+U`, or run:

```bash
xcodebuild test -project FlowSnip.xcodeproj -scheme FlowSnip \
   -configuration Debug -destination 'platform=macOS,arch=arm64' \
   -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

The hostless tests compile actual capture/workflow/provider code without launching onboarding. They cover crop geometry, Retina scaling, cancellation, settings persistence, memory thresholds, split SSE frames, completion, and HTTP errors without paid requests. Clipboard tests use a private pasteboard. The live image-only capture check is skipped unless explicitly enabled; it captures an 8-by-6-point region without saving it and checks that the general clipboard remains unchanged.

To opt into that check when Screen Recording permission is already granted to the test process:

```bash
TEST_RUNNER_FLOWSNIP_CAPTURE_SMOKE_TEST=1 xcodebuild test \
   -project FlowSnip.xcodeproj -scheme FlowSnip \
   -configuration Debug -destination 'platform=macOS,arch=arm64' \
   -only-testing:FlowSnipTests/CaptureEngineTests/testLiveImageOnlyCapturePreservesClipboard \
   -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

The test never requests permission itself. Manually verify the normal shortcut, overlay dismissal, clipboard paste, and Retina/external-display capture before shipping. CI uses GitHub's `xcode-27` Apple Silicon preview runner; hosted execution still needs verification on the next workflow run.

### Native AI Validation

The built app has explicit validation commands. `--render-ai-ui` uses generated fixtures and private pasteboards; it does not capture the desktop or call a cloud model. It refreshes the public model catalog and writes native light/dark/settings previews and a result record.

```bash
build/Release/FlowSnip.app/Contents/MacOS/FlowSnip \
   --render-ai-ui --report-directory /tmp/FlowSnip-Validation
```

`--verify-local-ai` downloads the pinned 4B model if needed and runs real local inference on generated code/receipt/chart images. This is an explicit multi-gigabyte download. Use `--offline` to require the existing snapshot and prevent downloads:

```bash
build/Release/FlowSnip.app/Contents/MacOS/FlowSnip \
   --verify-local-ai --offline --report-directory /tmp/FlowSnip-Validation
```

The app's **Check Performance** action provides the same calibration fixtures with progress and cancellation. Reports record model revision, chip/memory, first-token/complete-answer time, and peak MLX memory. Expected-term matching is a basic check, not a substitute for review.

### Package an Update

Run `bash scripts/export-zip.sh` to build, collect license files, sign, verify, and export the app. Then `bash scripts/create-dmg.sh --skip-build` creates a standard noninteractive drag-to-Applications image. Set `FLOWSNIP_DERIVED_DATA` to reuse a validated derived-data directory. Model weights and user preferences are never included in the package.

The default packaging avoids Finder automation. Optional fancy styling is available with `FLOWSNIP_FANCY_DMG=1`, but is not required for an installer.

## Code Style

- Follow standard Swift conventions
- Use `// MARK: -` section headers to organize files
- Keep files focused — one responsibility per file
- No external dependencies unless absolutely necessary

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add multi-selection support
fix: correct Retina scaling on external displays
refactor: simplify overlay window lifecycle
docs: update installation instructions
chore: update .gitignore
```

## Pull Request Process

1. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feat/your-feature
   ```

2. **Keep PRs focused** — one change per pull request.

3. **Ensure the project builds without warnings** in Xcode.

4. **Test on macOS 27+** — run the capture tests and verify the capture shortcut, selection overlay, and clipboard copy all work.

5. **Write a clear PR description** using the provided template.

6. **Update documentation** if your change affects user-facing behavior.

## Reporting Issues

Please use the provided issue templates:

- **Bug Report** — for unexpected behavior, crashes, or visual glitches
- **Feature Request** — for new ideas or improvements

Include your macOS version, steps to reproduce, and screenshots when relevant.

## Architecture Overview

```
FlowSnip/Sources/
├── main.swift              # App entry point
├── AppDelegate.swift       # Lifecycle, menu bar, coordination
├── EventTapManager.swift   # Global shortcut detection (Carbon + NSEvent)
├── OverlayWindowManager.swift  # Multi-screen overlay windows
├── LiquidOverlayView.swift # SwiftUI selection interface
├── CaptureEngine.swift     # Screenshot capture & clipboard
├── CaptureWorkflow.swift   # Typed modes, hotkey/session gates, placement
├── AIConfiguration.swift   # Model recommendations, preferences, Keychain
├── LocalModelRuntime.swift # Offline MLX vision inference
├── LocalModelManager.swift # Downloads, lifecycle, calibration
├── AIProviders.swift       # Cloud streaming, catalog, OCR, image processing
├── AIScanCoordinator.swift # Cancellable assistant sessions
├── AIPresentation.swift    # Native assistant/settings windows
├── AIValidation.swift      # Explicit non-sensitive verification commands
├── OnboardingView.swift    # Permission setup wizard
└── ClipboardToastView.swift # Success notification
```

## Questions?

Open an issue or start a discussion — we're happy to help!
