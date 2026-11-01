//  🖥️ TUI — A Terminal UI framework for Swift
//  UnreadQuitKeyWatch.swift
//
//  While the user's quit key asks before it quits, the terminal driver has given
//  it up, so nothing but the app reads it, and a hung app reads nothing. A
//  thread of its own looks at input the main loop has left unread, and quits
//  if the key is in it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// Threads, `poll` and a process group to signal are POSIX; wasip1 has no driver
// and no quit key.
#if !canImport(WASILibc)

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - Standard input, shared

/// Standard input, as the main loop and ``UnreadQuitKeyWatch`` share it: the
/// loop reads through here (`Terminal.readSource`), and the watch takes what the
/// loop has left unread into ``held``, from which the loop's next read comes first,
/// so no key is lost or read out of order.
///
/// `@unchecked Sendable`: every stored property is touched only under ``lock``.
final class SharedStandardInput: @unchecked Sendable {
    /// The descriptor: standard input, unless a test drives a pipe.
    let descriptor: Int32

    private let lock = NSLock()

    /// What the watch has read and the loop has not, oldest first.
    private var held: [UInt8] = []

    /// How many times the loop has asked to read: how the watch tells a loop
    /// that is reading from one that has stopped.
    private var reads = 0

    /// The most the watch holds: far more than a terminal's input queue, so it
    /// takes a long stall with keys held down to get here, and past it the
    /// driver's own limit applies to what is left in its queue.
    private static let holdLimit = 65_536

    init(descriptor: Int32 = STDIN_FILENO) {
        self.descriptor = descriptor
    }

    /// What the loop reads: what is held, or else what the descriptor has.
    ///
    /// Under the lock, so the watch cannot read between the loop finding
    /// nothing held and the loop reading the descriptor, and put later keys ahead
    /// of earlier ones. The descriptor's read does not block: raw mode has `VMIN`
    /// and `VTIME` 0.
    func read(into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
        guard let base = buffer.baseAddress else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        reads &+= 1
        if !held.isEmpty {
            let count = min(held.count, buffer.count)
            held.withUnsafeBufferPointer { base.update(from: $0.baseAddress!, count: count) }
            held.removeFirst(count)
            return count
        }
        while true {
            let count = readDescriptor(descriptor, base, buffer.count)
            // Retry only on EINTR (a signal interrupted the read before any byte
            // arrived); surface everything else — n >= 0, or a real error / the
            // benign EAGAIN of a non-blocking fd with no data — unchanged, which
            // `appendDrain`'s `n > 0` check already handles.
            if count < 0, errno == EINTR { continue }
            return count
        }
    }

    /// Whether the loop has bytes to read that the descriptor would not tell
    /// it of.
    var holdsInput: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !held.isEmpty
    }

    /// How many times the loop has asked to read.
    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    /// Reads what the descriptor has waiting into ``held``, up to the limit.
    ///
    /// - Returns: All that is held, oldest first.
    func holdWaitingInput() -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        var chunk = [UInt8](repeating: 0, count: 4096)
        while held.count < Self.holdLimit {
            let count = chunk.withUnsafeMutableBytes { readDescriptor(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            held.append(contentsOf: chunk[..<count])
        }
        return held
    }
}

/// `read(2)`, where a method of that name is in the way.
private func readDescriptor(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
    #if canImport(Darwin)
        Darwin.read(descriptor, buffer, count)
    #elseif canImport(Glibc)
        Glibc.read(descriptor, buffer, count)
    #else
        Musl.read(descriptor, buffer, count)
    #endif
}

// MARK: - Finding the key

