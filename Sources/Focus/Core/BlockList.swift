import Foundation

enum BlockList {
    /// Matches bare-ish hostnames. Rejects newlines, spaces, and shell metachars, which
    /// would otherwise let a malicious block.txt inject arbitrary /etc/hosts entries.
    /// Swift Regex literal is compile-time checked, so an invalid pattern is a build error.
    private static let hostnameRegex = #/^[a-zA-Z0-9][a-zA-Z0-9.\-]*$/#

    struct InvalidEntry: Error, LocalizedError {
        let path: URL
        let line: Int
        let raw: String
        var errorDescription: String? {
            "\(path.path):\(line): invalid hostname: \(raw)"
        }
    }

    static func isValid(_ site: String) -> Bool {
        (try? hostnameRegex.wholeMatch(in: site)) != nil
    }

    /// Parse a block file. Blank lines and `#`-prefixed comments are ignored. `www.` is
    /// stripped on input; both variants are added back at apply time by HostsFile.
    /// Throws `InvalidEntry` for any hostname that fails validation.
    static func load(from url: URL) throws -> [String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var sites = Set<String>()
        // components(separatedBy: .newlines) handles \n, \r, and \r\n uniformly.
        for (idx, raw) in content.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let site = line.hasPrefix("www.") ? String(line.dropFirst(4)) : line
            guard isValid(site) else {
                throw InvalidEntry(path: url, line: idx + 1, raw: line)
            }
            sites.insert(site)
        }
        return sites.sorted()
    }
}
