import Foundation

/// Installs `/etc/sudoers.d/focus` using AppleScript's
/// `do shell script ... with administrator privileges`, which surfaces the
/// native macOS admin password dialog. No shell script, no code-signed helper,
/// no Developer ID requirement.
enum SudoersInstaller {
    static let dropInPath = "/etc/sudoers.d/focus"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: dropInPath)
    }

    enum InstallError: Error, LocalizedError {
        case invalidRule(String)
        case userCancelled
        case systemFailure(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidRule(let msg): return "Generated sudoers rule failed visudo: \(msg)"
            case .userCancelled: return "Admin password dialog was cancelled."
            case .systemFailure(let code): return "Failed to install sudoers drop-in (exit \(code))."
            }
        }
    }

    /// Write, validate, and install the drop-in. Prompts once for admin password.
    /// Synchronous: blocks until the dialog is resolved, so call off the main queue
    /// if the caller is a SwiftUI button.
    static func install() throws {
        let rule = renderRule()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focus-sudoers-\(UUID().uuidString)")
        try rule.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Validate before prompting, so a bad rule doesn't pop a password dialog for nothing.
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/sbin/visudo")
        check.arguments = ["-cf", tmp.path]
        let err = Pipe()
        check.standardError = err
        check.standardOutput = FileHandle.nullDevice
        try check.run()
        check.waitUntilExit()
        if check.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown"
            throw InstallError.invalidRule(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Single-quoted shell arguments are safe because `tmp` is a UUID-based path
        // with no apostrophes or newlines, and `dropInPath` is a compile-time constant.
        let command = "/bin/cp '\(tmp.path)' '\(dropInPath)' && /bin/chmod 0440 '\(dropInPath)'"
        let script = "do shell script \"\(escapeAppleScript(command))\" with administrator privileges"
        let rc = Subprocess.osascript(script)
        if rc == 1 {
            // osascript returns 1 when the user clicks Cancel on the admin password dialog.
            throw InstallError.userCancelled
        }
        if rc != 0 {
            throw InstallError.systemFailure(rc)
        }
    }

    /// Build the sudoers rule targeting the currently-running binary.
    private static func renderRule() -> String {
        let bin = Paths.selfExecutable.path
        let user = NSUserName()
        // Backslash-continuation keeps any one line under typical lint limits and is
        // valid sudoers syntax (see `man 5 sudoers`).
        return """
        \(user) ALL=(root) NOPASSWD: \\
            \(bin) block, \\
            \(bin) unblock, \\
            \(bin) toggle, \\
            \(bin) toggle --json
        """
    }
}
