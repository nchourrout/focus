import Foundation

/// Read/write of `/etc/hosts` with a marker-delimited block section.
///
/// Wire-compatible with the previous Python tool so external consumers
/// (Hammerspoon, scripts) work unchanged.
enum HostsFile {
    static let markerStart = "# === FOCUS BLOCK START ==="
    static let markerEnd = "# === FOCUS BLOCK END ==="
    static let redirectIP = "127.0.0.1"

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

    /// Install block entries. Each site gets both the bare and www. variants.
    /// Requires root. Flushes DNS on success. Returns the number of sites blocked.
    @discardableResult
    static func apply(sites: [String]) throws -> Int {
        guard !sites.isEmpty else { return 0 }
        try backupOnce()
        let cleaned = strip(try read())
        var entries = [markerStart]
        for site in sites {
            entries.append("\(redirectIP) \(site)")
            entries.append("\(redirectIP) www.\(site)")
        }
        entries.append(markerEnd)
        try write(cleaned + entries.joined(separator: "\n") + "\n")
        DNS.flush()
        return sites.count
    }

    /// Remove the block section. Requires root.
    static func unblock() throws {
        try write(strip(try read()))
        DNS.flush()
    }
}
