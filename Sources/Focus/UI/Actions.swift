import Foundation
import AppKit

/// Thin dispatch layer: every menu action spawns the focus CLI (same binary,
/// different argv) and returns immediately. All state changes flow back
/// through the state file, which AppState picks up on its next tick.
enum Actions {
    // MARK: Pomodoro

    static func promptAndStartPomodoro() {
        let alert = NSAlert()
        alert.messageText = "Start pomodoro"
        alert.informativeText = "What are you working on?"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "goal"
        alert.accessoryView = field
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let goal = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !goal.isEmpty {
                startPomodoro(goal: goal, music: nil)
            }
        }
    }

    static func startPomodoro(goal: String, music: String?) {
        var args = ["pomodoro", "start", goal]
        if let music = music, !music.isEmpty {
            args.append(contentsOf: ["--music", music])
        }
        spawn(args)
    }

    static func stopPomodoro() {
        spawn(["pomodoro", "stop"])
    }

    // MARK: Block

    static func toggleBlock() {
        spawnSudo(["toggle"])
    }

    // MARK: Music

    static func playMusic(_ preset: String) {
        spawn(["music", preset])
    }

    static func stopMusic() {
        spawn(["music", "--stop"])
    }

    // MARK: Private

    /// Fire-and-forget invocation of the focus binary. Fails silently on launch error
    /// rather than popping an alert for every missed click.
    private static func spawn(_ args: [String]) {
        _ = try? Subprocess.launchSilent(Paths.selfExecutable, args)
    }

    /// Same as `spawn` but routes through `sudo -n`. Requires the sudoers drop-in.
    private static func spawnSudo(_ args: [String]) {
        _ = try? Subprocess.launchSilent(
            URL(fileURLWithPath: "/usr/bin/sudo"),
            ["-n", Paths.selfExecutable.path] + args
        )
    }
}