/// Whether the user's quit key is among bytes the main loop has not read.
enum UnreadQuitKey {
    /// Whether `bytes` hold the key, by its byte (``byte``, in a legacy encoding)
    /// or its kitty keyboard protocol report (`CSI 92;5u` for ⌃\\), outside
    /// a bracketed paste: pasted text is not a key press.
    ///
    /// A report counts with the locks on (Caps Lock and Num Lock are in the
    /// modifiers) and as a press or a repeat, not a release, and with no other
    /// modifier: ⌃⌥\\ is a chord of its own under the protocol.
    ///
    /// - Parameters:
    ///   - bytes: Unread input, from where the loop stopped reading: so it
    ///     starts between sequences, at the start of a paste or outside one.
    ///   - byte: The quit key's byte.
    static func isIn(_ bytes: [UInt8], byte: UInt8) -> Bool {
        let codepoint = KeyEvent.controlChord(sending: byte).flatMap { chord -> Int? in
            guard case .character(let character) = chord.key else { return nil }
            return character.asciiValue.map(Int.init)
        }
        var inPaste = false
        var index = 0
        while index < bytes.count {
            let current = bytes[index]
            guard current == 0x1B, index + 1 < bytes.count, bytes[index + 1] == 0x5B else {
                if current == byte, !inPaste { return true }
                index += 1
                continue
            }
            // A CSI sequence: parameters to the final byte, 0x40–0x7E.
            var end = index + 2
            while end < bytes.count, !(0x40...0x7E).contains(bytes[end]) { end += 1 }
            guard end < bytes.count else { return false }
            let parameters = bytes[(index + 2)..<end]
            if bytes[end] == 0x7E {  // ~
                if parameters.elementsEqual("200".utf8) { inPaste = true }
                if parameters.elementsEqual("201".utf8) { inPaste = false }
            } else if bytes[end] == 0x75, !inPaste, let codepoint, isReport(parameters, of: codepoint) {  // u
                return true
            }
            index = end + 1
        }
        return false
    }

    /// Whether the parameters of a `CSI … u` are a report of Control and the key
    /// `codepoint`, going down or repeating: `key[:alternates];modifiers[:event][;text]`,
    /// the modifiers being one more than their bits (Shift 1, Alt 2, Control 4,
    /// Super 8, Hyper 16, Meta 32, Caps Lock 64, Num Lock 128).
    private static func isReport(_ parameters: ArraySlice<UInt8>, of codepoint: Int) -> Bool {
        let fields = parameters.split(separator: 0x3B, omittingEmptySubsequences: false)
        guard fields.count >= 2 else { return false }
        func numbers(_ field: ArraySlice<UInt8>) -> [Int?] {
            field.split(separator: 0x3A, omittingEmptySubsequences: false).map { ASCIIDecimal.value(of: $0) }
        }
        let modifiers = numbers(fields[1])
        guard numbers(fields[0]).first == codepoint, case .some(.some(let encoded)) = modifiers.first, encoded >= 1
        else { return false }
        let locks = 64 | 128
        guard (encoded - 1) & ~locks == 4 else { return false }
        let release = 3
        return modifiers.count < 2 || modifiers[1] != release
    }
}

// MARK: - The watch

/// A thread that quits the app when the user's quit key, which the main loop
/// would have asked about, sits unread: a ⌃\\ the loop hasn't acknowledged after
/// ``grace`` (two seconds).
///
/// While the quit key asks before it quits (`QuitConfirmation`), the driver must
/// not act on its byte: the first ⌃\\ would end every process in the group
/// the moment it was pressed, before anything could ask. So it is masked, and the
/// key is the app's. An app that has hung can't answer it, and ⌃\\ is how a hung
/// app is ended, so something else has to read it. That can't be a look: a
/// terminal has no way of peeking at its input queue. So when input has waited
/// that long with no read by the loop, this reads it, into
/// ``SharedStandardInput``'s hold, and looks.
///
/// - The key among it: `SIGQUIT` to the process group, as the driver would have
///   sent, which leaves the terminal as a quit does (`FatalSignalTerminalRestore`).
/// - Not among it: the bytes stay held, the next read by the loop gets them, and
///   a loop that was only slow finds what was typed in order.
///
/// So a hung app dies at its first ⌃\\, two seconds later. So does one busy for
/// more than that on the main thread: it looks the same from here, and
/// that is the rule the owner set (a ⌃\\ the loop doesn't acknowledge promptly
/// quits at once). Once the loop has been found not to be reading, later input
/// is looked at without waiting again, until it reads.
///
/// Not behind the lock the terminal's writes take, unlike `StallWatchdog`, which
/// has to write and so has to wait for a frame to finish: a main thread stuck in
/// a write to a terminal that isn't reading is hung too.
///
/// Costs nothing while input is read: the thread sleeps in `poll` until input
/// arrives, and looks every tenth of a second for as long as it waits unread.
/// Disarmed, it waits for arming without watching at all. A terminal that hangs up
/// ends it.
final class UnreadQuitKeyWatch: @unchecked Sendable {
    /// How long input may wait unread before it is looked at.
    let grace: TimeInterval

    /// Standard input, as the loop reads it.
    let input: SharedStandardInput

    /// Guards the two below, and is what the thread waits for arming on.
    private let condition = NSCondition()

    /// The quit key's byte, while the thread is to watch for it.
    private var armedByte: UInt8?

    /// Whether the thread is to end.
    private var stopped = false

    /// Quits: `SIGQUIT` to the process group, unless a test hands in another.
    private let quit: @Sendable () -> Void

