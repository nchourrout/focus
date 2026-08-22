import ArgumentParser
import Foundation

struct FocusCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Run pomodoros, block distractions, and play focus music on macOS.",
        version: focusVersion(),
        subcommands: [
            Block.self,
            Unblock.self,
            ToggleCommand.self,
            StatusCommand.self,
            Music.self,
            Pomodoro.self,
            StatsCommand.self,
            AfplayLoop.self,
            StreamPlay.self,
            PomodoroRun.self,
        ]
    )
}

/// App version for `focus --version`. Sourced from the bundle's Info.plist
/// (`CFBundleShortVersionString`), which `build-app.sh` stamps from the VERSION
/// file. Raw `swift build` binaries have no Info.plist, so report "dev".
func focusVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
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

/// The machine-readable payload of `status --json` and `toggle --json`.
///
/// One type shared by both ends of the pipe. Emission stays hand-formatted,
/// deliberately not JSONEncoder: Foundation reorders keys unpredictably and
/// writes compact spacing, while the documented wire form is grep-stable
/// (`{"active": true}`, see README). Consumption goes through a real decoder,
/// so the menu bar never substring-matches output.
struct BlockStatus: Codable {
    let active: Bool

    /// The exact bytes this CLI has always written; pinned by test.
    var wireFormat: String { "{\"active\": \(active)}" }
}

func printJSONActive(_ active: Bool) {
    print(BlockStatus(active: active).wireFormat)
}
