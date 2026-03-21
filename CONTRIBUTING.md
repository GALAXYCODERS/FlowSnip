# Contributing to FlowSnip

Thanks for your interest in contributing to FlowSnip! This guide will help you get started.

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md) in all interactions.

## Development Setup

1. **Fork & clone** the repository:
   ```bash
   git clone https://github.com/<your-username>/FlowSnip.git
   cd FlowSnip
   ```

2. **Open** `FlowSnip.xcodeproj` in **Xcode 15+**.

3. **Build & run** (`⌘R`). The app appears in the menu bar, not the Dock.

4. **Grant permissions** when prompted:
   - **Accessibility** — required for global keyboard shortcut
   - **Screen Recording** — required for screen capture

> **Note:** FlowSnip has zero external dependencies. No package managers needed.

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

4. **Test on macOS 13+** — verify the capture shortcut, selection overlay, and clipboard copy all work.

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
├── OnboardingView.swift    # Permission setup wizard
└── ClipboardToastView.swift # Success notification
```

## Questions?

Open an issue or start a discussion — we're happy to help!
