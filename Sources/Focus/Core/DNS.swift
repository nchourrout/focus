import Foundation

enum DNS {
    /// Flush the macOS DNS cache. Assumes the caller is already running as root.
    static func flush() {
        _ = Subprocess.run("/usr/bin/dscacheutil", ["-flushcache"])
        _ = Subprocess.run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }
}
