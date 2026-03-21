# MacOS Liquid Glass Snip Tool: Perfected Implementation Plan

This document serves as the absolute "source of truth" and blueprint for an AI agent to build the MacOS native snipping tool. The application is designed to be as fast and fluid as Windows' `Win + Shift + S`, but natively optimized for macOS and streamlined specifically for pasting into AI chat interfaces (Claude, Gemini).

## 1. Goal Description
Create a lightweight, background-running macOS screen capture app. 
**Key Requirements:**
- **Zero-Friction Trigger:** Long-tap (2 seconds) on the Escape key or Up Arrow key.
- **Immediate Feedback:** A completely custom, liquid glass frosted overlay instantly appears on all connected displays.
- **Snip & Send:** Click-and-drag an area, which instantly gets copied to the macOS Clipboard (`NSPasteboard`) as a clean image, ready for AI tools. No saving to disk, no extra metadata.
- **Aesthetic:** Beautiful, high-end "native liquid glass" user interface with physics-based drag interactions and refraction effects.

## 2. Frameworks and Tech Stack
To achieve low-level keyboard interception and high-performance cross-display frosted windows, the app must be built entirely natively using Apple's modern swift frameworks.

*   **Swift 6 / macOS 13.0+ Minimum Target**
*   **AppKit:** Crucial for managing global `NSWindow` levels, multi-monitor window spawning, and menu bar item logic.
*   **SwiftUI:** Used specifically to render the overlay UI, drawing the selection shapes, and applying `.ultraThinMaterial` and glassmorphic shaders.
*   **CoreGraphics / ApplicationServices:** Required for `CGEventTap` to globally intercept the keyboard events.
*   **ScreenCaptureKit (or CoreGraphics):** For the actual screen region grabbing.
*   **Combine/Concurrency:** For managing state between the Event Tap and the UI thread.

## 3. Project Configuration & App Lifecycle
The building agent should configure the project as follows:
- **Project Structure:** Standard Xcode macOS App project or purely programmatic setup.
- **Version Control:** Initialize a local git repository, create a new **Private GitHub Repository** (e.g., via `gh repo create --private`), and push the initial codebase.
- **Target App Type:** "Agent" Application. 
  - Set `LSUIElement` to `YES` in `Info.plist`. This hides the app from the Dock and Force Quit menu. It runs completely in the background via the Menu Bar.
- **Permissions Required:** 
  - `Accessibility`: To use `CGEventTap` globally. The app MUST request this permission on the first launch.
  - `Screen Recording`: To use `ScreenCaptureKit` or `CGDisplayCreateImage`. The app MUST request this on the first launch.

---

## 4. Proposed Architecture & Implementation Steps

### Feature A: Global Input Interception (`EventTapManager`)
We need to track a "Long Press" on a target key without entirely breaking normal typing. 

> [!WARNING]
> Delaying key events to check for a long press inherently adds input lag to that key because the OS must wait to see if you release the key quickly. We will use a much shorter duration (0.4s). Alternatively, we highly recommend a standard global shortcut (e.g., `Cmd + Shift + X` or a double-tap).

- **Target Keys:** Escape (Keycode 53) or Up Arrow (Keycode 126). 
*(Note: Touch ID cannot be natively intercepted as it is handled by the Secure Enclave, so Escape is the standard target for "top left".)*
- **Mechanism:** Create a `CGEvent.tapCreate` anchored at `.headInsertEventTap`. Listen for `.keyDown` and `.keyUp`.
- **Logic:** 
  1. On `keyDown`, record the timestamp and swallow the event temporarily. 
  2. Start an async wrapper/timer. If a `keyUp` arrives before **0.4 seconds**, stop the timer and synchronously dispatch the original `keyDown` followed by the `keyUp` to the OS. (This preserves normal key function but adds up to 0.4s lag).
  3. If 0.4 seconds pass and no `keyUp` was received, consider the long press **Triggered**. Dispatch a command to open the Capture Overlay.

### Feature B: High-Performance Glass Overlay (`OverlayWindowManager`)
When triggered, a window must spawn covering the entire screen (or multiple screens if multi-monitor).
- **Window Hierarchy:** Instantiate a borderless `NSWindow` set to `level = .screenSaver` or `.popUpMenu` so it floats above all other application windows and menus.
- **Backdrop Styling (Frosted Glass):** Use an `NSVisualEffectView` behind the root SwiftUI view. Configure it to use `.behindWindow` blending and `.dark` or `.vibrantDark` material to subtly dim and blur the underlying desktop.
- **Cross-Screen Support:** Loop through `NSScreen.screens` and spawn an explicitly sized overlay window on *each* active display so the user can drag their snip anywhere.

### Feature C: Liquid Selection User Interface (`LiquidOverlayView.swift`)
The core visual experience of the app.
- **Gestures:** A SwiftUI view with a `.gesture(DragGesture())` covering the window.
- **Drawing the Snip Mask:** As the user drags, maintain `startLocation` and `currentLocation`. Create a custom Swift Shape to calculate the `CGRect`.
- **Liquid Design Aesthetics:** 
  - Do NOT just draw a static dashed line.
  - Render an inner shadow, a highly rounded corner radius (e.g., `12.0` to `24.0` depending on area), and a crisp 1px bright white semi-transparent ring around the selection box.
  - Apply an inverted mask so that an `.ultraThinMaterial` blurs everything *outside* the selection, allowing the interior of the rect to show the crisp, unblurred screen beneath.
  - *Bonus for the AI:* Add subtle scale or refraction animations when the drag is active.

### Feature D: Capture & Clipboard Pipeline (`CaptureEngine`)
Once the `DragGesture` ends, the app must capture exactly the coordinates defined by the user.
- **Coordinate Conversion:** macOS uses bottom-left origin for some APIs and top-left for others. The builder MUST carefully convert the SwiftUI/AppKit view coordinates to absolute screen pixel coordinates, accounting for Retina scaling (`backingScaleFactor`).
- **Snapping the Frame:** Use `ScreenCaptureKit` (`SCScreenshotManager.captureImage(contentFilter:configuration:)` or similar modern API) passing the calculated `CGRect` to take an instantaneous pixel grab of everything on screen. 
  *Note: `CGWindowListCreateImage` is deprecated in macOS 15, so ScreenCaptureKit is required for future-proofing.*
- **Clipboard Write:** Convert the `CGImage` into an `NSImage`. Open `NSPasteboard.general`, `clearContents()`, and `writeObjects([image])`.
- **Haptic Feedback:** Call `.perform(.generic)` on `NSHapticFeedbackManager.defaultPerformer` to provide physical feedback to the user on success.
- **Cleanup:** Instantly dismiss the overlay windows with a swift 0.2s fade-out animation.

---

## 5. Verification Plan
When the building agent has completed exactly what is described above, it must verify:
1. Does the app launch silently to the menu bar without a dock icon?
2. Does the app correctly prompt for Accessibility and Screen Recording permissions?
3. Does holding the UP arrow for 0.4 seconds trigger the glass overlay? Are normal quick presses still functioning (albeit with slight delay)?
4. Is the selection box drawn with premium, dynamic liquid/glass aesthetics?
5. Upon drag release, does the exact image directly copy to the clipboard and paste perfectly into Claude/Gemini?
