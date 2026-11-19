//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowsConsoleTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// The Windows console layer: what stands in for termios, stdin's reads and
// SIGWINCH there (`WindowsConsole.swift`, `SignalManager+Windows.swift`).
#if os(Windows)

import Foundation
import Synchronization
import Testing
import WinSDK

@testable import TUIApp

@Suite("Windows console")
struct WindowsConsoleTests {

    // MARK: - Raw mode

    /// The shell's modes as a fresh console has them: line input, echo and
    /// processing on, Quick Edit on, and no escape sequences either way.
    private static let shells = ConsoleModes(
        input: DWORD(
            ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_INSERT_MODE
                | ENABLE_QUICK_EDIT_MODE | ENABLE_EXTENDED_FLAGS),
        output: DWORD(ENABLE_PROCESSED_OUTPUT | ENABLE_WRAP_AT_EOL_OUTPUT),
        inputCodePage: 437, outputCodePage: 437)

    @Test("Raw mode reads each key unechoed and unprocessed, as escape sequences")
    func rawInput() {
        let raw = ConsoleModes.raw(from: Self.shells)
        for off in [ENABLE_LINE_INPUT, ENABLE_ECHO_INPUT, ENABLE_PROCESSED_INPUT, ENABLE_QUICK_EDIT_MODE] {
            #expect(raw.input & DWORD(off) == 0)
        }
        for on in [ENABLE_VIRTUAL_TERMINAL_INPUT, ENABLE_WINDOW_INPUT, ENABLE_MOUSE_INPUT] {
            #expect(raw.input & DWORD(on) != 0)
        }
        // What raw mode does not concern itself with is left as it was.
        #expect(raw.input & DWORD(ENABLE_INSERT_MODE) != 0)
    }

    @Test("Raw mode interprets escape sequences and leaves a line feed a line feed")
    func rawOutput() {
        let raw = ConsoleModes.raw(from: Self.shells)
        for on in [ENABLE_PROCESSED_OUTPUT, ENABLE_VIRTUAL_TERMINAL_PROCESSING, DISABLE_NEWLINE_AUTO_RETURN] {
            #expect(raw.output & DWORD(on) != 0)
        }
        #expect(raw.output & DWORD(ENABLE_WRAP_AT_EOL_OUTPUT) != 0)
    }

    @Test("Raw mode reads and writes UTF-8")
    func rawCodePages() {
        let raw = ConsoleModes.raw(from: Self.shells)
        #expect(raw.inputCodePage == UINT(CP_UTF8))
        #expect(raw.outputCodePage == UINT(CP_UTF8))
    }

    // MARK: - Key records

    private static func key(
        _ unit: UInt16, down: Bool = true, repeats: WORD = 1, virtualKey: WORD = 0, control: Bool = false
    ) -> KEY_EVENT_RECORD {
        var record = KEY_EVENT_RECORD()
        record.bKeyDown = WindowsBool(booleanLiteral: down)
        record.wRepeatCount = repeats
        record.wVirtualKeyCode = virtualKey
        unsafe record.uChar.UnicodeChar = unit
        record.dwControlKeyState = control ? DWORD(LEFT_CTRL_PRESSED) : 0
        return record
    }

    private static func decoded(_ records: [KEY_EVENT_RECORD]) -> [UInt8] {
        var decoder = KeyRecordDecoder()
        var bytes: [UInt8] = []
        for record in records { decoder.decode(record, into: &bytes) }
        return bytes
    }

    @Test("A sequence's records are its bytes: the key-downs, in order")
    func sequence() {
        // An up arrow, as a console in virtual-terminal input mode sends it:
        // each byte a down and an up.
        let records = [0x1B, 0x5B, 0x41].flatMap { [Self.key($0), Self.key($0, down: false)] }
        #expect(Self.decoded(records) == [0x1B, 0x5B, 0x41])
    }

    @Test("A repeated key is its character as many times as the record says")
    func repeats() {
        #expect(Self.decoded([Self.key(0x61, repeats: 3)]) == Array("aaa".utf8))
    }

    @Test("A character outside the Basic Multilingual Plane is its two records, as one character")
    func surrogatePair() {
        let units = Array("🙂".utf16)
        #expect(units.count == 2)
        #expect(Self.decoded(units.map { Self.key($0) }) == Array("🙂".utf8))
    }

