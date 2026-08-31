import Foundation
import Darwin

/// Signal handling for Focus's detached processes, in one place because getting
/// it wrong is silent.
///
/// Two rules, neither visible from the APIs being called, both already learned
/// the hard way once:
///
/// 1. Set the disposition to `SIG_IGN` before resuming any source. A signal
///    landing in that gap runs the default handler, which for SIGTERM and
///    SIGINT kills the process before it can clean up, and for SIGUSR1 and
///    SIGUSR2 kills it outright: a request to duck the music would stop it.
/// 2. Keep the returned sources alive for as long as delivery is wanted. A
///    released `DispatchSourceSignal` stops delivering, and with the
///    dispositions ignored above the signal then does nothing at all.
enum SignalTraps {
    /// Trap each signal in `handlers` and return the live sources. Callers hold
    /// them in a static: both users trap for the whole life of the process.
    ///
    /// Handlers run on `queue`, not on main, so one that needs the main thread
    /// hops there itself. The queue is the caller's so it can schedule its own
    /// work alongside them.
    static func install(on queue: DispatchQueue,
                        _ handlers: [(Int32, () -> Void)]) -> [DispatchSourceSignal] {
        handlers.map { sig, handler in
            Darwin.signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler(handler: handler)
            source.resume()
            return source
        }
    }
}
