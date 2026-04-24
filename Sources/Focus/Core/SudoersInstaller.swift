import Foundation
import AppKit

/// Installs `/etc/sudoers.d/focus` using AppleScript's
/// `do shell script ... with administrator privileges`, which surfaces the
/// native macOS admin password dialog. No shell script, no code-signed helper,
/// no Developer ID requirement.
enum SudoersInstaller {
    static let dropInPath = "/etc/sudoers.d/focus"

    /// Matches the safe subset of characters we're willing to interpolate into
    /// the sudoers rule (alphanumerics, dot, underscore, hyphen, slash).
    /// Guards against a malicious or exotic username / path injecting sudoers
    /// metacharacters like `%` or whitespace.
    private static let safeTokenPattern = #/^[A-Za-z0-9._/\-]+$/#

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: dropInPath)
    }

    enum InstallError: Error, LocalizedError {
        case invalidRule(String)
        case userCancelled
        case systemFailure(String)
        case unsafeInput(String)

        var errorDescription: String? {
            switch self {
            case .invalidRule(let msg): return "Generated sudoers rule failed visudo: \(msg)"
            case .userCancelled: return "Admin password dialog was cancelled."
            case .systemFailure(let msg): return "Failed to install sudoers drop-in: \(msg)"
            case .unsafeInput(let field): return "Refusing to interpolate unsafe \(field) into sudoers rule."
            }
        }
    }

    /// Build the sudoers rule targeting the currently-running binary.
    /// Internal (not private) so tests can validate the output.
    static func renderRule() throws -> String {
        let bin = Paths.selfExecutable.path
        let user = NSUserName()
        try assertSafe(user, field: "username")
        try assertSafe(bin, field: "binary path")
        return """
        \(user) ALL=(root) NOPASSWD: \\
            \(bin) block, \\
            \(bin) unblock, \\
            \(bin) toggle, \\
            \(bin) toggle --json
        """
    }

    private static func assertSafe(_ value: String, field: String) throws {
        guard (try? safeTokenPattern.wholeMatch(in: value)) != nil else {
            throw InstallError.unsafeInput(field)
        }
    }

    /// Synchronous install. Blocks the calling thread through `visudo` plus the
    /// AppleScript admin dialog, so call off the main queue (use `installWithUI`
    /// from UI code).
    static func install() throws {
        let rule = try renderRule()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focus-sudoers-\(UUID().uuidString)")
        try rule.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Validate before prompting. A syntax error here is ours to fix, not the user's.
        let visudo = Subprocess.runCapturingStderr("/usr/sbin/visudo", ["-cf", tmp.path])
        if visudo.status != 0 {
            throw InstallError.invalidRule(visudo.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // tmp.path is UUID-based (no apostrophes / control chars); dropInPath is a constant.
        let command = "/bin/cp '\(tmp.path)' '\(dropInPath)' && /bin/chmod 0440 '\(dropInPath)'"
        let script = "do shell script \"\(escapeAppleScript(command))\" with administrator privileges"
        let result = Subprocess.runCapturingStderr("/usr/bin/osascript", ["-e", script])
        if result.status == 0 { return }
        // osascript exits 1 for any script-level error. User cancellation specifically
        // carries the `-128` error code in stderr ("User canceled. (-128)"), so we
        // use that string as the signal rather than the exit code alone.
        if result.stderr.contains("-128") {
            throw InstallError.userCancelled
        }
        throw InstallError.systemFailure(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// UI-facing wrapper: runs `install()` off the main thread so the app window
    /// doesn't freeze during the password dialog, then hands the outcome back on
    /// the main actor. `userCancelled` is swallowed silently; real errors go to
    /// `onError`; success calls `onSuccess`.
    @MainActor
    static func installWithUI(
        onSuccess: @MainActor @escaping () -> Void = {},
        onError: @MainActor @escaping (Error) -> Void = { _ in }
    ) {
        Task.detached {
            do {
                try install()
                await MainActor.run { onSuccess() }
            } catch InstallError.userCancelled {
                // Silent by design.
            } catch {
                await MainActor.run { onError(error) }
            }
        }
    }
}
