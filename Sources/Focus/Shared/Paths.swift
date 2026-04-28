import Foundation

enum Paths {
    static let hosts = URL(fileURLWithPath: "/etc/hosts")
    static let hostsBackup = URL(fileURLWithPath: "/etc/hosts.backup")

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
    static var selfExecutable: URL {
        if let path = Bundle.main.executablePath {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: CommandLine.arguments[0])
    }
}
