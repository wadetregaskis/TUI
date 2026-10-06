//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StallWatchdogTests.swift
//
//  The stall watchdog pops the kitty keyboard protocol's flags when the main
//  loop leaves input unread, so ⌃\ reaches the driver as its byte. Driven over
//  pipes standing in for the terminal, with a short grace; and its arming,
//  through a scripted terminal.
//
//  Created by Wade Tregaskis
//  License: MIT

#if !canImport(WASILibc)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import Foundation
import Testing

@testable import TUIkit

/// A watchdog over two pipes: one it watches as the terminal's input, one it
/// writes its pop to.
private final class Rig {
    let gate = TerminalWriteGate()
    let watchdog: StallWatchdog
    private var input: [Int32]
    private let output: [Int32]

    init(grace: TimeInterval = 0.3) {
        var input: [Int32] = [-1, -1]
        var output: [Int32] = [-1, -1]
        _ = pipe(&input)
        _ = pipe(&output)
        self.input = input
        self.output = output
        watchdog = StallWatchdog(gate: gate, input: input[0], output: output[1], grace: grace)
        watchdog.start()
    }

    /// A key arrives.
    func type() {
        var byte = UInt8(ascii: "k")
        _ = write(input[1], &byte, 1)
    }

    /// The terminal goes: the input's writing end closes.
    func hangUp() {
        close(input[1])
        // Never closed twice: by then the number may be another test's.
        input[1] = -1
    }

    /// The loop reads it, as `drainTerminalEvents` does.
    func drain() -> Bool {
        var byte: UInt8 = 0
        _ = read(input[0], &byte, 1)
        return gate.noteDrain()
    }

    /// Standard output left non-blocking by another program, and full: what
    /// the terminal does with a pop it cannot take. Returns how many bytes of
    /// filler went in.
    func fillOutput() -> Int {
        _ = fcntl(output[1], F_SETFL, fcntl(output[1], F_GETFL) | O_NONBLOCK)
        var filled = 0
        let chunk = [UInt8](repeating: Self.filler, count: 512)
        while true {
            let count = chunk.withUnsafeBufferPointer { write(output[1], $0.baseAddress, $0.count) }
            guard count > 0 else { break }
            filled += count
        }
        var byte = Self.filler
        while write(output[1], &byte, 1) == 1 { filled += 1 }
        return filled
    }

    static let filler = UInt8(ascii: "x")

    /// Everything on the output, read until it ends with `suffix` or
    /// `seconds` pass with nothing more.
    func readOutput(endingWith suffix: [UInt8], within seconds: Double) -> [UInt8] {
        var bytes: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !bytes.reversed().starts(with: suffix.reversed()) {
            var target = pollfd(fd: output[0], events: Int16(POLLIN), revents: 0)
            guard poll(&target, 1, Int32(seconds * 1000)) > 0 else { break }
            let count = read(output[0], &chunk, chunk.count)
            guard count > 0 else { break }
            bytes += chunk.prefix(count)
        }
        return bytes
    }

    /// What the watchdog wrote within `seconds`.
    func written(within seconds: Double) -> String {
        var target = pollfd(fd: output[0], events: Int16(POLLIN), revents: 0)
        guard poll(&target, 1, Int32(seconds * 1000)) > 0 else { return "" }
        var bytes = [UInt8](repeating: 0, count: 64)
        let count = read(output[0], &bytes, bytes.count)
        return String(bytes: bytes.prefix(max(0, count)), encoding: .utf8) ?? ""
    }

    func finish() {
        watchdog.stop()
        for descriptor in input + output where descriptor >= 0 { close(descriptor) }
    }
}

/// A TCP socket listening on the loopback interface, for a descriptor
/// `poll` calls readable while `FIONREAD` finds nothing in it: one with a
/// connection pending.
private struct LoopbackListener {
    let descriptor: Int32
    private let port: in_port_t

    enum Failure: Error { case failed(String) }

    #if canImport(Darwin)
        private static let stream = SOCK_STREAM
    #else
        private static let stream = Int32(SOCK_STREAM.rawValue)
    #endif

    init() throws {
        let listener = socket(AF_INET, Self.stream, 0)
        guard listener >= 0 else { throw Failure.failed("socket") }
        var address = Self.loopback(port: 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let listening = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, length) == 0 && listen(listener, 4) == 0
                    && getsockname(listener, $0, &length) == 0
            }
        }
        guard listening else {
            Foundation.close(listener)
            throw Failure.failed("bind/listen")
        }
        descriptor = listener
        port = address.sin_port
    }

    /// A connection to it, left pending: the listener is readable until it
    /// is accepted.
    func connect() throws -> Int32 {
        let client = socket(AF_INET, Self.stream, 0)
        var address = Self.loopback(port: port)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Foundation.connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard client >= 0, connected else {
            if client >= 0 { Foundation.close(client) }
            throw Failure.failed("connect")
        }
        return client
    }

    func close() { Foundation.close(descriptor) }

    private static func loopback(port: in_port_t) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        #if canImport(Darwin)
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        return address
    }
}

