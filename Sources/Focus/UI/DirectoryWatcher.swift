import Foundation

/// Calls `onChange` on the main queue whenever an entry is added to, removed
/// from, or renamed within one of `directories`.
///
/// Watches directories rather than files because every file the menu bar reads
/// is written atomically (temp file, then rename) or deleted outright: a file
/// watcher would be left holding the replaced inode and see nothing after the
/// first write. A rename into the directory is exactly one directory event.
///
/// Events are coalesced: a burst inside `debounce` fires `onChange` once. A
/// burst that never pauses still fires every `maxWait`, so steady unrelated
/// churn in the directory can't hold back the change that matters.
@MainActor
final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    /// When the first event of the current burst arrived.
    private var burstStart: DispatchTime?
    private let debounce: TimeInterval
    private let maxWait: TimeInterval
    private let onChange: () -> Void

    init(directories: [String], debounce: TimeInterval = 0.1, maxWait: TimeInterval = 0.5,
         onChange: @escaping () -> Void) {
        self.debounce = debounce
        self.maxWait = maxWait
        self.onChange = onChange
        for dir in directories {
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
            self?.onChange()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: item)
    }
}
