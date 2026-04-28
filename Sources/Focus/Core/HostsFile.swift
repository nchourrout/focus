import Foundation

/// Read/write of `/etc/hosts` with a marker-delimited block section.
///
/// Wire-compatible with the previous Python tool so external consumers
/// (Hammerspoon, scripts) work unchanged.
enum HostsFile {
    static let markerStart = "# === FOCUS BLOCK START ==="
    static let markerEnd = "# === FOCUS BLOCK END ==="
    static let redirectIP = "127.0.0.1"
    static let redirectIPv6 = "::1"

    static func read() throws -> String {
        try String(contentsOf: Paths.hosts, encoding: .utf8)
    }

    static func write(_ content: String) throws {
        try content.write(to: Paths.hosts, atomically: true, encoding: .utf8)
    }

    static func isActive() -> Bool {
        (try? read())?.contains(markerStart) ?? false
    }

    /// Remove the marker-delimited section from a hosts file body, returning the remainder
    /// with a single trailing newline.
    ///
    /// Safety: an unmatched START (no closing END, from a crash mid-write) would otherwise
    /// silently drop the rest of the file. We detect that case and leave the input alone.
    static func strip(_ content: String) -> String {
        var out: [String] = []
        var skipping = false
        // .newlines splits on \n, \r, and \r\n uniformly — no lingering \r on entries.
        // Compare each trimmed line to the marker so:
        //   (1) a comment mentioning the marker text doesn't trigger stripping;
        //   (2) trailing whitespace (editor artifact) on the marker line still matches.
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == markerStart { skipping = true; continue }
            if trimmed == markerEnd { skipping = false; continue }
            if !skipping { out.append(line) }
        }
        if skipping {
            // Mismatched markers — refuse to mangle the file.
            return content
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func backupOnce() throws {
        guard !FileManager.default.fileExists(atPath: Paths.hostsBackup.path) else { return }
        let content = try read()
        try content.write(to: Paths.hostsBackup, atomically: true, encoding: .utf8)
    }

    /// Install block entries. Each site in `sites` gets bare + www. variants in
    /// both IPv4 and IPv6. `extraExactDomains` are blackholed too but without
    /// the www. variant — used for DNS-over-HTTPS endpoints that should match
    /// exactly what the browser would query.
    /// Requires root. Flushes DNS on success. Returns the number of entries
    /// (sites + extras) installed.
    @discardableResult
    static func apply(sites: [String], extraExactDomains: [String] = []) throws -> Int {
        guard !sites.isEmpty || !extraExactDomains.isEmpty else { return 0 }
        try backupOnce()
        let cleaned = strip(try read())
        try write(cleaned + renderBlock(sites: sites, extraExactDomains: extraExactDomains))
        DNS.flush()
        return sites.count + extraExactDomains.count
    }

    /// Pure helper: render the marker-delimited block section as a single string
    /// (with trailing newline). Exposed for tests; called by `apply`.
    ///
    /// Both IPv4 and IPv6 loopback entries are emitted. Without `::1`, macOS's
    /// Happy Eyeballs resolver still hands real IPv6 DNS answers to apps and the
    /// block is silently bypassed for sites with AAAA records.
    static func renderBlock(sites: [String], extraExactDomains: [String]) -> String {
        var entries = [markerStart]
        for site in sites {
            entries.append("\(redirectIP) \(site)")
            entries.append("\(redirectIPv6) \(site)")
            entries.append("\(redirectIP) www.\(site)")
            entries.append("\(redirectIPv6) www.\(site)")
        }
        for domain in extraExactDomains {
            entries.append("\(redirectIP) \(domain)")
            entries.append("\(redirectIPv6) \(domain)")
        }
        entries.append(markerEnd)
        return entries.joined(separator: "\n") + "\n"
    }

    /// Remove the block section. Requires root.
    static func unblock() throws {
        try write(strip(try read()))
        DNS.flush()
    }
}
