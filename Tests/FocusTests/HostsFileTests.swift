import Testing
@testable import Focus

@Suite struct HostsFileTests {
    @Test func stripRemovesMarkedBlock() {
        let input = """
        127.0.0.1 localhost
        # === FOCUS BLOCK START ===
        127.0.0.1 youtube.com
        127.0.0.1 www.youtube.com
        # === FOCUS BLOCK END ===
        ::1 localhost
        """
        let result = HostsFile.strip(input)
        #expect(result.contains("127.0.0.1 localhost"))
        #expect(result.contains("::1 localhost"))
        #expect(!result.contains("youtube.com"))
        #expect(!result.contains("FOCUS BLOCK"))
        #expect(result.hasSuffix("\n"))
    }

    @Test func stripWithNoBlockIsIdempotent() {
        let input = "127.0.0.1 localhost\n::1 localhost\n"
        let result = HostsFile.strip(input)
        #expect(
            result.trimmingCharacters(in: .whitespacesAndNewlines)
            == input.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @Test func stripHandlesDoubleBlock() {
        let input = """
        # === FOCUS BLOCK START ===
        127.0.0.1 one.com
        # === FOCUS BLOCK END ===
        127.0.0.1 localhost
        # === FOCUS BLOCK START ===
        127.0.0.1 two.com
        # === FOCUS BLOCK END ===
        """
        let result = HostsFile.strip(input)
        #expect(!result.contains("one.com"))
        #expect(!result.contains("two.com"))
        #expect(result.contains("localhost"))
    }

    @Test func stripHandlesCRLF() {
        let input = "127.0.0.1 localhost\r\n# === FOCUS BLOCK START ===\r\n127.0.0.1 youtube.com\r\n# === FOCUS BLOCK END ===\r\n::1 localhost\r\n"
        let result = HostsFile.strip(input)
        #expect(!result.contains("\r"), "CRLF input should not leak \\r into output")
        #expect(!result.contains("youtube"))
        #expect(result.contains("localhost"))
    }

    @Test func applyThenStripRoundtripIsIdempotent() {
        let base = "127.0.0.1 localhost\n::1 localhost\n"
        let entries = """
        \(HostsFile.markerStart)
        127.0.0.1 youtube.com
        127.0.0.1 www.youtube.com
        \(HostsFile.markerEnd)
        """
        let blocked = base + entries + "\n"

        // strip() must restore the base exactly (modulo whitespace).
        let stripped = HostsFile.strip(blocked)
        #expect(stripped.contains("127.0.0.1 localhost"))
        #expect(stripped.contains("::1 localhost"))
        #expect(!stripped.contains("youtube.com"))

        // Re-stripping the same input is a no-op (no double-block accumulation).
        #expect(HostsFile.strip(stripped) == stripped)

        // strip() of the unblocked input is also a no-op.
        #expect(HostsFile.strip(base).trimmingCharacters(in: .whitespacesAndNewlines)
                == base.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func stripRefusesToDropContentOnUnmatchedStart() {
        // An unmatched START (no END) used to silently drop the remainder of the file.
        // Now we return the input unchanged rather than mangle /etc/hosts.
        let input = """
        127.0.0.1 localhost
        # === FOCUS BLOCK START ===
        127.0.0.1 youtube.com
        (crashed mid-write, no end marker)
        """
        let result = HostsFile.strip(input)
        #expect(result.contains("localhost"))
        #expect(result.contains("youtube.com"), "unmatched markers should preserve the input")
    }
}
