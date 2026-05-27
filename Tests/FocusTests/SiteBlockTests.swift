import Foundation
import Testing
@testable import Focus

@Suite struct SiteBlockTests {

    // MARK: Pure helpers — unmatched-marker safety and shape invariants

    @Test func stripRemovesMarkedBlock() {
        let input = """
        127.0.0.1 localhost
        # === FOCUS BLOCK START ===
        127.0.0.1 youtube.com
        127.0.0.1 www.youtube.com
        # === FOCUS BLOCK END ===
        ::1 localhost
        """
        let result = SiteBlock.strip(input)
        #expect(result.contains("127.0.0.1 localhost"))
        #expect(result.contains("::1 localhost"))
        #expect(!result.contains("youtube.com"))
        #expect(!result.contains("FOCUS BLOCK"))
        #expect(result.hasSuffix("\n"))
    }

    @Test func stripWithNoBlockIsIdempotent() {
        let input = "127.0.0.1 localhost\n::1 localhost\n"
        let result = SiteBlock.strip(input)
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
        let result = SiteBlock.strip(input)
        #expect(!result.contains("one.com"))
        #expect(!result.contains("two.com"))
        #expect(result.contains("localhost"))
    }

    @Test func stripHandlesCRLF() {
        let input = "127.0.0.1 localhost\r\n# === FOCUS BLOCK START ===\r\n127.0.0.1 youtube.com\r\n# === FOCUS BLOCK END ===\r\n::1 localhost\r\n"
        let result = SiteBlock.strip(input)
        #expect(!result.contains("\r"), "CRLF input should not leak \\r into output")
        #expect(!result.contains("youtube"))
        #expect(result.contains("localhost"))
    }

    @Test func stripRoundtripIsIdempotent() {
        let base = "127.0.0.1 localhost\n::1 localhost\n"
        let entries = """
        \(SiteBlock.markerStart)
        127.0.0.1 youtube.com
        127.0.0.1 www.youtube.com
        \(SiteBlock.markerEnd)
        """
        let blocked = base + entries + "\n"
        let stripped = SiteBlock.strip(blocked)
        #expect(stripped.contains("127.0.0.1 localhost"))
        #expect(stripped.contains("::1 localhost"))
        #expect(!stripped.contains("youtube.com"))
        #expect(SiteBlock.strip(stripped) == stripped)
        #expect(SiteBlock.strip(base).trimmingCharacters(in: .whitespacesAndNewlines)
                == base.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `extraExactDomains` should yield bare IPv4 + IPv6 entries for each domain,
    /// without the www. variant. Used for DNS-over-HTTPS resolver hostnames where
    /// `www.dns.google` etc. are not real endpoints.
    @Test func renderEmitsExactExtraDomainsOnly() throws {
        let entries = ["dns.google", "cloudflare-dns.com"]
        let output = SiteBlock.renderBlock(sites: [], extraExactDomains: entries)
        #expect(output.contains("127.0.0.1 dns.google\n"))
        #expect(output.contains("::1 dns.google\n"))
        #expect(output.contains("127.0.0.1 cloudflare-dns.com\n"))
        #expect(output.contains("::1 cloudflare-dns.com\n"))
        #expect(!output.contains("www.dns.google"), "extras must not get a www. variant")
        #expect(!output.contains("www.cloudflare-dns.com"))
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
        let result = SiteBlock.strip(input)
        #expect(result.contains("localhost"))
        #expect(result.contains("youtube.com"), "unmatched markers should preserve the input")
    }

    // MARK: Interface — round-trip against a sandboxed hosts file

    /// Build a SiteBlock pointed at a freshly-created tmp hosts file (seeded with
    /// `seed`) and a tmp backup path. dnsFlush is a no-op.
    private func makeSandbox(seed: String = "127.0.0.1 localhost\n::1 localhost\n")
    throws -> (block: SiteBlock, hosts: URL, backup: URL)
    {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("site-block-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let hosts = dir.appendingPathComponent("hosts")
        let backup = dir.appendingPathComponent("hosts.backup")
        try seed.write(to: hosts, atomically: true, encoding: .utf8)
        let block = SiteBlock(hostsURL: hosts, backupURL: backup, dnsFlush: {})
        return (block, hosts, backup)
    }

    @Test func activateThenDeactivateRestoresOriginal() throws {
        let (block, hosts, _) = try makeSandbox()
        let original = try String(contentsOf: hosts, encoding: .utf8)

        let count = try block.activate(sites: ["youtube.com"], doh: false)
        #expect(count == 1)
        #expect(block.isActive)

        let blocked = try String(contentsOf: hosts, encoding: .utf8)
        #expect(blocked.contains("127.0.0.1 youtube.com"))
        #expect(blocked.contains("::1 youtube.com"))
        #expect(blocked.contains("127.0.0.1 www.youtube.com"))
        #expect(blocked.contains(SiteBlock.markerStart))

        try block.deactivate()
        #expect(!block.isActive)
        let restored = try String(contentsOf: hosts, encoding: .utf8)
        #expect(restored.trimmingCharacters(in: .whitespacesAndNewlines)
                == original.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func activateBacksUpOnceThenLeavesBackupAlone() throws {
        let (block, hosts, backup) = try makeSandbox()
        let originalForBackup = try String(contentsOf: hosts, encoding: .utf8)
        try block.activate(sites: ["youtube.com"], doh: false)
        let firstBackup = try String(contentsOf: backup, encoding: .utf8)
        #expect(firstBackup == originalForBackup, "first activate snapshots the pre-block hosts")

        // Second activate must not overwrite the backup with the already-blocked file.
        try block.deactivate()
        try block.activate(sites: ["reddit.com"], doh: false)
        let secondBackup = try String(contentsOf: backup, encoding: .utf8)
        #expect(secondBackup == firstBackup, "backupOnce is idempotent")
    }

    @Test func toggleFlipsState() throws {
        let (block, _, _) = try makeSandbox()
        #expect(block.isActive == false)
        #expect(try block.toggle(sites: ["x.com"], doh: false) == true)
        #expect(block.isActive)
        #expect(try block.toggle(sites: ["x.com"], doh: false) == false)
        #expect(!block.isActive)
    }

    @Test func activateWithDoHAddsExtraEndpoints() throws {
        let (block, hosts, _) = try makeSandbox()
        try block.activate(sites: ["youtube.com"], doh: true)
        let body = try String(contentsOf: hosts, encoding: .utf8)
        #expect(body.contains("127.0.0.1 dns.google"))
        #expect(body.contains("127.0.0.1 cloudflare-dns.com"))
        #expect(!body.contains("www.dns.google"), "DoH endpoints are exact-match only")
    }

    @Test func dnsFlushFiresOnActivateAndDeactivate() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("site-block-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let hosts = dir.appendingPathComponent("hosts")
        try "127.0.0.1 localhost\n".write(to: hosts, atomically: true, encoding: .utf8)

        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let block = SiteBlock(
            hostsURL: hosts,
            backupURL: dir.appendingPathComponent("hosts.backup"),
            dnsFlush: { counter.n += 1 }
        )
        try block.activate(sites: ["x.com"], doh: false)
        try block.deactivate()
        #expect(counter.n == 2)
    }
}
