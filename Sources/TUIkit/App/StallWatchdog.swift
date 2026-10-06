//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StallWatchdog.swift
//
//  Under the kitty keyboard protocol the terminal sends ⌃\ as a report the
//  driver never sees, so a hung app could not be quit by it. A thread of its
//  own notices input the main loop has stopped reading and pops the
//  protocol's flags, so the next ⌃\ is the byte the driver quits on.
//
//  Created by Wade Tregaskis
//  License: MIT

// Threads, `poll` and a pipe are POSIX; wasip1 has no driver to hand the key
// back to.
#if !canImport(WASILibc)

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - What the main thread and the watchdog share

/// The lock every write to the terminal takes, and what the stall watchdog
/// and the main loop tell each other under it.
///
/// One lock for both, so the watchdog's pop can never land inside a frame:
/// it writes only while it holds the lock, and the main thread holds it for
/// the whole of each write (`Terminal.writeImmediate`, a frame's flush). If
/// the main thread is hung INSIDE a write — the terminal not reading what it
/// is sent — the watchdog waits behind it and pops nothing: writing over a
/// frame half sent would corrupt it, and a terminal that is not reading would
/// not read the pop either. Writes outside `Terminal` (an app's own `print`,
/// a crash report) do not take it.
///
/// `@unchecked Sendable`: every stored property is read and written only
/// under ``condition``.
final class TerminalWriteGate: @unchecked Sendable {
    /// The lock, and what the watchdog waits on.
    fileprivate let condition = NSCondition()

    /// Whether the watchdog may pop the flags: they are pushed, the user's
    /// quit key is live in the driver and would stay so after the pop, and
    /// no suspend or teardown is under way (`Terminal.refreshStallWatch()`).
    fileprivate var armed = false

    /// Whether the watchdog popped the flags and the main loop has not yet
    /// been told (``noteDrain()``).
    fileprivate var popped = false

    /// How many times the main loop has drained its input: what the watchdog
    /// watches for a change.
    fileprivate var drains = 0

    /// Whether the watchdog is to end.
    fileprivate var stopped = false

    /// Runs `body`, a write to the terminal, holding the gate.
    func withWriteLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        condition.lock()
        defer { condition.unlock() }
        return try body()
    }

    /// The main loop drained its input, as it does once an iteration: the
    /// one store the watchdog costs a running loop.
    ///
    /// - Returns: Whether the watchdog popped the kitty keyboard protocol's
    ///   flags since the last drain, while the loop was stalled: the loop
    ///   pushes them again (`Terminal.recoverFromStall()`).
    func noteDrain() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        drains &+= 1
        let wasPopped = popped
        popped = false
        return wasPopped
    }

    /// Lets the watchdog pop the flags, or stops it until armed again.
    func setArmed(_ armed: Bool) {
        condition.lock()
        defer { condition.unlock() }
        guard armed != self.armed else { return }
        self.armed = armed
        condition.broadcast()
    }

    /// Disarms the watchdog and takes back a pop of its the loop has not heard
    /// of, in one step: the main thread is about to pop the flags itself (a
    /// suspend, the teardown), so there is nothing to push again on the
    /// watchdog's behalf, and from here the watchdog pops nothing.
    ///
    /// One step, under the lock the watchdog pops under, so no pop of its can
    /// fall between the two: one that did would be left for the loop's next
    /// drain to push back, after a resume that has pushed already.
    ///
    /// - Returns: Whether the watchdog had popped the flags: then the main
    ///   thread's pop would be a second one, of an entry this process never
    ///   pushed, and is not to be written.
    func disarmForPop() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let wasPopped = popped
        popped = false
        if armed {
            armed = false
            condition.broadcast()
        }
        return wasPopped
    }

    /// Whether the watchdog may pop, for tests.
    var isArmed: Bool { withWriteLock { armed } }

    /// Whether the watchdog has ended or is to end — stopped, or the
    /// terminal hung up — for tests.
    var isStopped: Bool { withWriteLock { stopped } }
}

// MARK: - The watchdog

