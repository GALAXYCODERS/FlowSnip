<div align="center">

<img src="assets/icon.png" alt="FlowSnip Icon" width="128">

### Screen capture and local-first AI scanning for macOS.
**Snip it. Copy it. Paste it. Done.**

[![macOS 27.0+](https://img.shields.io/badge/macOS-27.0%2B-black?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/GALAXYCODERS/FlowSnip/build.yml?style=flat-square&label=build)](https://github.com/GALAXYCODERS/FlowSnip/actions)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](CONTRIBUTING.md)

<video src="assets/FlowSnipDemo2HighRes.mp4" width="800" autoplay loop muted playsinline></video>

<br>

[Download](#download) · [Features](#features) · [Usage](#usage) · [Contributing](CONTRIBUTING.md)

</div>

---

## Why FlowSnip?

macOS has built-in screenshot tools — so why FlowSnip?

| | macOS Screenshot (⌘⇧4) | FlowSnip (⌘⇧2) |
|---|---|---|
| **Output** | Saves a file to Desktop | Copies directly to clipboard |
| **Workflow** | Screenshot → Find file → Drag into app | Screenshot → ⌘V → Done |
| **Selection UI** | Basic crosshair | Liquid glass overlay with glow effects |
| **Feedback** | Camera shutter sound | Haptic feedback + animated toast |
| **Extra steps** | 0-2 clicks to reach clipboard | Zero — it's already there |

FlowSnip is built for people who screenshot to **paste**, not to **save**.

---

## Features

<table>
<tr>
<td width="50%">

**Instant Clipboard Capture**
Press `⌘ + Shift + 2` from anywhere — your selection goes straight to the clipboard. No files, no dialogs, just `⌘V` to paste.

</td>
<td width="50%">

**Liquid Glass Selection**
Beautiful frosted glass overlay with rounded corners, glow effects, and an inverted mask that puts your selection front and center.

</td>
</tr>
<tr>
<td>

**Multi-Monitor Support**
Each connected display gets its own selection overlay, including displays arranged left, right, above, or below the main screen. Each selection stays within the display where the drag starts, with that display's pixel scaling.

</td>
<td>

**Silent & Lightweight**
Runs as a menu bar agent with no Dock icon. Ordinary screenshots do not load an AI model or contact AI services; local model weights are downloaded separately.

</td>
</tr>
<tr>
<td>

**Polished Details**
Haptic feedback on capture, animated "Copied!" toast, live size indicator during selection, smart corner radius scaling.

</td>
<td>

**Guided Onboarding**
First-launch wizard walks you through Accessibility, Screen Recording, and local or OpenRouter AI setup. AI setup can be deferred without blocking screenshots.

</td>
</tr>
</table>

### AI Scan

`Command + Option + Shift + 2` opens a distinct mint-white animated selection. Release to analyze the crop in a compact native assistant panel. Ask follow-up questions, copy the answer or image, translate captured text, or switch to the separate Vision OCR tab. AI scans leave the clipboard untouched until a copy action is selected.

First launch includes AI setup alongside permissions. Existing users see the expanded guide once after updating. Choose **Set Up Later** to keep using screenshots, or configure AI immediately. Settings remain available from **AI Settings** in the menu bar:

1. **On This Mac:** FlowSnip reads the chip, unified memory, Metal working-set budget, and OS locally. It recommends a pinned 4-bit vision model; confirm its download before use. An M4/M5 with 16 GB starts with Qwen3.5 4B. Larger-memory Macs can choose 9B, while the 27B profile is an optional larger-memory candidate.
2. **OpenRouter:** Enable cloud processing, enter your own key into the secure field, and explicitly select an image-capable model. GPT-6 Luna and Gemini 3.8 Flash are suggestions; the searchable catalog includes other choices. Keys are stored in Keychain, not preferences.
3. **Shortcut:** Record a custom AI shortcut or reset to the default. The screenshot shortcut stays unchanged.

Models are stored in `~/Library/Application Support/FlowSnip/Models`, not inside the installer. Downloads can be paused/resumed or removed; **Check Performance** uses generated error, receipt, and chart fixtures. The local runtime unloads after inactivity or memory pressure. No provider/model substitution or local-to-cloud fallback occurs silently.

The first local request may take several seconds while the model loads. Small local models can misread or misinterpret content; check extracted text and important numbers before relying on an answer. Calibration reports are workload-specific checks, not accuracy guarantees.

**What the AI receives:** Both local and OpenRouter vision models receive the selected crop as an image, your question, and bounded conversation history. Large crops are resized proportionally to a maximum dimension of 1600 pixels. The separate **Extracted Text** tab uses Apple's on-device Vision OCR; that OCR output is not sent as a replacement for the image or appended to AI requests. For cloud scans, only the crop is uploaded, never the entire screen.

Answers render Markdown lists, tables, code blocks, and LaTeX equations using bundled offline libraries. Rendering does not contact a CDN or load remote images, and model-supplied HTML/scripts are not executed. **Copy Answer** copies the original Markdown/LaTeX text.

**Keychain prompts:** The first cloud scan or verification unlocks the saved key once; FlowSnip then reuses it in memory for the rest of the running app session. Subsequent scans and follow-ups do not read Keychain again. Saving a key makes it immediately usable in the current session; replacement/removal updates the cache and invalidates an assistant using the old credential. The key is not written to preferences or an unprotected file. Checking whether a key is saved uses noninteractive metadata, not the secret.

macOS may still request authorization after FlowSnip quits/restarts or an ad-hoc-signed build is replaced. This is a macOS dialog asking for the login Keychain password, usually your Mac login password, not the OpenRouter API key. Only grant access to a build you trust. Local scans need no API key or Keychain authorization. A stable Developer ID signing identity is the longer-term solution for consistent access across app updates.

---

## Download

### Direct (ZIP)

Download the latest `FlowSnip.zip` from the [Releases](../../releases) page, then run this in your Terminal:

```bash
cd ~/Downloads && \
unzip FlowSnip.zip && \
mv FlowSnip.app /Applications/ && \
xattr -dr com.apple.quarantine /Applications/FlowSnip.app && \
open /Applications/FlowSnip.app && \
echo "✓ FlowSnip installed and launched"
```

> FlowSnip is not notarized (no Apple Developer account). The `xattr` command removes the macOS quarantine flag — this is normal for apps distributed outside the App Store.

### Update an Existing Installation

Quit the running FlowSnip from its menu-bar menu. Open the new DMG, drag FlowSnip to Applications, and replace the old app; alternatively replace it with the app from the ZIP. Launch the replacement. Screenshot counts, AI preferences, and separately downloaded models remain in place. Screen Recording or Accessibility may need to be re-enabled for the updated ad-hoc-signed app.

The 2.0 update requires macOS 27 and Apple Silicon. Older machines should retain the prior release. Local AI additionally requires at least 16 GB unified memory. The application is ad-hoc signed, not Developer ID notarized; only remove quarantine for a build you trust.

### Build from Source

**Prerequisites:** Xcode 27+ with the macOS 27 SDK, macOS 27.0 or later, and an Apple Silicon Mac.

Install Apple's Metal compiler with `xcodebuild -downloadComponent MetalToolchain` if it is not already present. Xcode resolves the exact Swift package versions in the checked-in package lockfile. No third-party macro approval or macro-validation bypass is required.

```bash
git clone https://github.com/GALAXYCODERS/FlowSnip.git
cd FlowSnip
open FlowSnip.xcodeproj
```

1. Select the **FlowSnip** scheme and your Mac as the run destination
2. Press `⌘R` to build and run
3. Look for the crop icon in your **menu bar** (not the Dock)
4. Follow the onboarding wizard to grant permissions

---

## Usage

| Shortcut | Action |
|---|---|
| `⌘ + Shift + 2` | Start capture |
| `Command + Option + Shift + 2` | Start AI scan (configurable) |
| Click + Drag | Select screen region |
| Release | Capture & copy to clipboard |
| `Esc` | Cancel capture |
| `⌘ + V` | Paste your capture anywhere |

**Three steps:** Press `⌘⇧2` → Drag to select → Release. Done — it's on your clipboard.

---

## System Requirements

- **macOS 27.0** or later
- **Apple Silicon** Mac running natively
- **16 GB unified memory** or more for local AI
- **Accessibility** permission — for global keyboard shortcut detection
- **Screen Recording** permission — for capturing screen content

---

## Tech Stack

| | |
|---|---|
| **Language** | Swift 6 toolchain, Swift 5 language mode |
| **UI** | AppKit + SwiftUI |
| **Capture** | ScreenCaptureKit · CoreGraphics coordinates |
| **Keyboard** | Carbon Hot Keys + NSEvent Monitors |
| **Local Inference** | Pinned MLX Swift vision runtime + Hugging Face tokenizer/download libraries |
| **Cloud** | Optional user-selected OpenRouter model via URLSession |
| **Text Extraction** | Apple Vision |

<details>
<summary><strong>Architecture Overview</strong></summary>

```
FlowSnip/Sources/
├── main.swift                 # App entry point
├── AppDelegate.swift          # Lifecycle, menu bar, coordination
├── EventTapManager.swift      # Global shortcut (Carbon + NSEvent dual)
├── OverlayWindowManager.swift # Multi-screen overlay windows & toast
├── LiquidOverlayView.swift    # SwiftUI selection with drag gestures
├── CaptureEngine.swift        # ScreenCaptureKit image capture & explicit clipboard delivery
├── CaptureWorkflow.swift      # Capture modes, shortcut/session gates, placement
├── AIConfiguration.swift      # Hardware/model catalog, preferences, Keychain
├── LocalModelRuntime.swift    # Offline native MLX vision inference
├── LocalModelManager.swift    # Confirmed downloads, lifecycle, calibration
├── AIProviders.swift          # OpenRouter streaming/catalog, OCR, image encoding
├── AIScanCoordinator.swift    # Cancelled/stale session protection and follow-ups
├── AIPresentation.swift       # Native assistant, settings, shortcut recorder
├── AIValidation.swift         # Explicit synthetic validation commands
├── OnboardingView.swift       # Permission setup wizard
└── ClipboardToastView.swift   # Animated success notification
```

</details>

---

## Contributing

Contributions are welcome! Check out the [Contributing Guide](CONTRIBUTING.md) to get started.

The shared **FlowSnip** scheme includes hostless tests for capture, shortcuts, settings, model eligibility, image encoding, and streaming transport. Run it with `Cmd+U` in Xcode; the opt-in live screen check is skipped by default. See the [validation record](VALIDATION.md) for measured release checks and unverified environments.

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

---

## License

FlowSnip is released under the [MIT License](LICENSE).

Third-party runtime licenses are bundled with the application; see [ThirdPartyNotices.md](FlowSnip/Resources/ThirdPartyNotices.md). Model weights have their own licenses and are not bundled.

---

<div align="center">

Built by [Christian Homborg](https://github.com/GALAXYCODERS)

If you find FlowSnip useful, consider giving it a star — it helps others discover the project.

</div>
