import Foundation

/// Site blocking via a marker-delimited section of `/etc/hosts`.
///
/// Owns the recipe: backup-once, strip-then-write, DNS flush. Mutation requires
/// the calling process to already hold root; `isActive` does not. DoH endpoints
/// are absorbed here because they are part of how a hosts-file block stays
/// effective when browsers ship their own resolver.
///
/// Wire-compatible with the previous Python tool so external consumers
/// (Hammerspoon, scripts) work unchanged.
struct SiteBlock {
    static let `default` = SiteBlock(
        hostsURL: Paths.hosts,
        backupURL: Paths.hostsBackup,
        dnsFlush: SiteBlock.flushSystemDNS
    )

    let hostsURL: URL
    let backupURL: URL
    let dnsFlush: () -> Void

    // MARK: Interface

    var isActive: Bool {
        (try? read())?.contains(Self.markerStart) ?? false
    }

    /// Install block entries. Each site in `sites` gets bare + www. variants in
    /// both IPv4 and IPv6. `doh` true also blackholes common DNS-over-HTTPS
    /// endpoints (exact match, no www. variant). Returns the number of entries
    /// installed. Requires root. Flushes DNS on success.
    @discardableResult
    func activate(sites: [String], doh: Bool = true) throws -> Int {
        let extras = doh ? Self.dohEndpoints : []
        guard !sites.isEmpty || !extras.isEmpty else { return 0 }
        try backupOnce()
        let cleaned = Self.strip(try read())
        try write(cleaned + Self.renderBlock(sites: sites, extraExactDomains: extras))
        dnsFlush()
        return sites.count + extras.count
    }

    /// Remove the block section. Requires root.
    func deactivate() throws {
        try write(Self.strip(try read()))
        dnsFlush()
    }

    /// Flip the block. Returns the new state (true = now blocking).
    @discardableResult
    func toggle(sites: [String], doh: Bool = true) throws -> Bool {
        if isActive {
            try deactivate()
            return false
        } else {
            try activate(sites: sites, doh: doh)
            return true
        }
    }

    // MARK: Internals (tested via @testable)

    static let markerStart = "# === FOCUS BLOCK START ==="
    static let markerEnd = "# === FOCUS BLOCK END ==="
    static let redirectIP = "127.0.0.1"
    static let redirectIPv6 = "::1"

    /// Common DNS-over-HTTPS resolver endpoints. Browsers with "Secure DNS"
    /// enabled query these directly over HTTPS, bypassing /etc/hosts. Routing
    /// them to loopback forces a fallback to the OS resolver.
    static let dohEndpoints: [String] = [
        "dns.google", "dns.google.com",
        "cloudflare-dns.com",
        "mozilla.cloudflare-dns.com",
        "chrome.cloudflare-dns.com",
        "family.cloudflare-dns.com",
        "1.1.1.1.dns.cloudflare.com",
        "doh.opendns.com",
        "dns.quad9.net", "dns11.quad9.net",
        "dns.adguard.com", "dns.adguard-dns.com",
        "doh.cleanbrowsing.org",
        "mask.icloud.com", "mask-h2.icloud.com",
    ]

    /// Remove the marker-delimited section from a hosts file body, returning the
    /// remainder with a single trailing newline.
    ///
    /// Safety: an unmatched START (no closing END, from a crash mid-write) would
    /// otherwise silently drop the rest of the file. We detect that case and
    /// leave the input alone.
    static func strip(_ content: String) -> String {
        var out: [String] = []
        var skipping = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == markerStart { skipping = true; continue }
            if trimmed == markerEnd { skipping = false; continue }
            if !skipping { out.append(line) }
        }
        if skipping {
            return content
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Pure helper: render the marker-delimited block section as a single string
    /// (with trailing newline). Exposed for tests; called by `activate`.
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

    /// Flush the macOS DNS cache. Assumes the caller is already running as root.
    static func flushSystemDNS() {
        Shell.run(Shell.Command(path: "/usr/bin/dscacheutil", ["-flushcache"]))
        Shell.run(Shell.Command(path: "/usr/bin/killall", ["-HUP", "mDNSResponder"]))
    }

    // MARK: Private

    private func read() throws -> String {
        try String(contentsOf: hostsURL, encoding: .utf8)
    }

    private func write(_ content: String) throws {
        try content.write(to: hostsURL, atomically: true, encoding: .utf8)
    }

    private func backupOnce() throws {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try read().write(to: backupURL, atomically: true, encoding: .utf8)
    }
}
