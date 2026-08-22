import Foundation

enum BlockList {
    /// Matches bare-ish hostnames. Rejects newlines, spaces, and shell metachars, which
    /// would otherwise let a malicious block.txt inject arbitrary /etc/hosts entries.
    /// Swift Regex literal is compile-time checked, so an invalid pattern is a build error.
    private static let hostnameRegex = #/^[a-zA-Z0-9][a-zA-Z0-9.\-]*$/#

    /// One rejected line of a block file. Payload of `InvalidEntries`.
    struct InvalidEntry {
        let path: URL
        let line: Int
        let raw: String
        var message: String {
            "\(path.path):\(line): invalid hostname: \(raw)"
        }
    }

    /// Thrown when any hostname fails validation — carrying every bad line,
    /// not just the first, so a hand-edited list can be fixed in one pass
    /// instead of whack-a-mole through repeated loads.
    struct InvalidEntries: Error, LocalizedError {
        let entries: [InvalidEntry]
        var errorDescription: String? {
            "invalid hostnames:\n" + entries.map(\.message).joined(separator: "\n")
        }
    }

    static func isValid(_ site: String) -> Bool {
        (try? hostnameRegex.wholeMatch(in: site)) != nil
    }

    /// Parse a block file. Blank lines and `#`-prefixed comments are ignored. `www.` is
    /// stripped on input; both variants are added back at apply time by SiteBlock.
    /// Throws `InvalidEntries` listing every hostname that fails validation.
    /// Make sure `~/Library/Application Support/Focus/block.txt` exists, seeding
    /// it from the bundled default on first call. Returns the user path. The UI
    /// calls this when opening the Block-list tab, so the file is created with
    /// the user's permissions, not root's (relevant when CLI is later invoked
    /// via sudo).
    @discardableResult
    static func ensureUserFile() throws -> URL {
        let dest = Paths.userBlockList
        let dir = dest.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: dest.path),
           let bundled = Paths.defaultBlockFile {
            try FileManager.default.copyItem(at: bundled, to: dest)
        }
        return dest
    }

    static func load(from url: URL) throws -> [String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var sites = Set<String>()
        var invalid: [InvalidEntry] = []
        // components(separatedBy: .newlines) handles \n, \r, and \r\n uniformly.
        for (idx, raw) in content.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let site = line.hasPrefix("www.") ? String(line.dropFirst(4)) : line
            guard isValid(site) else {
                invalid.append(InvalidEntry(path: url, line: idx + 1, raw: line))
                continue
            }
            sites.insert(site)
        }
        guard invalid.isEmpty else { throw InvalidEntries(entries: invalid) }
        return sites.sorted()
    }
}
