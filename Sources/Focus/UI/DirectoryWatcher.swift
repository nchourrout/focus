import Foundation

/// Calls `onChange` on the main queue whenever one of `files` is created,
/// replaced, or deleted.
///
/// Watches the files' directories rather than the files, because every file
/// the menu bar reads is written atomically (temp file, then rename) or
/// deleted outright: a file watcher would be left holding the replaced inode
/// and see nothing after the first write. A rename into the directory is
/// exactly one directory event.
///
/// A directory event says something in the directory changed, not what. The
/// home directory in particular churns all day (shell history, other apps'
/// dotfiles), so each burst is checked against the watched files' identity
/// and modification time, and only a burst that touched one of them fires.
///
/// Events are coalesced: a burst inside `debounce` is checked once. A burst
/// that never pauses is still checked every `maxWait`, so steady unrelated
/// churn in the directory can't hold back the change that matters.
@MainActor
final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    /// When the first event of the current burst arrived.
    private var burstStart: DispatchTime?
    private let paths: [String]
    private var lastSignatures: [Signature?]
    private let debounce: TimeInterval
    private let maxWait: TimeInterval
    private let onChange: () -> Void

    init(files: [URL], debounce: TimeInterval = 0.1, maxWait: TimeInterval = 0.5,
         onChange: @escaping () -> Void) {
        // Resolved, so a file behind a symlinked directory (/etc is one) is
        // watched in the directory it is really renamed into.
        let paths = files.map { $0.resolvingSymlinksInPath().path }
        self.paths = paths
        self.lastSignatures = paths.map(Self.signature)
        self.debounce = debounce
        self.maxWait = maxWait
        self.onChange = onChange
        var seen = Set<String>()
        for dir in paths.map({ ($0 as NSString).deletingLastPathComponent }) where seen.insert(dir).inserted {
            let fd = open(dir, O_EVTONLY)
            guard fd >= 0 else {
                // The heartbeat still covers this directory, only later.
                Log.actions.error("cannot watch \(dir, privacy: .public): \(String(cString: strerror(errno)), privacy: .public)")
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.schedule() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    deinit {
        sources.forEach { $0.cancel() }
    }

    private func schedule() {
        pending?.cancel()
        let start = burstStart ?? .now()
        burstStart = start
        let deadline = min(DispatchTime.now() + debounce, start + maxWait)
        let item = DispatchWorkItem { [weak self] in
            self?.burstStart = nil
            self?.fireIfChanged()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: item)
    }

    private func fireIfChanged() {
        let signatures = paths.map(Self.signature)
        guard signatures != lastSignatures else { return }
        lastSignatures = signatures
        onChange()
    }

    /// What changes when a file is replaced, rewritten or removed: nil when
    /// it is missing, else its inode and modification time.
    private struct Signature: Equatable {
        let device: Int32
        let inode: UInt64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let size: Int64
    }

    private nonisolated static func signature(_ path: String) -> Signature? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Signature(
            device: info.st_dev, inode: info.st_ino,
            modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec,
            size: info.st_size
        )
    }
}
