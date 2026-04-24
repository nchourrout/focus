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

    /// Default block.txt, bundled as an SPM resource.
    static var defaultBlockFile: URL? {
        Bundle.module.url(forResource: "block", withExtension: "txt")
    }

    /// Absolute path to the running executable, used to re-invoke ourselves.
    static var selfExecutable: URL {
        if let path = Bundle.main.executablePath {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: CommandLine.arguments[0])
    }
}
