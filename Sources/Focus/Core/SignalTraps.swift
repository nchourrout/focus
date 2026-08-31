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
/// 2. Keep the sources alive for as long as delivery is wanted. A released
///    `DispatchSourceSignal` stops delivering, and with the dispositions ignored
///    above the signal then does nothing at all. This type holds them itself
///    rather than handing them back: leaving that to the caller would put the
///    silent half of the contract back outside, which is what the first version
///    did and what both call sites then had to remember.
enum SignalTraps {
    /// Traps installed so far. Never released: both users trap for the whole
    /// life of a detached process, and there is no unregister case.
    private static var sources: [DispatchSourceSignal] = []

    /// Trap each signal in `handlers`.
    ///
    /// Handlers run on `queue`, not on main, so one that needs the main thread
    /// hops there itself. The queue is the caller's so it can schedule its own
    /// work alongside them, which `StreamPlayer` does for its exit watchdog.
    static func install(on queue: DispatchQueue, _ handlers: [(Int32, () -> Void)]) {
        // Every disposition first, in its own pass. Interleaving the two loops
        // would leave the signals later in the list still carrying their
        // defaults while the earlier sources are already live, which is rule 1
        // failing on exactly the signals it is there to protect: SIGUSR1 and
        // SIGUSR2 come last, and their default is to terminate.
        for (sig, _) in handlers {
            Darwin.signal(sig, SIG_IGN)
        }
        for (sig, handler) in handlers {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler(handler: handler)
            source.resume()
            sources.append(source)
        }
    }
}
