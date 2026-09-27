import Foundation

enum Paths {
    static let hosts = URL(fileURLWithPath: "/etc/hosts")
    static let hostsBackup = URL(fileURLWithPath: "/etc/hosts.backup")

    /// Advisory lock serializing concurrent /etc/hosts mutations (daemon phase
    /// boundaries vs menu bar toggle vs a terminal's `focus toggle`). Lives in
    /// /var/run, which only root (and group daemon) can write: in /tmp any
    /// user could create it first and hold the lock, stalling every unblock.
    static let hostsLockPath = "/var/run/com.nchourrout.focus.hosts.lock"

    /// Root-owned copy of the binary, the only path the sudoers rule trusts.
    /// See `SudoersInstaller`.
    static let privilegedHelperDir = "/Library/PrivilegedHelperTools/com.nchourrout.focus"
    static var privilegedHelper: URL {
        URL(fileURLWithPath: privilegedHelperDir).appendingPathComponent("focus")
    }

    /// What to run under `sudo -n`: the helper once installed, else the running
    /// binary, which is what drop-ins written before the helper existed name.
    static var sudoTarget: URL {
        FileManager.default.isExecutableFile(atPath: privilegedHelper.path)
            ? privilegedHelper : selfExecutable
    }

    static var pomodoroState: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".focus-pomodoro.json")
    }

    /// Serializes pomodoro start/stop/pause/resume/skip. See `PomodoroDaemon`.
    static var pomodoroLock: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".focus-pomodoro.lock")
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

    /// ~/Library/Application Support/Focus, the one directory Focus writes to.
    /// Resolved against the login user's home (`loginUser`) so that
    /// running under sudo doesn't steer the path into /var/root — everything
    /// below derives from here so no new file can miss that.
    static var appSupport: URL {
        let home = NSHomeDirectoryForUser(loginUser) ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Focus")
    }

    /// The user Focus acts for. Under sudo the process runs as root and
    /// NSUserName() says "root", which would steer every path into /var/root
    /// and silently swap the user's block list for the bundled one. sudo sets
    /// SUDO_USER itself, and the rule only admits the invoking user, so it is
    /// trustworthy here.
    static var loginUser: String {
        if geteuid() == 0, let user = ProcessInfo.processInfo.environment["SUDO_USER"], !user.isEmpty {
            return user
        }
        return NSUserName()
    }

    /// User-writable block list.
    static var userBlockList: URL { appSupport.appendingPathComponent("block.txt") }

    /// Append-only log of finished work sessions.
    static var history: URL { appSupport.appendingPathComponent("history.jsonl") }

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
