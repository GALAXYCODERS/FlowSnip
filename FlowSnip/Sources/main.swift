import Cocoa

// FlowSnip — Liquid Glass Snipping Tool for macOS
// Launches as a background agent app (no Dock icon) with a menu bar item.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
