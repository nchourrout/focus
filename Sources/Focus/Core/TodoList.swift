import Foundation

/// The day's short task list, shared by the CLI (`focus todo`) and the menu bar.
///
/// Deliberately small: a few tasks for today, not a backlog. At most
/// `maxOpen` can be open at once, and the list resets itself at the day
/// boundary: tasks finished before today drop off, open ones carry over. That
/// rollover runs on every read, so nothing has to be awake at midnight.
///
/// One JSON file, written atomically under a lock, so a menu click and a
/// terminal command can't lose each other's change, and the menu bar's
/// directory watcher sees every write as a single rename.
struct TodoList {
    static let `default` = TodoList(url: Paths.todos, lockPath: Paths.todosLock.path)
    static let maxOpen = 3

    let url: URL
    let lockPath: String

    struct Item: Codable, Equatable, Identifiable {
        let id: UUID
        var title: String
        let createdAt: TimeInterval
        /// When it was marked done; nil while open.
        var doneAt: TimeInterval?

        var isDone: Bool { doneAt != nil }

        enum CodingKeys: String, CodingKey {
            case id, title
            case createdAt = "created_at"
            case doneAt = "done_at"
        }
    }

    /// Which task an edit means. The CLI says the number `focus todo` printed;
    /// the menu bar holds the id, because the list can change between the menu
    /// opening and the click, and a number would then name another task. Both
    /// are resolved under the lock, against the list being written.
    enum Ref: Equatable {
        case number(Int)
        case id(UUID)
    }

    enum Failure: Error, LocalizedError, Equatable {
        case emptyTitle
        case full
        case noSuchItem(Ref)
        case unreadable(URL)

        var errorDescription: String? {
            switch self {
            case .emptyTitle: return "a task needs a title"
            case .full: return "already \(TodoList.maxOpen) open tasks for today; finish or remove one first"
            case .noSuchItem(.number(let n)): return "no task \(n)"
            case .noSuchItem(.id): return "that task is gone"
            case .unreadable(let url): return "\(url.path) isn't a task list Focus can read; fix or delete it"
            }
        }
    }

    // MARK: Interface

    /// Today's list, in the order the tasks were added. An unreadable file
    /// reads as empty, which is right for display; see `load` otherwise.
    func items(now: Date = Date()) -> [Item] {
        (try? load(now: now)) ?? []
    }

    /// Today's list, throwing `.unreadable` rather than passing a damaged
    /// file off as an empty list.
    func load(now: Date = Date()) throws -> [Item] {
        Self.rolledOver(try read(), now: now)
    }

    @discardableResult
    func add(_ title: String, now: Date = Date()) throws -> Item {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.emptyTitle }
        return try mutate(now: now) { items in
            guard items.filter({ !$0.isDone }).count < Self.maxOpen else { throw Failure.full }
            let item = Item(id: UUID(), title: trimmed, createdAt: now.timeIntervalSince1970, doneAt: nil)
            items.append(item)
            return item
        }
    }

    /// Mark done (or open again).
    @discardableResult
    func setDone(_ ref: Ref, _ done: Bool, now: Date = Date()) throws -> Item {
        try mutate(now: now) { items in
            let i = try Self.index(of: ref, in: items)
            // Reopening counts against the cap like adding does.
            if !done, items[i].isDone, items.filter({ !$0.isDone }).count >= Self.maxOpen {
                throw Failure.full
            }
            items[i].doneAt = done ? (items[i].doneAt ?? now.timeIntervalSince1970) : nil
            return items[i]
        }
    }

    @discardableResult
    func remove(_ ref: Ref, now: Date = Date()) throws -> Item {
        try mutate(now: now) { items in
            items.remove(at: try Self.index(of: ref, in: items))
        }
    }

    // MARK: Internals (tested via @testable)

    /// Drop tasks finished before the start of `now`'s day. Open tasks stay,
    /// however old: carrying them over is the point of a list.
    static func rolledOver(_ items: [Item], now: Date) -> [Item] {
        let startOfDay = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        return items.filter { ($0.doneAt ?? .infinity) >= startOfDay }
    }

    /// `.number` is 1-based, as `focus todo` lists it.
    private static func index(of ref: Ref, in items: [Item]) throws -> Int {
        switch ref {
        case .number(let n) where n >= 1 && n <= items.count:
            return n - 1
        case .id(let id):
            if let i = items.firstIndex(where: { $0.id == id }) { return i }
        default:
            break
        }
        throw Failure.noSuchItem(ref)
    }

    // MARK: Private

    private func mutate<T>(now: Date, _ body: (inout [Item]) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return try FileLock(path: lockPath).withExclusiveLock {
            var items = Self.rolledOver(try read(), now: now)
            let result = try body(&items)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: url, options: .atomic)
            return result
        }
    }

    /// A missing file is an empty list. One that exists but doesn't decode (a
    /// hand edit gone wrong, a newer build's format) throws instead: reading it
    /// as empty is fine for display, but writing that back would wipe it.
    private func read() throws -> [Item] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([Item].self, from: Data(contentsOf: url))
        } catch {
            throw Failure.unreadable(url)
        }
    }
}
