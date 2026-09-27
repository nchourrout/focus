import Foundation
import CryptoKit

/// Installs `/etc/sudoers.d/focus` using AppleScript's
/// `do shell script ... with administrator privileges`, which surfaces the
/// native macOS admin password dialog. No shell script, no code-signed helper,
/// no Developer ID requirement.
///
/// The rule never names the binary the user launched. That one lives in a
/// directory the user can write (`/Applications` is admin-group writable, a
/// zip install or a `.build` binary is user-owned), so any process running as
/// the user could swap it and then call it through `sudo -n` as root. The
/// installer copies it instead to a root-owned directory, checks the copy's
/// hash as root, and points the rule there.
enum SudoersInstaller {
    static let dropInPath = "/etc/sudoers.d/focus"

    /// Matches the safe subset of characters we're willing to interpolate into
    /// the sudoers rule (alphanumerics, dot, underscore, hyphen, slash).
    /// Guards against a malicious or exotic username / path injecting sudoers
    /// metacharacters like `%` or whitespace.
    private static let safeTokenPattern = #/^[A-Za-z0-9._/\-]+$/#

    /// Whether the drop-in exists, so `sudo -n` has a rule to try.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: dropInPath)
    }

    enum Status {
        /// No drop-in: every privileged action fails.
        case missing
        /// A drop-in exists but the root-owned helper is absent (a rule from
        /// before the helper existed, which still trusts the user-writable
        /// binary) or differs from the running build. Privileged actions work
        /// but run the old code, or the unprotected binary.
        case outdated
        case current
    }

    /// Compares the helper byte for byte with the running binary. Reads a few
    /// MB, so call it on demand (Settings), not on a timer.
    static var status: Status {
        guard isInstalled else { return .missing }
        let fm = FileManager.default
        guard let helper = fm.contents(atPath: Paths.privilegedHelper.path),
              let running = fm.contents(atPath: Paths.selfExecutable.path),
              helper == running
        else { return .outdated }
        return .current
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

    /// Build the sudoers rule targeting the root-owned helper.
    /// Internal (not private) so tests can validate the output.
    static func renderRule(binary: String = Paths.privilegedHelper.path,
                           user: String = NSUserName()) throws -> String {
        try assertSafe(user, field: "username")
        try assertSafe(binary, field: "binary path")
        return """
        \(user) ALL=(root) NOPASSWD: \\
            \(binary) block, \\
            \(binary) block --no-block-doh, \\
            \(binary) unblock, \\
            \(binary) toggle, \\
            \(binary) toggle --json, \\
            \(binary) toggle --json --no-block-doh
        """
    }

    /// Pure check exposed for unit tests: does `value` consist only of the
    /// characters we're willing to interpolate into the sudoers rule?
    static func isSafeToken(_ value: String) -> Bool {
        (try? safeTokenPattern.wholeMatch(in: value)) != nil
    }

    private static func assertSafe(_ value: String, field: String) throws {
        guard isSafeToken(value) else {
            throw InstallError.unsafeInput(field)
        }
    }

    /// The script the admin dialog runs as root. Everything it trusts is
    /// produced inside it: the helper is copied into a root-owned temp dir and
    /// its hash checked against `sha256` (taken before the prompt, so a binary
    /// swapped while the dialog is open is refused), and the rule is written,
    /// validated and moved by root. Nothing passes through a user-writable
    /// file between validation and install. Internal for tests.
    static func privilegedScript(binary: String, resourceBundle: String?,
                                 sha256: String, rule: String) throws -> String {
        try assertSafe(binary, field: "binary path")
        if let resourceBundle { try assertSafe(resourceBundle, field: "resource bundle path") }
        try assertSafe(sha256, field: "hash")
        let dir = Paths.privilegedHelperDir
        let parent = (dir as NSString).deletingLastPathComponent
        // Rule lines hold only safe tokens plus `,` `=` `(` `)` `:` and the
        // continuation backslash, all inert inside single quotes.
        let ruleArgs = rule.split(separator: "\n").map { "'\($0)'" }.joined(separator: " ")
        var lines: [String] = [
            "set -e",
            "umask 022",
            "t=''; r=''",
            "trap '/bin/rm -rf \"$t\" \"$r\"' EXIT",
            "/bin/mkdir -p '\(parent)'",
            "t=$(/usr/bin/mktemp -d '\(parent)/.focus.XXXXXX')",
            "/bin/cp '\(binary)' \"$t/focus\"",
        ]
        if let resourceBundle { lines.append("/bin/cp -R '\(resourceBundle)' \"$t/\"") }
        lines += [
            "[ \"$(/usr/bin/shasum -a 256 \"$t/focus\" | /usr/bin/cut -d ' ' -f 1)\" = '\(sha256)' ] || { echo 'focus binary changed during install' >&2; exit 1; }",
            "/usr/sbin/chown -R root:wheel \"$t\"",
            "/bin/chmod -R go-w \"$t\"",
            "/bin/chmod 755 \"$t\"",
            "/bin/rm -rf '\(dir)'",
            "/bin/mv \"$t\" '\(dir)'",
            "t=''",
            // A leading dot keeps sudo's includedir from reading the file
            // before it has been validated.
            "r=$(/usr/bin/mktemp /etc/sudoers.d/.focus.XXXXXX)",
            "/usr/bin/printf '%s\\n' \(ruleArgs) > \"$r\"",
            "/usr/sbin/visudo -cf \"$r\" >/dev/null",
            "/usr/sbin/chown root:wheel \"$r\"",
            "/bin/chmod 0440 \"$r\"",
            "/bin/mv -f \"$r\" '\(dropInPath)'",
            "r=''",
        ]
        return lines.joined(separator: "\n")
    }

    /// Synchronous install. Blocks the calling thread through `visudo` plus the
    /// AppleScript admin dialog, so call off the main queue (use `installWithUI`
    /// from UI code).
    static func install() throws {
        let rule = try renderRule()

        // Validate before prompting. A syntax error here is ours to fix, not the
        // user's. Root validates again on its own copy; this pass only exists so
        // a bad rule never costs the user a password.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focus-sudoers-\(UUID().uuidString)")
        try rule.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let visudo = Shell.run(Shell.Command(
            path: "/usr/sbin/visudo", ["-cf", tmp.path], captureStderr: true
        ))
        if visudo.status != 0 {
            throw InstallError.invalidRule(visudo.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let binary = Paths.selfExecutable
        guard let bytes = FileManager.default.contents(atPath: binary.path) else {
            throw InstallError.systemFailure("cannot read \(binary.path)")
        }
        let sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let bundle = binary.deletingLastPathComponent().appendingPathComponent("Focus_Focus.bundle")
        let script = try privilegedScript(
            binary: binary.path,
            resourceBundle: FileManager.default.fileExists(atPath: bundle.path) ? bundle.path : nil,
            sha256: sha256,
            rule: rule
        )
        let apple = "do shell script \"\(escapeAppleScript(script))\" with administrator privileges"
        let result = Shell.run(Shell.Command(
            path: "/usr/bin/osascript", ["-e", apple], captureStderr: true
        ))
        if result.status == 0 { return }
        // osascript exits 1 for any script-level error. User cancellation specifically
        // carries the `(-128)` error code in stderr ("User canceled. (-128)"), so we
        // match the parenthesized form to avoid false positives on errors that
        // happen to contain the digits "-128" elsewhere.
        if result.stderr.contains("(-128)") {
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
