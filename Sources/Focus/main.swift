import Foundation

// Dual-mode entry point:
// - Any argument present → CLI mode (run a subcommand).
// - No args → UI mode (menu bar app).
if CommandLine.arguments.count > 1 {
    FocusCLI.main()
} else {
    FocusApp.main()
}
