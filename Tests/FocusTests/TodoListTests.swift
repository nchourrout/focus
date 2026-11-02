import Testing
import Foundation
@testable import Focus

@Suite struct TodoListTests {

    /// A TodoList pointed at a fresh tmp directory that doesn't exist yet, so
    /// the first write also proves the directory gets created.
    private func makeList() -> TodoList {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("todos-\(UUID().uuidString)", isDirectory: true)
        return TodoList(url: dir.appendingPathComponent("todos.json"),
                        lockPath: dir.appendingPathComponent(".todos.lock").path)
    }

    private let calendar = Calendar.current
    private var noon: Date { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }
    private var tomorrowNoon: Date { calendar.date(byAdding: .day, value: 1, to: noon)! }

    @Test func addKeepsOrderAndTrimsTitles() throws {
        let list = makeList()
        try list.add("  write spec \n", now: noon)
        try list.add("reply to quote", now: noon)
        #expect(list.items(now: noon).map(\.title) == ["write spec", "reply to quote"])
    }

    @Test func anEmptyTitleIsRefused() {
        #expect(throws: TodoList.Failure.emptyTitle) { try makeList().add("   ") }
    }

    @Test func atMostThreeOpenTasks() throws {
        let list = makeList()
        for title in ["a", "b", "c"] { try list.add(title, now: noon) }
        #expect(throws: TodoList.Failure.full) { try list.add("d", now: noon) }
        // A finished task frees its slot.
        try list.setDone(.number(1), true, now: noon)
        try list.add("d", now: noon)
        #expect(list.items(now: noon).count == 4)
    }

    @Test func reopeningCountsAgainstTheCap() throws {
        let list = makeList()
        for title in ["a", "b", "c"] { try list.add(title, now: noon) }
        try list.setDone(.number(1), true, now: noon)
        try list.add("d", now: noon)
        #expect(throws: TodoList.Failure.full) { try list.setDone(.number(1), false, now: noon) }
    }

    @Test func doneAndUndoRoundtrip() throws {
        let list = makeList()
        try list.add("a", now: noon)
        #expect(try list.setDone(.number(1), true, now: noon).isDone)
        #expect(try !list.setDone(.number(1), false, now: noon).isDone)
    }

    @Test func refsResolveByNumberOrId() throws {
        let list = makeList()
        try list.add("a", now: noon)
        let b = try list.add("b", now: noon)
        try list.remove(.id(b.id), now: noon)
        #expect(list.items(now: noon).map(\.title) == ["a"])
        #expect(throws: TodoList.Failure.noSuchItem(.number(2))) { try list.remove(.number(2), now: noon) }
        #expect(throws: TodoList.Failure.noSuchItem(.id(b.id))) { try list.remove(.id(b.id), now: noon) }
        #expect(throws: TodoList.Failure.noSuchItem(.number(0))) { try list.remove(.number(0), now: noon) }
    }

    @Test func nextDayDropsDoneAndCarriesOpen() throws {
        let list = makeList()
        try list.add("finished", now: noon)
        try list.add("still open", now: noon)
        try list.setDone(.number(1), true, now: noon)
        #expect(list.items(now: noon).count == 2, "done tasks stay for the rest of the day")
        #expect(list.items(now: tomorrowNoon).map(\.title) == ["still open"])
    }

    @Test func aCorruptFileReadsAsEmptyButIsNeverOverwritten() throws {
        let list = makeList()
        try list.add("a", now: noon)
        try Data("not json".utf8).write(to: list.url)
        #expect(list.items(now: noon).isEmpty)
        #expect(throws: TodoList.Failure.unreadable(list.url)) { try list.add("b", now: noon) }
        #expect(try String(contentsOf: list.url, encoding: .utf8) == "not json")
    }
}