    @Test("A key with no character is no byte, but ⌃Space is NUL")
    func noCharacter() {
        #expect(Self.decoded([Self.key(0, virtualKey: WORD(VK_SHIFT))]).isEmpty)
        #expect(Self.decoded([Self.key(0, virtualKey: WORD(VK_SPACE), control: true)]) == [0])
    }

    // MARK: - The reader's hold

    @Test("What the reader received is read once, oldest first, and wakes a wait")
    func hold() {
        let input = ConsoleInput()
        #expect(!input.waitForInput(until: Date()))
        input.receive(Array("ab".utf8))
        input.receive(Array("c".utf8))
        #expect(input.waitForInput(until: Date()))
        var buffer = [UInt8](repeating: 0, count: 2)
        let first = buffer.withUnsafeMutableBufferPointer { unsafe input.read(into: $0) }
        #expect(first == 2)
        #expect(buffer == Array("ab".utf8))
        let second = buffer.withUnsafeMutableBufferPointer { unsafe input.read(into: $0) }
        #expect(second == 1)
        #expect(buffer[0] == UInt8(ascii: "c"))
        let third = buffer.withUnsafeMutableBufferPointer { unsafe input.read(into: $0) }
        #expect(third == 0)
    }

    @Test("A paste past the hold's limit is kept whole, and read back in order")
    func largePaste() {
        let input = ConsoleInput()
        let size = ConsoleInput.holdLimit + 123_457
        let paste = (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 9) }
        // Received in reads of a console's size, as the reader receives them.
        for start in stride(from: 0, to: size, by: 512) {
            input.receive(Array(paste[start..<min(start + 512, size)]))
        }
        #expect(input.isHolding)
        var read: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBufferPointer { unsafe input.read(into: $0) }
            guard count > 0 else { break }
            read += buffer[..<count]
        }
        #expect(read == paste)
        #expect(!input.isHolding)
    }

    @Test("What the reader received is announced to the loop")
    func arrival() {
        let input = ConsoleInput()
        let arrivals = Mutex(0)
        input.setHandlers(.init(arrival: { arrivals.withLock { $0 += 1 } }, resize: {}))
        input.receive(Array("x".utf8))
        input.receive([])
        #expect(arrivals.withLock { $0 } == 1)
    }

    // MARK: - The clipboard's line breaks

    @Test("The clipboard gets Windows's line breaks, and the app the terminal's")
    func clipboardLineBreaks() {
        #expect(SystemClipboard.lineBreaks("a\nb\r\nc", as: "\r\n") == "a\r\nb\r\nc")
        #expect(SystemClipboard.lineBreaks("a\r\nb\nc", as: "\n") == "a\nb\nc")
    }
}

@MainActor
@Suite("SignalManager on Windows")
struct WindowsSignalManagerTests {
    @Test("A resize from the console's reader sets the resize flag once, and wakes the loop")
    func resize() async {
        let signals = SignalManager()
        var wakes = 0
        await signals.install(wake: { wakes += 1 })
        defer { signals.stop() }
        #expect(!signals.consumeResizeFlag())
        signals.noteResize()
        #expect(wakes == 1)
        #expect(signals.consumeResizeFlag())
        #expect(!signals.consumeResizeFlag())
    }

    @Test("Nothing suspends a Windows process from its console")
    func noJobControl() {
        let signals = SignalManager()
        #expect(!signals.consumeSuspendFlag())
        #expect(!signals.consumeContinueFlag())
        #expect(!signals.shouldShutdown)
    }
}

/// The console's ⌃C and Ctrl-Break during a hand-off, which the console raises
/// in the app as well as in the program it handed the console to. Serialized:
/// whether the app is handing off is process-wide, as the handlers are.
@MainActor
@Suite("A hand-off's control events on Windows", .serialized)
struct WindowsHandOffControlEventTests {
    @Test("⌃C during a hand-off is the other program's: taken, and no shutdown")
    func controlCIgnored() async {
        let signals = SignalManager()
        await signals.install(wake: {})
        defer { signals.stop() }
        signals.beginHandOff()
        #expect(SignalManager.handler(DWORD(CTRL_C_EVENT)).boolValue)
        signals.endHandOff()
        await Task.yield()
        #expect(!signals.shouldShutdown)
    }