/// A thread that pops the kitty keyboard protocol's flags when the main loop
/// has left input unread for ``grace`` (1.5 s), so a hung app can be quit by
/// ⌃\ under the protocol, as anywhere else.
///
/// Where the terminal speaks the protocol, TUIkit pushes its "disambiguate"
/// flag, and the terminal sends ⌃\ as the report `CSI 92;5u`, not the byte
/// 0x1C the driver turns into `SIGQUIT`. A running app reads the report and
/// quits itself (`QuitKeyReport`); a hung one reads nothing. So: when input
/// has been waiting that long with no drain by the loop — the user pressing
/// keys at an app that does not answer, the first ⌃\'s report among them —
/// the watchdog writes `CSI < u`. The terminal sends keys in the legacy
/// encoding from then on, and the next ⌃\ is 0x1C, which the driver quits on
/// whatever the app is doing. The report that tripped it stays unread: under
/// the protocol it takes a second ⌃\, about two seconds after the first, to
/// quit a hung app.
///
/// A loop that was only slow (a frame that took two seconds) finds the flags
/// popped when it drains again and pushes them back
/// (`TerminalWriteGate.noteDrain()`); the keys between come in both
/// encodings, and the parser reads both while the flags are, as far as it
/// knows, still pushed.
///
/// Costs nothing while input is read: the thread sleeps in `poll` until
/// input arrives, looks at it on a timer (every quarter second) for as long
/// as it waits unread, and goes back to sleep once it is read. Disarmed —
/// the flags not pushed, a suspend, or a binding of the app's on a chord the
/// quit key's byte could be once popped (`Terminal.refreshStallWatch()`) —
/// it waits for arming without watching at all. A terminal that hangs up
/// ends it.
final class StallWatchdog: @unchecked Sendable {
    /// How long input may wait unread before the flags are popped.
    let grace: TimeInterval

    private let gate: TerminalWriteGate
    private let input: Int32
    private let output: Int32

    /// The pipe that wakes the thread from `poll` to stop: read end, write
    /// end; -1 before ``start()``.
    private var wakeRead: Int32 = -1
    private var wakeWrite: Int32 = -1

    /// Signalled when the thread has ended.
    private let ended = DispatchSemaphore(value: 0)
    private var started = false

    /// What the watchdog writes to pop the flags: `KeyboardProtocolQuery.pop`.
    private static let pop = Array(KeyboardProtocolQuery.pop.utf8)

    /// - Parameters:
    ///   - gate: The lock the terminal's writes take, and the state shared
    ///     with the main loop.
    ///   - input: Standard input, unless a test drives a pipe.
    ///   - output: Standard output, unless a test reads a pipe.
    ///   - grace: How long input may wait unread before the flags are popped.
    init(
        gate: TerminalWriteGate, input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO,
        grace: TimeInterval = 1.5
    ) {
        self.gate = gate
        self.input = input
        self.output = output
        self.grace = grace
    }

    /// Starts the thread. Does nothing a second time, or where the pipe that
    /// stops it cannot be made.
    func start() {
        guard !started else { return }
        var ends: [Int32] = [-1, -1]
        guard pipe(&ends) == 0 else { return }
        wakeRead = ends[0]
        wakeWrite = ends[1]
        started = true
        let thread = Thread { [self] in
            watch()
            ended.signal()
        }
        thread.name = "TUIkit stall watchdog"
        thread.start()
    }

    /// Ends the thread, waiting up to a second for it — it may be waiting
    /// behind a write the main thread cannot finish, which is no reason to
    /// hold up the teardown — and closes its pipe once it has ended.
    func stop() {
        guard started else { return }
        started = false
        gate.condition.lock()
        gate.stopped = true
        gate.condition.broadcast()
        gate.condition.unlock()
        var byte: UInt8 = 0
        _ = write(wakeWrite, &byte, 1)
        if ended.wait(timeout: .now() + 1) == .success {
            close(wakeRead)
            close(wakeWrite)
        }
    }

    /// The thread's loop. Holds the gate's lock except while it sleeps.
    private func watch() {
        let condition = gate.condition
        condition.lock()
        defer { condition.unlock() }
        while true {
            while !gate.stopped, !gate.armed { condition.wait() }
            if gate.stopped { return }

            // Asleep until input arrives — or the pipe says stop — not holding
            // the lock, so writes and drains go on.
            condition.unlock()
            let woke = waitForInput()
            condition.lock()
            switch woke {
            case .stop: return
            case .hangUp:
                // No terminal to read from, and nothing a pop could reach.
                gate.stopped = true
                return
            case .input: break
            }
            if gate.stopped { return }
            if gate.armed, watchWaitingInput() { return }
        }
    }

    /// Watches input that is waiting, until it is read or ``grace`` passes
    /// with the loop draining nothing — then pops. Holds the lock but while
    /// it sleeps; returns whether the watchdog is to end.
    ///
    /// The clock starts again whenever the loop drains while input is still
    /// waiting: a loop reading a flood of input is reading, and keys typed at
    /// a loop that read the last ones and then stalled (a slow frame) are
    /// counted from when they came. So the input is looked at every
    /// ``checkInterval`` while it waits — and only then.
    private func watchWaitingInput() -> Bool {
        let condition = gate.condition
        var drainsSeen = gate.drains
        var waitingSince = Date()
        while true {
            let check = min(waitingSince.addingTimeInterval(grace), Date(timeIntervalSinceNow: Self.checkInterval))
            while !gate.stopped, gate.armed, condition.wait(until: check) {}
            if gate.stopped { return true }
            guard gate.armed, inputIsWaiting() else { return false }
            if gate.drains != drainsSeen {
                drainsSeen = gate.drains
                waitingSince = Date()
            } else if Date() >= waitingSince.addingTimeInterval(grace) {
                // Stalled: pop, holding the lock, so no frame is mid-write —
                // and only a pop the terminal was sent whole counts as one.
                // One it could not take stays armed, and is tried again a
                // grace later.
                guard writePop() else { return false }
                gate.popped = true
                gate.armed = false
                return false
            }
        }
    }