@Suite("The stall watchdog")
struct StallWatchdogTests {

    /// The hung app: input waits and nothing drains it.
    @Test("Input left unread past the grace pops the flags, once, and the loop hears of it at its next drain")
    func unreadInputPops() {
        let rig = Rig()
        defer { rig.finish() }
        rig.gate.setArmed(true)
        rig.type()
        #expect(rig.written(within: 10) == "\u{1B}[<u")
        #expect(!rig.gate.isArmed, "once: disarmed until the loop pushes again")
        #expect(rig.drain(), "the loop's next drain hears of the pop")
        #expect(!rig.gate.noteDrain(), "and only once")
    }

    /// And it is still watching afterwards: a watchdog that had ended would
    /// pop nothing too.
    @Test("Input the loop reads pops nothing, and the watch goes on")
    func readInputPopsNothing() {
        let rig = Rig()
        defer { rig.finish() }
        rig.gate.setArmed(true)
        for _ in 0..<3 {
            rig.type()
            #expect(!rig.drain())
        }
        #expect(rig.written(within: 1.2).isEmpty)
        #expect(rig.gate.isArmed && !rig.gate.isStopped)
        rig.type()
        #expect(rig.written(within: 10) == "\u{1B}[<u", "still watching: a key left unread pops")
    }

    /// What a read racing the watchdog's look makes of a keystroke: input
    /// `poll` calls readable, whose count a moment later is 0 — the loop read
    /// it in between. Stood in for, without the race, by a listening socket
    /// with a connection pending: readable to `poll`, nothing to `FIONREAD`
    /// (0 on Darwin, an error on Linux), and not at its end. That is no
    /// hang-up: the watch goes on, popping nothing for it (round 6: taken
    /// for an end of file, it ended the watch for good, silently).
    @Test("Input readable to poll with nothing to count — a racing read — leaves it watching")
    func racingReadIsNoHangUp() throws {
        let listener = try LoopbackListener()
        defer { listener.close() }
        var output: [Int32] = [-1, -1]
        _ = pipe(&output)
        defer { for descriptor in output { close(descriptor) } }
        let gate = TerminalWriteGate()
        let watchdog = StallWatchdog(gate: gate, input: listener.descriptor, output: output[1], grace: 0.1)
        watchdog.start()
        defer { watchdog.stop() }
        gate.setArmed(true)
        let client = try listener.connect()
        defer { Foundation.close(client) }
        // Long enough for many looks: it checks four times a second.
        Thread.sleep(forTimeInterval: 0.8)
        #expect(!gate.isStopped, "no hang-up")
        #expect(gate.isArmed, "nothing popped: there was nothing to read")
        var target = pollfd(fd: output[0], events: Int16(POLLIN), revents: 0)
        #expect(poll(&target, 1, 0) == 0)
    }

    /// Disarmed while the flags are not pushed, during a suspend, and while
    /// the quit key is masked — where a pop could not make ⌃\ quit.
    @Test("Disarmed, it pops nothing; armed again, it pops for the input still waiting")
    func disarmedPopsNothing() {
        let rig = Rig()
        defer { rig.finish() }
        rig.type()
        #expect(rig.written(within: 1.2).isEmpty)
        rig.gate.setArmed(true)
        #expect(rig.written(within: 10) == "\u{1B}[<u")
    }

    /// A terminal gone: its input reports a hang-up, or reads as at its end —
    /// readable for ever, with nothing to read, as a pipe with no writer
    /// left does. Taken for input, that would pop, be pushed back, and pop
    /// again every grace for as long as the app went on running.
    @Test("A terminal that hangs up ends the watch; nothing is popped")
    func hangUpEndsIt() {
        let rig = Rig()
        defer { rig.finish() }
        rig.gate.setArmed(true)
        rig.hangUp()
        #expect(rig.written(within: 1.2).isEmpty)
        #expect(rig.gate.isStopped, "the watch ended")
    }

