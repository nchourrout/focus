import ArgumentParser
import Foundation

struct FocusCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Block distractions and play focus music on macOS.",
        subcommands: [
            Block.self,
            Unblock.self,
            ToggleCommand.self,
            StatusCommand.self,
            Music.self,
            Pomodoro.self,
            AfplayLoop.self,
            StreamPlay.self,
            PomodoroRun.self,
        ]
    )
}

/// Shared helper: require root for hosts-writing commands.
func requireRoot() throws {
    if geteuid() != 0 {
        throw CLIError.notRoot
    }
}

/// Expand `~` and verify the file exists. Throws `CLIError.missingFile` otherwise.
func resolveExistingFile(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CLIError.missingFile(url)
    }
    return url
}

/// Resolve the default or user-supplied block file path.
/// Precedence: explicit `--file` > user-edited list > bundled default.
func resolveBlockFile(_ override: String?) throws -> URL {
    if let override = override, !override.isEmpty {
        return try resolveExistingFile(override)
    }
    if FileManager.default.fileExists(atPath: Paths.userBlockList.path) {
        return Paths.userBlockList
    }
    if let url = Paths.defaultBlockFile {
        return url
    }
    throw CLIError.missingFile(URL(fileURLWithPath: "block.txt"))
}

/// Minimal JSON printer (Foundation JSONEncoder reorders keys unpredictably; we
/// keep output small and deterministic so consumers can grep).
func printJSONActive(_ active: Bool) {
    print("{\"active\": \(active ? "true" : "false")}")
}
