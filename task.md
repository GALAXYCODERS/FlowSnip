# FlowSnip / LiquidSnip Task List

This task list is prepared for the AI agent that will build the application. Check off items as they are implemented.

- [ ] **Phase 1: Project Setup**
  - [ ] Initialize Swift 6 / AppKit + SwiftUI project.
  - [ ] Set `LSUIElement` to `true` in [Info.plist](file:///Users/christianhomborg/.gemini/antigravity/playground/metallic-cassini/Info.plist) (Agent app).
  - [ ] Add Privacy permissions for Accessibility and Screen Capture to [Info.plist](file:///Users/christianhomborg/.gemini/antigravity/playground/metallic-cassini/Info.plist).
- [ ] **Phase 2: Global Key Interception**
  - [ ] Create `EventTapManager` to use `CGEvent.tapCreate`.
  - [ ] Listen specifically for Escape (53) and Up Arrow (126).
  - [ ] Implement 2-second long press detection logic.
  - [ ] Request layout permissions on launch if not granted.
- [ ] **Phase 3: Screen Overlay UI**
  - [ ] Create `OverlayWindowController` that spawns `borderless` `NSWindow` on all active `NSScreen` displays.
  - [ ] Set window level to `.screenSaver` or `.popUpMenu`.
  - [ ] Implement `NSVisualEffectView` backdrops for Frosted Glass.
- [ ] **Phase 4: Liquid Selection Gesture**
  - [ ] Create `LiquidOverlayView` in SwiftUI.
  - [ ] Implement `DragGesture` to calculate selection `CGRect`.
  - [ ] Draw liquid glass selection border (12pt corner radius, 1px bright border, inner shadow).
  - [ ] Use inverted masks / `.ultraThinMaterial` to reveal the selected area cleanly.
- [ ] **Phase 5: Capture & Clipboard Pipeline**
  - [ ] Implement coordinate conversion for Retina / Bottom-Left origins.
  - [ ] Trigger `CGWindowListCreateImage` on the selected `CGRect` (or `ScreenCaptureKit`).
  - [ ] Clear `NSPasteboard` and write the copied image natively.
  - [ ] Provide Haptic feedback (`NSHapticFeedbackManager.defaultPerformer`).
