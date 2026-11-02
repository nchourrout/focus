import ArgumentParser
import Foundation

/// `focus todo`: today's short task list, the same one the menu bar shows.
struct Todo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "todo",
        abstract: "keep a few tasks for today",
        subcommands: [List.self, Add.self, Done.self, Undo.self, Remove.self],
        defaultSubcommand: List.self
    )
}

extension Todo {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "show today's tasks (the default)"
        )

        @Flag(name: .customLong("json"), help: "Machine-readable output.")
        var json: Bool = false

        func run() throws {
            let items = TodoList.default.items()
            if json {
                let payload = items.enumerated().map { i, item in
                    ["number": i + 1, "title": item.title, "done": item.isDone] as [String: Any]
                }
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                return
            }
            guard !items.isEmpty else {
                print("focus: nothing for today yet. Add one with: focus todo add \"...\"")
                return
            }
            for line in Self.lines(items) { print(line) }
        }

        static func lines(_ items: [TodoList.Item]) -> [String] {
            items.enumerated().map { i, item in
                "  \(i + 1) [\(item.isDone ? "x" : " ")] \(item.title)"
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "add a task for today (at most \(TodoList.maxOpen) open)"
        )

        // Every remaining word, so the title needs no quotes.
        @Argument(parsing: .remaining, help: "The task")
        var words: [String] = []

        func run() throws {
            let item = try wrap { try TodoList.default.add(words.joined(separator: " ")) }
            print("focus: added \(item.title)")
        }
    }

    struct Done: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "done",
            abstract: "mark a task done"
        )

        @Argument(help: "Task number, as `focus todo` lists it")
        var number: Int

        func run() throws {
            let item = try wrap { try TodoList.default.setDone(.number(number), true) }
            print("focus: done: \(item.title)")
        }
    }

    struct Undo: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "undo",
            abstract: "mark a done task open again"
        )

        @Argument(help: "Task number, as `focus todo` lists it")
        var number: Int

        func run() throws {
            let item = try wrap { try TodoList.default.setDone(.number(number), false) }
            print("focus: reopened: \(item.title)")
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rm",
            abstract: "remove a task"
        )

        @Argument(help: "Task number, as `focus todo` lists it")
        var number: Int

        func run() throws {
            let item = try wrap { try TodoList.default.remove(.number(number)) }
            print("focus: removed \(item.title)")
        }
    }
}

/// Report a list rule the user broke (full list, bad number) as a plain
/// `focus: ...` line and exit 1, rather than as an ArgumentParser error dump.
private func wrap<T>(_ body: () throws -> T) throws -> T {
    do {
        return try body()
    } catch let failure as TodoList.Failure {
        FileHandle.standardError.write(Data("focus: \(failure.localizedDescription)\n".utf8))
        throw ExitCode.failure
    }
}