    /// How often waiting input is looked at.
    private static let checkInterval: TimeInterval = 0.25

    private enum Woke { case input, stop, hangUp }

    /// Sleeps in `poll` until ``input`` has bytes, the terminal hangs up,
    /// or the wake pipe says stop.
    private func waitForInput() -> Woke {
        while true {
            var targets = [
                pollfd(fd: input, events: Int16(POLLIN), revents: 0),
                pollfd(fd: wakeRead, events: Int16(POLLIN), revents: 0),
            ]
            let ready = poll(&targets, 2, -1)
            if ready < 0 {
                if errno == EINTR { continue }
                return .hangUp
            }
            if targets[1].revents != 0 { return .stop }
            // A hang-up first: a terminal gone is readable for ever, with
            // nothing to read, and `poll` says it is gone — POLLHUP for a pty
            // whose terminal closed and for a pipe whose writer did (measured
            // on Darwin 24.6; Linux's pty and pipe drivers set it too, by
            // their source), POLLNVAL for a descriptor that is none.
            if targets[0].revents & Self.gone != 0 { return .hangUp }
            // Readable is input, and nothing more is asked here — above all
            // not `FIONREAD`, whose 0 would read as an end of file. The loop
            // reads this descriptor on its own thread, and a read between the
            // `poll` and the `ioctl` makes a keystroke's 0 too: each arrival
            // a chance to end the watch for good, silently (round 6; the race
            // `StdinArrivalNotifier.handleReadable()` records making every
            // Linux CI lane deaf). Bytes the loop took first are only input no
            // longer waiting, which ``inputIsWaiting()`` finds.
            if targets[0].revents & Int16(POLLIN) != 0 { return .input }
        }
    }

    /// What `poll` reports for a descriptor with no terminal behind it any
    /// more.
    private static let gone = Int16(POLLHUP | POLLERR | POLLNVAL)

    /// Whether ``input`` still has bytes waiting — a drain by something
    /// other than the loop (a startup exchange) takes them too.
    ///
    /// Here the race ``waitForInput()`` steers clear of costs nothing: bytes
    /// the loop read between the `poll` and the count are not waiting, which
    /// is the answer, and a loop that reads is draining, which starts the
    /// grace again anyway. A descriptor readable with nothing to count
    /// (`/dev/null`) never has input waiting, so no grace pops for it.
    private func inputIsWaiting() -> Bool {
        var target = pollfd(fd: input, events: Int16(POLLIN), revents: 0)
        return poll(&target, 1, 0) > 0 && target.revents & Self.gone == 0 && target.revents & Int16(POLLIN) != 0
            && !StdinArrivalNotifier.isAtEndOfInput(input)
    }

    /// Writes the pop whole, or not at all.
    ///
    /// Not at all where the terminal has no room for it — standard output
    /// left non-blocking by another program (`Terminal.writeAll`) and full:
    /// the main thread is not writing (the lock is held), so a terminal that
    /// takes nothing now is not reading. Nothing has gone, and the watchdog
    /// tries again a grace later. Whole once the first byte has gone, waiting
    /// for room as a blocking write would (`Terminal.waitForRoom`): the
    /// sequence's head without its tail would run into the next frame's
    /// bytes, and the terminal would read them as the rest of it.
    ///
    /// - Returns: Whether the terminal was sent the whole of it: only then
    ///   are the flags popped.
    private func writePop() -> Bool {
        var room = pollfd(fd: output, events: Int16(POLLOUT), revents: 0)
        guard poll(&room, 1, 0) > 0, room.revents & Int16(POLLOUT) != 0 else { return false }
        return Self.pop.withUnsafeBufferPointer { bytes in
            guard let base = bytes.baseAddress else { return false }
            var written = 0
            while written < bytes.count {
                let result = write(output, base + written, bytes.count - written)
                if result > 0 {
                    written += result
                    continue
                }
                // `errno` is thread-local and transient: read it first.
                let error = result < 0 ? errno : 0
                if error == EINTR { continue }
                let full = error == EAGAIN || error == EWOULDBLOCK
                guard full, written > 0, Terminal.waitForRoom(on: output) else { return false }
            }
            return true
        }
    }
}

#endif
