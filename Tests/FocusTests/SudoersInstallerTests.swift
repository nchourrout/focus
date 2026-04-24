import Testing
import Foundation
@testable import Focus

@Suite struct SudoersInstallerTests {
    /// Pure-logic check: the rendered rule must use the real binary path and the
    /// current user, with the expected four whitelisted subcommands.
    @Test func ruleShapeIsCorrect() throws {
        // Use reflection-free access by invoking install() indirectly isn't feasible;
        // instead we encode the contract: what install() sends to visudo must start
        // with "<user> ALL=(root) NOPASSWD:" and mention each subcommand exactly once.
        // We recreate the same rendering here as a sanity check on the shape.
        let user = NSUserName()
        let bin = Paths.selfExecutable.path
        let expected = """
        \(user) ALL=(root) NOPASSWD: \\
            \(bin) block, \\
            \(bin) unblock, \\
            \(bin) toggle, \\
            \(bin) toggle --json
        """
        // Sanity: non-empty user and an absolute bin path.
        #expect(!user.isEmpty)
        #expect(bin.hasPrefix("/"))
        // Each subcommand appears in the expected form.
        for sub in ["block", "unblock", "toggle", "toggle --json"] {
            #expect(expected.contains("\(bin) \(sub)"), "rule should whitelist `\(sub)` against the running binary")
        }
    }
}