    /// Standard output left non-blocking by another program (a crashed Node
    /// CLI is the known case, `Terminal.writeAll`) and full: the pop cannot
    /// go. None of it is written — the head of a sequence would run into the
    /// next frame — and it is no pop: the loop, told of one, would push the
    /// flags back over an entry still there. Armed still, it goes whole once
    /// the terminal has room (round 6: it counted a pop it gave up on).
    @Test("A pop the terminal has no room for is not written or counted, and goes whole once there is room")
    func fullOutputPopsNothingUntilThereIsRoom() {
        let rig = Rig(grace: 0.1)
        defer { rig.finish() }
        let filled = rig.fillOutput()
        rig.gate.setArmed(true)
        rig.type()
        // Several graces, each a pop tried and given up.
        Thread.sleep(forTimeInterval: 0.6)
        #expect(rig.gate.isArmed, "nothing popped: still armed")
        #expect(!rig.gate.noteDrain(), "and nothing for the loop to push back")

        let pop = Array("\u{1B}[<u".utf8)
        let bytes = rig.readOutput(endingWith: pop, within: 10)
        #expect(bytes.count == filled + pop.count, "the filler, then one whole pop")
        #expect(bytes.prefix(filled).allSatisfy { $0 == Rig.filler } && bytes.suffix(pop.count).elementsEqual(pop))
        #expect(rig.drain(), "a pop the loop hears of")
    }

    /// The watchdog popped while the loop was stalled, and the loop's next
    /// act is a suspend, which pops the flags itself. The watchdog's pop
    /// took this process's entry off the terminal's stack already: a second
    /// would take one this process never pushed. The suspend's disarm and
    /// its taking back of the watchdog's pop are one step under the
    /// watchdog's lock, so no pop of the watchdog's can fall between them
    /// and be pushed back after the resume as well as the resume's own push
    /// (round 6: they were two, and the suspend wrote its pop regardless).
    @MainActor
    @Test("A suspend after the watchdog's pop writes no second pop, and the resume pushes once")
    func suspendAfterAWatchdogPop() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.scriptedLineDiscipline = LineDiscipline(
            get: { TerminalLineDisciplineTests.cooked() }, set: { _, _ in })
        terminal.enableRawMode()
        terminal.negotiateKeyboardEnhancement(firstAnswer: .requested, timeout: 0.01)
        #expect(terminal.writeGate.isArmed)

        // The stall: a watchdog on the terminal's own gate pops while a key
        // waits unread. Stopped once it has, so it pops nothing more.
        var input: [Int32] = [-1, -1]
        var popped: [Int32] = [-1, -1]
        _ = pipe(&input)
        _ = pipe(&popped)
        defer { for descriptor in input + popped { close(descriptor) } }
        let watchdog = StallWatchdog(gate: terminal.writeGate, input: input[0], output: popped[1], grace: 0.1)
        watchdog.start()
        var byte = UInt8(ascii: "k")
        _ = write(input[1], &byte, 1)
        var target = pollfd(fd: popped[0], events: Int16(POLLIN), revents: 0)
        #expect(poll(&target, 1, 10_000) == 1, "the watchdog popped")
        watchdog.stop()

        output.clear()
        terminal.disableRawMode()
        #expect(!output.bytes.contains(KeyboardProtocolQuery.pop), "the watchdog's pop stands for the suspend's")
        output.clear()
        terminal.enableRawMode()
        #expect(output.bytes.contains(KeyboardProtocolQuery.push(.requested)), "the resume pushes")
        #expect(!terminal.writeGate.noteDrain(), "and nothing is left to push back on the watchdog's account")
        terminal.disableRawMode()
    }

    /// It is armed only while popping can help: raw mode on, the flags
    /// pushed, the user's quit key live and not masked for a binding.
    @MainActor
    @Test("The terminal arms it while the flags are pushed and the quit key is live, and pushes them back after a stall")
    func armedWhileItCanHelp() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.scriptedLineDiscipline = LineDiscipline(
            get: { TerminalLineDisciplineTests.cooked() }, set: { _, _ in })
        terminal.enableRawMode()
        #expect(!terminal.writeGate.isArmed, "nothing pushed")
        terminal.negotiateKeyboardEnhancement(firstAnswer: .requested, timeout: 0.01)
        #expect(terminal.keyboardFlagsPushed && terminal.writeGate.isArmed)
        terminal.maskQuitKey(for: .ownChord)
        #expect(!terminal.writeGate.isArmed, "masked: the byte would not quit")
        terminal.maskQuitKey(for: .aliasOnly)
        #expect(!terminal.quitKeyMasked && !terminal.writeGate.isArmed, "live, but not after a pop")
        terminal.maskQuitKey(for: .unbound)
        #expect(terminal.writeGate.isArmed)

        output.clear()
        terminal.recoverFromStall()
        #expect(output.bytes == KeyboardProtocolQuery.push(.requested), "the flags pushed back")
        #expect(terminal.writeGate.isArmed)

        terminal.disableRawMode()
        #expect(!terminal.writeGate.isArmed, "torn down: popped by the terminal itself")
        output.clear()
        terminal.recoverFromStall()
        #expect(output.bytes.isEmpty, "nothing to push back once popped for good")
    }
}

#endif