    /// Told when input has been held, for the loop to be woken: it may be waiting
    /// on a descriptor that has nothing more to say. Set before the thread starts.
    private var inputHeld: @Sendable () -> Void = {}

    /// The pipe that wakes the thread from `poll` to stop: read end, write
    /// end; -1 before ``start()``.
    private var wakeRead: Int32 = -1
    private var wakeWrite: Int32 = -1

    /// Signalled when the thread has ended.
    private let ended = DispatchSemaphore(value: 0)
    private var started = false

    /// How often waiting input is looked at.
    private static let checkInterval: TimeInterval = 0.1

    /// - Parameters:
    ///   - input: Standard input, unless a test drives a pipe.
    ///   - grace: How long input may wait unread before it is looked at.
    ///   - quit: What quits.
    init(
        input: SharedStandardInput = SharedStandardInput(), grace: TimeInterval = 2.0,
        quit: @escaping @Sendable () -> Void = { _ = kill(0, SIGQUIT) }
    ) {
        self.input = input
        self.grace = grace
        self.quit = quit
    }

    /// Watches for the quit key `byte`, or, for `nil`, stops watching until armed
    /// again.
    func setArmed(byte: UInt8?) {
        condition.lock()
        defer { condition.unlock() }
        guard byte != armedByte else { return }
        armedByte = byte
        condition.broadcast()
    }

    /// Whether the watch is armed, for tests.
    var isArmed: Bool {
        condition.lock()
        defer { condition.unlock() }
        return armedByte != nil
    }

    /// Starts the thread. Does nothing a second time, or where the pipe that
    /// stops it cannot be made.
    ///
    /// - Parameter inputHeld: Told when input has been held for the loop, which
    ///   may be waiting on a descriptor that has nothing more to say.
    func start(inputHeld: @escaping @Sendable () -> Void = {}) {
        guard !started else { return }
        self.inputHeld = inputHeld
        var ends: [Int32] = [-1, -1]
        guard pipe(&ends) == 0 else { return }
        wakeRead = ends[0]
        wakeWrite = ends[1]
        started = true
        let thread = Thread { [self] in
            watch()
            ended.signal()
        }
        thread.name = "TUI quit key watch"
        thread.start()
    }

    /// Ends the thread, waiting up to a second for it, and closes its pipe once
    /// it has ended.
    func stop() {
        guard started else { return }
        started = false
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
        var byte: UInt8 = 0
        _ = write(wakeWrite, &byte, 1)
        if ended.wait(timeout: .now() + 1) == .success {
            close(wakeRead)
            close(wakeWrite)
        }
    }

    /// The thread's loop.
    private func watch() {
        condition.lock()
        defer { condition.unlock() }
        // The read count when input was last held and the loop had not read
        // since: the loop has stopped reading, and needs no grace to prove it.
        var heldAtReads: Int?
        while true {
            while !stopped, armedByte == nil { condition.wait() }
            if stopped { return }

            condition.unlock()
            let woke = StandardInputWait.untilInput(on: input.descriptor, orWake: wakeRead)
            condition.lock()
            switch woke {
            case .stop: return
            case .hangUp:
                stopped = true
                return
            case .input: break
            }
            if stopped { return }
            if watchWaitingInput(heldAtReads: &heldAtReads) { return }
        }
    }

    /// Watches input that is waiting, until it is read or ``grace`` passes with
    /// no read by the loop, and then looks at it. Holds the lock but while it
    /// sleeps; returns whether the thread is to end.
    private func watchWaitingInput(heldAtReads: inout Int?) -> Bool {
        var readsSeen = input.readCount
        var waitingSince = Date()
        if heldAtReads == readsSeen { waitingSince = .distantPast }
        while true {
            if waitingSince != .distantPast {
                let check = min(waitingSince.addingTimeInterval(grace), Date(timeIntervalSinceNow: Self.checkInterval))
                while !stopped, armedByte != nil, condition.wait(until: check) {}
            }
            if stopped { return true }
            guard let byte = armedByte, StandardInputWait.inputIsWaiting(on: input.descriptor) else { return false }
            if input.readCount != readsSeen {
                readsSeen = input.readCount
                waitingSince = Date()
            } else if Date() >= waitingSince.addingTimeInterval(grace) {
                let unread = input.holdWaitingInput()
                heldAtReads = input.readCount
                if UnreadQuitKey.isIn(unread, byte: byte) {
                    quit()
                    return true
                }
                inputHeld()
                return false
            }
        }
    }
}

#endif
