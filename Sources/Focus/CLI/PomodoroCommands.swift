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

        @Argument(help: "What you're working on")
        var goal: String

        @Option(help: ArgumentHelp("Work minutes (default 25)", valueName: "MINS"))
        var work: Int = 25

        @Option(name: .customLong("break"), help: ArgumentHelp("Break minutes (default 5)", valueName: "MINS"))
        var breakMinutes: Int = 5

        @Option(help: "Music preset or spotify: URI (default FOCUS_SPOTIFY_URI)")
        var music: String?

        func validate() throws {
            if work <= 0 {
                throw ValidationError("--work must be a positive integer")
            }
            if breakMinutes <= 0 {
                throw ValidationError("--break must be a positive integer")
            }
        }

        func run() throws {
            try PomodoroDaemon.launch(
                goal: goal, workMinutes: work, breakMinutes: breakMinutes, music: music
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

        func run() {
            guard let state = PomodoroState.current else {
                if json {
                    print("{\"running\": false}")
                } else {
                    print("focus: no pomodoro running")
                }
                return
            }
            let (phase, timeLeft) = state.phase()
            if json {
                let escapedGoal = escapeJSONString(state.goal)
                print(
                    "{\"running\": true, \"goal\": \"\(escapedGoal)\", "
                    + "\"phase\": \"\(phase.rawValue)\", "
                    + "\"time_left\": \(Int(timeLeft.rounded())), "
                    + "\"work_end\": \(state.workEnd), "
                    + "\"break_end\": \(state.breakEnd)}"
                )
            } else {
                let mins = Int(timeLeft) / 60
                let secs = Int(timeLeft) % 60
                print(String(format: "focus: %@ — %d:%02d left — %@", phase.rawValue, mins, secs, state.goal))
            }
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
    @Option var music: String?

    func run() {
        PomodoroDaemon.runDaemon(goal: goal, workEnd: workEnd, breakEnd: breakEnd, music: music)
    }
}

/// Minimal JSON string escape for the handful of fields we emit.
func escapeJSONString(_ s: String) -> String {
    var out = ""
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case let c where c.value < 0x20:
            out += String(format: "\\u%04x", c.value)
        default:
            out.unicodeScalars.append(scalar)
        }
    }
    return out
}
