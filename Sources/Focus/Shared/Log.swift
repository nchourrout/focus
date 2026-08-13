import os

/// Unified Logging, for the parts of Focus that have nowhere else to complain.
///
/// Detached processes — the pomodoro daemon, the stream player, the afplay loop
/// — are spawned with their stdio on `/dev/null` (see `Shell.configured`) and
/// outlive the shell that started them, so anything they write to stderr is
/// lost. That is how a failing `sudo -n block` stayed invisible: the daemon
/// warned about it on every session and nobody ever saw a word.
///
/// Read it with Console.app filtered on the subsystem, or:
///
///     log stream --predicate 'subsystem == "com.nchourrout.focus"'
///     log show --last 30m --predicate 'subsystem == "com.nchourrout.focus"'
///
/// Interpolated values are marked `.public` — none of it is sensitive, and
/// redacted logs are useless for the thing they exist to diagnose.
enum Log {
    static let subsystem = "com.nchourrout.focus"

    /// The pomodoro daemon: the run loop and its block calls.
    static let daemon = Logger(subsystem: subsystem, category: "daemon")
    /// Music: the stream player and the afplay loop.
    static let playback = Logger(subsystem: subsystem, category: "playback")
    /// Menu bar actions that spawn the CLI.
    static let actions = Logger(subsystem: subsystem, category: "actions")
    static let launchAtLogin = Logger(subsystem: subsystem, category: "launch-at-login")
    /// Cleanup on app quit.
    static let terminate = Logger(subsystem: subsystem, category: "terminate")
}
