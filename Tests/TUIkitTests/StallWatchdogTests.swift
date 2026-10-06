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
    private let input: [Int32]
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

    /// The loop reads it, as `drainTerminalEvents` does.
    func drain() -> Bool {
        var byte: UInt8 = 0
        _ = read(input[0], &byte, 1)
        return gate.noteDrain()
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
        for descriptor in input + output { close(descriptor) }
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

    @Test("Input the loop reads pops nothing")
    func readInputPopsNothing() {
        let rig = Rig()
        defer { rig.finish() }
        rig.gate.setArmed(true)
        for _ in 0..<3 {
            rig.type()
            #expect(!rig.drain())
        }
        #expect(rig.written(within: 1.2).isEmpty)
        #expect(rig.gate.isArmed)
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
        terminal.maskQuitKey(true)
        #expect(!terminal.writeGate.isArmed, "masked: the byte would not quit")
        terminal.maskQuitKey(false)
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