    @Test("⌃C after the hand-off shuts the app down again")
    func controlCAfter() async {
        let signals = SignalManager()
        await signals.install(wake: {})
        defer { signals.stop() }
        signals.beginHandOff()
        signals.endHandOff()
        #expect(SignalManager.handler(DWORD(CTRL_C_EVENT)).boolValue)
        // The route hops to the main actor to set the flag.
        for _ in 0..<100 where !signals.shouldShutdown { await Task.yield() }
        #expect(signals.shouldShutdown)
    }

    @Test("Ctrl-Break during a hand-off is the other program's: taken, and the app lives")
    func breakIgnored() {
        let signals = SignalManager()
        signals.beginHandOff()
        defer { signals.endHandOff() }
        // Were it not ignored, this would end the test's process.
        #expect(FatalSignalTerminalRestore.controlHandler(DWORD(CTRL_BREAK_EVENT)).boolValue)
    }
}

/// A logoff or a shutdown, told to the hidden window as the system tells it.
/// Serialized: the window and the route it sends through are the process's.
@MainActor
@Suite("A session's end on Windows", .serialized)
struct WindowsSessionEndTests {
    /// The watch's window's bits, once it is made.
    private func window() async throws -> UInt {
        for _ in 0..<500 where SessionEndWatch.window == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        let window = SessionEndWatch.window
        try #require(window != 0, "no window was made")
        return window
    }

    @Test("Asked whether the session may end, the app says yes, and stays up")
    func queryAnswered() async throws {
        let signals = SignalManager()
        await signals.install(wake: {})
        defer { signals.stop() }
        let window = try await window()
        #expect(unsafe SendMessageW(HWND(bitPattern: window), UINT(WM_QUERYENDSESSION), 0, 0) == 1)
        // A session another program kept from ending.
        _ = unsafe SendMessageW(HWND(bitPattern: window), UINT(WM_ENDSESSION), 0, 0)
        for _ in 0..<10 { await Task.yield() }
        #expect(!signals.shouldShutdown)
    }

    @Test("A session that is ending shuts the app down in order")
    func endShutsDown() async throws {
        let signals = SignalManager()
        await signals.install(wake: {})
        defer { signals.stop() }
        let window = try await window()
        // Posted, as the window then waits for a teardown that, here, never
        // ends the process.
        _ = unsafe PostMessageW(HWND(bitPattern: window), UINT(WM_ENDSESSION), 1, 0)
        for _ in 0..<500 where !signals.shouldShutdown { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(signals.shouldShutdown)
    }
}

@Suite("Standard output's writes on Windows")
struct WindowsStandardOutputTests {
    @Test("A failed write sets errno as write(2) would, not leaving a stale EINTR to retry on")
    func failedWriteSetsErrno() {
        let bytes: [UInt8] = Array("x".utf8)
        errno = EINTR
        let written = bytes.withUnsafeBufferPointer {
            unsafe StandardHandle.write(to: INVALID_HANDLE_VALUE, $0.baseAddress!, $0.count)
        }
        #expect(written == -1)
        #expect(errno == EIO)
    }
}

@Suite("A quit and the frame being written, on Windows")
struct WindowsQuitWriteGateTests {
    @Test("With no write under way, a quit waits for nothing")
    func noWrite() {
        #expect(FatalSignalTerminalRestore.awaitWrites(within: .seconds(5)))
    }

    @Test("A quit waits for the write under way, and not for ever for one that does not end")
    func waitsForTheWrite() {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            FatalSignalTerminalRestore.duringWrite {
                started.signal()
                release.wait()
            }
            finished.signal()
        }
        started.wait()
        // Held: the wait gives up.
        #expect(!FatalSignalTerminalRestore.awaitWrites(within: .milliseconds(50)))
        // Let go while it waits: the wait ends with it.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(30)) { release.signal() }
        #expect(FatalSignalTerminalRestore.awaitWrites(within: .seconds(5)))
        finished.wait()
    }
}

#endif
