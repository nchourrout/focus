import Testing
import Foundation
@testable import Focus

@Suite struct SudoersInstallerTests {
    @Test func ruleContainsEachSubcommandAgainstRunningBinary() throws {
        let rule = try SudoersInstaller.renderRule()
        let bin = Paths.selfExecutable.path
        for sub in ["block", "unblock", "toggle", "toggle --json"] {
            #expect(rule.contains("\(bin) \(sub)"), "rule should whitelist `\(sub)` against \(bin)")
        }
        #expect(rule.hasPrefix(NSUserName()), "rule's first token must be the username at column 0")
    }

    /// Catches indentation regressions in the multiline string literal: the first
    /// line must start at column 0, and each continuation must be valid sudoers.
    @Test func generatedRulePassesVisudo() throws {
        let rule = try SudoersInstaller.renderRule()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-sudoers-test-\(UUID().uuidString)")
        try rule.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = Subprocess.runCapturingStderr("/usr/sbin/visudo", ["-cf", tmp.path])
        #expect(result.status == 0, "visudo rejected the generated rule:\n\(result.stderr)")
    }
}
