import Testing
import Foundation
@testable import Focus

@Suite struct SudoersInstallerTests {
    @Test func ruleContainsEachSubcommandAgainstTheHelper() throws {
        let rule = try SudoersInstaller.renderRule()
        let bin = Paths.privilegedHelper.path
        for sub in [
            "block", "block --no-block-doh",
            "unblock",
            "toggle", "toggle --json", "toggle --json --no-block-doh",
        ] {
            #expect(rule.contains("\(bin) \(sub)"), "rule should whitelist `\(sub)` against \(bin)")
        }
        #expect(rule.hasPrefix(NSUserName()), "rule's first token must be the username at column 0")
    }

    @Test func safeTokenAcceptsExpectedValues() {
        for ok in ["nico", "user_name", "user-name", "/Applications/Focus.app/Contents/MacOS/focus", "a.b.c"] {
            #expect(SudoersInstaller.isSafeToken(ok), "should accept: \(ok)")
        }
    }

    @Test func safeTokenRejectsUnsafeValues() {
        // sudoers metacharacters / shell-meta / whitespace / control: each must fail.
        for bad in [
            "user with space",       // whitespace
            "user'name",             // apostrophe (would break shell single-quotes)
            "user\"name",            // double quote
            "user;rm -rf",           // shell injection
            "user\nALL=(root)",      // newline injection
            "%wheel",                // sudoers group reference
            "",                      // empty
            "user$",                 // shell expansion
        ] {
            #expect(!SudoersInstaller.isSafeToken(bad), "should reject: \(bad.debugDescription)")
        }
    }

    /// Catches indentation regressions in the multiline string literal: the first
    /// line must start at column 0, and each continuation must be valid sudoers.
    @Test func generatedRulePassesVisudo() throws {
        let rule = try SudoersInstaller.renderRule()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-sudoers-test-\(UUID().uuidString)")
        try rule.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = Shell.run(Shell.Command(
            path: "/usr/sbin/visudo", ["-cf", tmp.path], captureStderr: true
        ))
        #expect(result.status == 0, "visudo rejected the generated rule:\n\(result.stderr)")
    }

    @Test func ruleNeverTrustsTheRunningBinary() throws {
        let rule = try SudoersInstaller.renderRule()
        #expect(!rule.contains(Paths.selfExecutable.path + " "),
                "the running binary is user-writable; only the root-owned helper may be named")
    }

    private func script(bundle: String? = "/x/Focus_Focus.bundle") throws -> String {
        try SudoersInstaller.privilegedScript(
            binary: "/Applications/Focus.app/Contents/MacOS/focus",
            resourceBundle: bundle,
            sha256: String(repeating: "a", count: 64),
            rule: try SudoersInstaller.renderRule()
        )
    }

    @Test func privilegedScriptIsValidShell() throws {
        for bundle in ["/x/Focus_Focus.bundle", nil] {
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("focus-install-\(UUID().uuidString).sh")
            try script(bundle: bundle).write(to: path, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: path) }
            let result = Shell.run(Shell.Command(path: "/bin/sh", ["-n", path.path], captureStderr: true))
            #expect(result.status == 0, "sh -n rejected the install script:\n\(result.stderr)")
        }
    }

    /// Root writes the rule with printf, not by copying a user-owned file, so
    /// the printf line must reproduce the rule byte for byte.
    @Test func privilegedScriptWritesTheExactRule() throws {
        let rule = try SudoersInstaller.renderRule()
        let printf = try #require(try script().split(separator: "\n").first { $0.hasPrefix("/usr/bin/printf") })
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("focus-rule-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let line = String(printf).replacingOccurrences(of: "\"$r\"", with: "'\(out.path)'")
        let result = Shell.run(Shell.Command(path: "/bin/sh", ["-c", line], captureStderr: true))
        #expect(result.status == 0, "\(result.stderr)")
        #expect(try String(contentsOf: out, encoding: .utf8) == rule + "\n")
    }

    @Test func privilegedScriptChecksTheHashBeforeInstalling() throws {
        let lines = try script().split(separator: "\n").map(String.init)
        let check = try #require(lines.firstIndex { $0.contains("shasum -a 256") })
        let move = try #require(lines.firstIndex { $0.hasPrefix("/bin/mv \"$t\"") })
        let chown = try #require(lines.firstIndex { $0.hasPrefix("/usr/sbin/chown -R root:wheel") })
        #expect(check < chown && chown < move)
        #expect(lines.first == "set -e")
    }
}
