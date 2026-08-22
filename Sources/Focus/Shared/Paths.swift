import Foundation

enum Paths {
    static let hosts = URL(fileURLWithPath: "/etc/hosts")
    static let hostsBackup = URL(fileURLWithPath: "/etc/hosts.backup")

    /// Advisory lock serializing concurrent /etc/hosts mutations (daemon phase
    /// boundaries vs menu bar toggle vs a terminal's `focus toggle`). Lives in
    /// /tmp: recreated on reboot, and only ever touched by root, since every
    /// mutating command requires sudo.
    static let hostsLockPath = "/tmp/com.nchourrout.focus.hosts.lock"

    static var pomodoroState: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".focus-pomodoro.json")
    }

    static var musicPid: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".focus-music.pid")
    }

    /// Default block.txt, bundled as an SPM resource (read-only).
    /// Used as the seed for the user-writable list and as a fallback when the
    /// user file doesn't exist yet.
    static var defaultBlockFile: URL? {
        Bundle.module.url(forResource: "block", withExtension: "txt")
    }

    /// User-writable block list at ~/Library/Application Support/Focus/block.txt.
    /// Resolved against the login user's home (NSHomeDirectoryForUser) so that
    /// running under sudo doesn't steer the path into /var/root.
    static var userBlockList: URL {
        let home = NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Focus/block.txt")
    }

    /// Absolute path to the running executable, used to re-invoke ourselves.
    ///
    /// Symlinks are resolved because the sudoers drop-in whitelists the binary
    /// inside Focus.app by its real path. Invoked through the
    /// `/usr/local/bin/focus` symlink, an unresolved path makes every `sudo -n`
    /// call fall outside the rule, so the site block silently fails to apply —
    /// and the daemon's warning about it goes to /dev/null.
    static var selfExecutable: URL {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }
}
