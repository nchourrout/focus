import Testing
import Foundation
@testable import Focus

@Suite struct BlockListTests {
    @Test func validatorAcceptsCommonForms() {
        #expect(BlockList.isValid("amazon.com"))
        #expect(BlockList.isValid("edition.cnn.com"))
        #expect(BlockList.isValid("with-hyphen.net"))
        #expect(BlockList.isValid("a1.b2.c3"))
    }

    @Test func validatorRejectsInjection() {
        #expect(!BlockList.isValid("evil.com 127.0.0.1"))
        #expect(!BlockList.isValid("evil.com\n127.0.0.1 github.com"))
        #expect(!BlockList.isValid("  leading-space.com"))
        #expect(!BlockList.isValid("-leading-dash.com"))
        #expect(!BlockList.isValid(""))
    }

    @Test func loadStripsCommentsAndBlankLines() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        let content = """
        # comment
        youtube.com

          amazon.com
        # another
        www.chess.com
        """
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sites = try BlockList.load(from: tmp)
        #expect(sites == ["amazon.com", "chess.com", "youtube.com"])
    }

    @Test func loadRejectsInvalidEntry() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try "good.com\n127.0.0.1 evil.com\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: BlockList.InvalidEntries.self) {
            _ = try BlockList.load(from: tmp)
        }
    }

    /// Fail-fast used to surface one bad line per attempt; now every rejected
    /// line lands in the single error so the Settings editor lists them all.
    @Test func loadReportsAllInvalidLinesAtOnce() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try "good.com\nbad one\nalso bad\nwww.fine.org\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        do {
            _ = try BlockList.load(from: tmp)
            Issue.record("expected InvalidEntries")
        } catch let error as BlockList.InvalidEntries {
            #expect(error.entries.count == 2)
            #expect(error.entries.map(\.line) == [2, 3])
            #expect(error.localizedDescription.contains("bad one"))
            #expect(error.localizedDescription.contains("also bad"))
        }
    }

    @Test func loadHandlesCRLF() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try "youtube.com\r\namazon.com\r\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sites = try BlockList.load(from: tmp)
        #expect(sites == ["amazon.com", "youtube.com"], "\\r should be stripped, not smuggled into hostnames")
    }

    @Test func loadRejectsInjectionInCRLFFile() throws {
        // /etc/hosts injection attempt on a CRLF-encoded block file. The
        // injection line ("127.0.0.1 evil.com") fails hostname validation
        // even though the line endings are \r\n.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try "good.com\r\n127.0.0.1 evil.com\r\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: BlockList.InvalidEntries.self) {
            _ = try BlockList.load(from: tmp)
        }
    }
}
