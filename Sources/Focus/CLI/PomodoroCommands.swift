import ArgumentParser
import Foundation

struct Pomodoro: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pomodoro",
        abstract: "run a pomodoro session with block + music",
        subcommands: [Start.self, Stop.self, PomodoroStatus.self]
    )
}

extension Pomodoro {
    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "start a pomodoro in the background"
        )

        // Every override is optional: omitted means "use the Settings value", so
        // the CLI and the menu bar start identical sessions. See `PomodoroPlan`.
        @Argument(help: "What you're working on")
        var goal: String

        @Option(help: ArgumentHelp("Work minutes (default: your Settings value)", valueName: "MINS"))
        var work: Int?

        @Option(name: .customLong("break"),
                help: ArgumentHelp("Break minutes (default: your Settings value)", valueName: "MINS"))
        var breakMinutes: Int?

        @Option(help: "Music preset or http(s):// stream URL (default: your Settings value, else FOCUS_MUSIC_URI)")
        var music: String?

        @Flag(inversion: .prefixedNo,
              exclusivity: .exclusive,
              help: "Block websites for the duration of the session (default: your Settings value)")
        var block: Bool?

        func validate() throws {
            if let work, work <= 0 {
                throw ValidationError("--work must be a positive integer")
            }
            if let breakMinutes, breakMinutes <= 0 {
                throw ValidationError("--break must be a positive integer")
            }
        }

        func run() throws {
            try PomodoroDaemon.launch(
                PomodoroPlan.fromSettings(
                    goal: goal,
                    workMinutes: work,
                    breakMinutes: breakMinutes,
                    block: block,
                    music: music
                )
            )
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "cancel the running pomodoro"
        )

        func run() {
            PomodoroDaemon.stop()
        }
    }

    struct PomodoroStatus: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "show current pomodoro state"
        )

        @Flag(name: .customLong("json"), help: "Machine-readable output.")
        var json: Bool = false

        func run() throws {
            let session = PomodoroSession.default
            guard let state = session.current else {
                if json {
                    print("{\"running\": false}")
                } else {
                    print("focus: no pomodoro running")
                }
                return
            }
            let (phase, timeLeft) = session.phase(of: state)
            if json {
                let payload = StatusPayload(
                    running: true,
                    goal: state.goal,
                    phase: phase.rawValue,
                    time_left: Int(timeLeft.rounded()),
                    work_end: state.workEnd,
                    break_end: state.breakEnd,
                    session: state.sessionNumber
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let data = try encoder.encode(payload)
                print(String(decoding: data, as: UTF8.self))
            } else {
                let mins = Int(timeLeft) / 60
                let secs = Int(timeLeft) % 60
                print(String(format: "focus: %@ — %d:%02d left — session %d — %@",
                             phase.rawValue, mins, secs, state.sessionNumber, state.goal))
            }
        }

        private struct StatusPayload: Encodable {
            let running: Bool
            let goal: String
            let phase: String
            let time_left: Int
            let work_end: TimeInterval
            let break_end: TimeInterval
            let session: Int
        }
    }
}

/// Hidden: the detached pomodoro daemon invocation.
struct PomodoroRun: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "_pomodoro-run",
        shouldDisplay: false
    )

    @Option var goal: String
    @Option(name: .customLong("work-end")) var workEnd: Double
    @Option(name: .customLong("break-end")) var breakEnd: Double
    /// Durations are also passed (not just end timestamps) so the daemon can
    /// roll its own next-cycle deadlines when auto-start is enabled.
    @Option(name: .customLong("work-minutes")) var workMinutes: Int
    @Option(name: .customLong("break-minutes")) var breakMinutes: Int
    @Option var music: String?
    @Flag(inversion: .prefixedNo) var block: Bool = true

    func run() {
        // The launching process already resolved everything; `--music` arrives as
        // a resolved stream URI, which maps back to its preset when it is one.
        let plan = PomodoroPlan(
            goal: goal,
            workMinutes: workMinutes,
            breakMinutes: breakMinutes,
            block: block,
            station: music.flatMap { Station(uri: $0) }
        )
        PomodoroDaemon.runDaemon(plan, workEnd: workEnd, breakEnd: breakEnd)
    }
}
