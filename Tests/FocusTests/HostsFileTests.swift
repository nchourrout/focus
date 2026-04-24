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
}
