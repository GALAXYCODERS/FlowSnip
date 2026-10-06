import Cocoa

// FlowSnip — Liquid Glass Snipping Tool for macOS
// Launches as a background agent app (no Dock icon) with a menu bar item.

MainActor.assumeIsolated {
	let app = NSApplication.shared
	if CommandLine.arguments.contains("--verify-local-ai") || CommandLine.arguments.contains("--render-ai-ui") {
		Task { @MainActor in
			let result = await AIValidationRunner.run(arguments: CommandLine.arguments)
			fflush(stdout)
			exit(result)
		}
		app.run()
	} else {
		let delegate = AppDelegate()
		app.delegate = delegate
		withExtendedLifetime(delegate) { app.run() }
	}
}
