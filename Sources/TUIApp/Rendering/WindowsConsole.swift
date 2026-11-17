//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowsConsole.swift
//
//  The Windows console, standing in for what a POSIX terminal gives the
//  console layer: its modes for `termios`, its input records for a read of
//  stdin, its screen buffer for `TIOCGWINSZ`, and its handles for stdin and
//  stdout. Everything Windows-only the run loop needs is here, so the rest of
//  `TUIApp` reads the same on every platform but for a few named arms.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import TUIFoundation
import WinSDK

// MARK: - The modes raw mode sets

/// The console's settings that raw mode changes and the teardown puts back:
/// the input and output modes of standard input's and standard output's
/// console handles, and the console's two code pages.
///
/// What `termios` is on a POSIX terminal. The console has no line discipline in
/// a kernel driver; it has these flags on its handles, and a program that leaves
/// them changed leaves them changed for the shell that started it, as with
/// `termios`.
struct ConsoleModes: Equatable, Sendable {
    /// Standard input's console mode (`ENABLE_LINE_INPUT`, `ENABLE_ECHO_INPUT`, …).
    var input: DWORD
    /// Standard output's console mode (`ENABLE_VIRTUAL_TERMINAL_PROCESSING`, …).
    var output: DWORD
    /// The code page the console decodes what a program reads with (`GetConsoleCP`).
    var inputCodePage: UINT
    /// The code page the console decodes what a program writes with (`GetConsoleOutputCP`).
    var outputCodePage: UINT

    /// The console's settings now, or `nil` where standard input or standard
    /// output is not a console: a pipe, a file, `NUL`.
    static func current() -> ConsoleModes? {
        var input: DWORD = 0
        var output: DWORD = 0
        guard unsafe GetConsoleMode(StandardHandle.input, &input), unsafe GetConsoleMode(StandardHandle.output, &output)
        else { return nil }
        return ConsoleModes(
            input: input, output: output, inputCodePage: GetConsoleCP(), outputCodePage: GetConsoleOutputCP())
    }

    /// Sets these on the console. Each handle and code page is set alone, so one
    /// the console refuses leaves the others set.
    ///
    /// `ENABLE_EXTENDED_FLAGS` goes with every input mode: without it the
    /// console ignores the Quick Edit bit, so neither turning it off nor putting
    /// the user's back would take.
    func apply() {
        _ = unsafe SetConsoleMode(StandardHandle.input, input | DWORD(ENABLE_EXTENDED_FLAGS))
        if unsafe !SetConsoleMode(StandardHandle.output, output) {
            // A console older than Windows 10's 2016 updates has no
            // `DISABLE_NEWLINE_AUTO_RETURN`, and refuses the whole mode for it.
            // Every frame positions its own cursor, so it is done without.
            _ = unsafe SetConsoleMode(StandardHandle.output, output & ~DWORD(DISABLE_NEWLINE_AUTO_RETURN))
        }
        _ = SetConsoleCP(inputCodePage)
        _ = SetConsoleOutputCP(outputCodePage)
    }

    /// The modes raw mode runs in, made from the user's own, `original`, which
    /// the teardown puts back exactly.
    ///
    /// - Input: no line editing, no echo, and no processing (`ENABLE_LINE_INPUT`,
    ///   `ENABLE_ECHO_INPUT`, `ENABLE_PROCESSED_INPUT` off): each key is read as
    ///   it comes, unechoed, and ⌃C arrives as the key 0x03 rather than as a
    ///   `CTRL_C_EVENT` — as `ISIG`'s `VINTR` turned off does on POSIX. Quick
    ///   Edit off (`ENABLE_QUICK_EDIT_MODE`), or the classic console (conhost)
    ///   takes a drag for its own selection instead of reporting it. And keys,
    ///   mouse reports, pastes and the terminal's replies as the bytes a POSIX
    ///   terminal sends (`ENABLE_VIRTUAL_TERMINAL_INPUT`), which the parser
    ///   already reads; a resize as a record of its own (`ENABLE_WINDOW_INPUT`,
    ///   see ``ConsoleInput``); and the mouse (`ENABLE_MOUSE_INPUT`), which
    ///   conhost wants before it sends a VT mouse report.
    /// - Output: escape sequences interpreted rather than printed
    ///   (`ENABLE_VIRTUAL_TERMINAL_PROCESSING`, with `ENABLE_PROCESSED_OUTPUT`,
    ///   which it needs), and a line feed that only moves down a row
    ///   (`DISABLE_NEWLINE_AUTO_RETURN`), as `OPOST` off leaves it on POSIX.
    /// - Both code pages UTF-8, so the bytes a frame writes and the bytes a key
    ///   reads are UTF-8, as on every other platform.
    ///
    /// Ctrl-Break is not a key in any of these: the console always raises
    /// `CTRL_BREAK_EVENT` for it, which is what quits a hung app
    /// (`FatalSignalTerminalRestore`), as the driver's ⌃\ does on POSIX.
    static func raw(from original: ConsoleModes) -> ConsoleModes {
        var raw = original
        raw.input &= ~DWORD(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT | ENABLE_QUICK_EDIT_MODE)
        raw.input |= DWORD(ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT)
        raw.output |= DWORD(
            ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN)
        raw.inputCodePage = UINT(CP_UTF8)
        raw.outputCodePage = UINT(CP_UTF8)
        return raw
    }
}

// MARK: - The handles

/// Standard input's and standard output's handles, asked of the process each
/// time rather than kept, as `STDIN_FILENO` names whatever is descriptor 0 now:
/// ``NoTerminal`` may point them at the console after start-up
/// (`SetStdHandle`).
enum StandardHandle {
    /// Standard input's handle.
    static var input: HANDLE? { unsafe GetStdHandle(STD_INPUT_HANDLE) }

    /// Standard output's handle.
    static var output: HANDLE? { unsafe GetStdHandle(STD_OUTPUT_HANDLE) }

    /// Writes `count` bytes at `base` to standard output, and returns how many
    /// were written, or -1. `WriteFile` rather than the C library's `write`,
    /// which opens descriptor 1 in text mode and would turn every line feed a
    /// frame writes into a carriage return and a line feed.
    static func write(_ base: UnsafePointer<UInt8>, _ count: Int) -> Int {
        var written: DWORD = 0
        guard unsafe WriteFile(output, base, DWORD(clamping: count), &written, nil) else { return -1 }
        return Int(written)
    }

    /// The cells the console's window shows, or `nil` where standard output is
    /// no console. The window, not the screen buffer: conhost's buffer is
    /// usually far taller than its window, and what is drawn is the window.
    static func windowSize() -> (width: Int, height: Int)? {
        var info = CONSOLE_SCREEN_BUFFER_INFO()
        guard unsafe GetConsoleScreenBufferInfo(output, &info) else { return nil }
        let width = Int(info.srWindow.Right) - Int(info.srWindow.Left) + 1
        let height = Int(info.srWindow.Bottom) - Int(info.srWindow.Top) + 1
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }
}

// MARK: - The C library's POSIX names

/// Whether `descriptor` is a console: what the console layer asks `isatty`
/// on every platform, before a start-up exchange with the terminal.
///
/// Declared here under the POSIX name, so the call sites read the same on every
/// platform, and in this module, so it is the one they find: the C library's
/// own (`ucrt`) is deprecated under that name, and says yes to `NUL` as well
/// as to a console, being a test for a character device. What the console
/// layer needs to know is whether there is a console to talk to.
func isatty(_ descriptor: Int32) -> Int32 {
    let raw = _get_osfhandle(descriptor)
    guard raw != -1, raw != -2, let handle = unsafe HANDLE(bitPattern: raw) else { return 0 }
    var mode: DWORD = 0
    return unsafe GetConsoleMode(handle, &mode) ? 1 : 0
}

/// The process's environment variable `name`, or `nil` where it is unset:
/// what `getenv` answers on POSIX, read from the process's environment
/// (`GetEnvironmentVariableW`), which is where `ProcessInfo` and `_putenv_s`
/// read and write it. The C library's `getenv` is deprecated.
func environmentValue(_ name: String) -> String? {
    name.withCString(encodedAs: UTF16.self) { key in
        let length = unsafe GetEnvironmentVariableW(key, nil, 0)
        guard length > 0 else { return nil }
        var value = [UInt16](repeating: 0, count: Int(length))
        let written = unsafe GetEnvironmentVariableW(key, &value, length)
        guard written > 0, written < length else { return nil }
        return String(decoding: value[..<Int(written)], as: UTF16.self)
    }
}

// MARK: - Reading the console

/// Standard input on Windows: a thread of its own blocked on the console's
/// input records, turning them into the bytes a POSIX terminal would send, and
/// holding them for the run loop, which reads them without blocking
/// (`Terminal.readSource`).
///
/// A thread because nothing else will wait on a console. libdispatch refuses a
/// console handle for a read source (it is no pipe, file or socket), and `poll`
/// does not exist. The console's handle can be waited on, and is ready while it
/// holds records — of every kind, focus and menu events included — so the
/// thread waits on it and reads what is there.
///
/// Records, not bytes, because a resize is one: `WINDOW_BUFFER_SIZE_EVENT`,
/// sent while `ENABLE_WINDOW_INPUT` is on, the console's SIGWINCH. `ReadFile`
/// would read the keys and drop it. Under `ENABLE_VIRTUAL_TERMINAL_INPUT` a key
/// record carries one UTF-16 code unit of what a POSIX terminal sends for the
/// key — an arrow is the three records `ESC`, `[`, `A`, and a mouse report or a
/// terminal's reply the same — so the bytes are each key-down record's
/// character, as UTF-8.
///
/// Reads only while the run loop has the console (``resume()``, from raw mode
/// on, to ``pause()``, from raw mode off): records read while another program
/// has it — a hand-off — would be keys taken from that program.
final class ConsoleInput: @unchecked Sendable {
    // @unchecked: every stored property but the two handles, which are set once
    // in `init` and only read after, is read and written under `condition`.

    /// What the reader tells the run loop, from its own thread: that bytes are
    /// waiting, and that the window changed size.
    struct Handlers: Sendable {
        var arrival: @Sendable () -> Void
        var resize: @Sendable () -> Void
    }

    /// The lock over everything below, and what a wait for input
    /// (``waitForInput(until:)``) sleeps on.
    private let condition = NSCondition()

    /// What the reader has read and the loop has not, oldest first.
    private var queued: [UInt8] = []

    /// Whether the reader may read: raw mode is on.
    private var reading = false

    /// Whether the reader's thread has been started.
    private var started = false

    /// What the reader calls with what it read.
    private var handlers: Handlers?

    /// Set when ``reading`` changes, so a reader waiting on the console wakes
    /// and looks at it.
    private var changed: HANDLE? { unsafe HANDLE(bitPattern: changedEvent) }

    /// ``changed``'s handle, kept as its bits: a `HANDLE` is a raw pointer, and
    /// storing one would make this class's storage unsafe, and every owner's.
    /// This class alone creates the event and closes it. 0 if none was made.
    private let changedEvent: UInt

    /// The most held for the loop: far more than any burst of keys or a
    /// terminal's replies, and a paste past it waits in the console's own queue.
    private static let holdLimit = 1 << 20

    init() {
        changedEvent = unsafe UInt(bitPattern: CreateEventW(nil, false, false, nil))
    }

    deinit {
        if let changed = unsafe changed { unsafe CloseHandle(changed) }
    }

    /// Sets what the reader calls when it has read something: the run loop's
    /// wake, and its resize. Until then what is read is held, unannounced, for
    /// the start-up exchanges, which ask ``waitForInput(until:)`` instead.
    func setHandlers(_ handlers: Handlers?) {
        condition.withLock { self.handlers = handlers }
    }

    /// Starts reading, on a thread started the first time.
    func resume() {
        let start = condition.withLock {
            reading = true
            defer { started = true }
            return !started
        }
        if start {
            let thread = Thread { [self] in readRecords() }
            thread.name = "TUI console input"
            thread.start()
        } else if let changed = unsafe changed {
            unsafe SetEvent(changed)
        }
    }

    /// Stops reading until ``resume()``. What is held stays held.
    func pause() {
        condition.withLock { reading = false }
        if let changed = unsafe changed { unsafe SetEvent(changed) }
    }

    /// Moves what is held into `buffer`, as much as fits, and returns how many
    /// bytes it moved: 0 when nothing is held. Never blocks.
    func read(into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
        guard let base = buffer.baseAddress else { return 0 }
        return condition.withLock {
            let count = min(queued.count, buffer.count)
            guard count > 0 else { return 0 }
            queued.withUnsafeBufferPointer { unsafe base.update(from: $0.baseAddress!, count: count) }
            queued.removeFirst(count)
            return count
        }
    }

    /// Whether bytes are held, or arrive before `deadline`.
    func waitForInput(until deadline: Date) -> Bool {
        condition.withLock {
            while queued.isEmpty {
                guard condition.wait(until: deadline) else { return !queued.isEmpty }
            }
            return true
        }
    }

    /// The reader's thread: waits for records while reading, and for
    /// ``resume()`` while not, for the life of the process.
    private func readRecords() {
        guard let console = unsafe StandardHandle.input else { return }
        var decoder = KeyRecordDecoder()
        var records = [INPUT_RECORD](repeating: INPUT_RECORD(), count: 128)
        while true {
            let (reading, resize) = condition.withLock { (self.reading, self.handlers?.resize) }
            guard reading else {
                if let changed = unsafe changed { unsafe WaitForSingleObject(changed, INFINITE) }
                continue
            }
            var handles: [HANDLE?] = unsafe [console, changed]
            let woken = handles.withUnsafeMutableBufferPointer {
                unsafe WaitForMultipleObjects(changed == nil ? 1 : 2, $0.baseAddress, false, INFINITE)
            }
            // The control event: look at `reading` again.
            guard woken == WAIT_OBJECT_0 else {
                if woken == WAIT_FAILED { Sleep(10) }
                continue
            }
            var pending: DWORD = 0
            guard unsafe GetNumberOfConsoleInputEvents(console, &pending), pending > 0 else { continue }
            var count: DWORD = 0
            let read = records.withUnsafeMutableBufferPointer {
                unsafe ReadConsoleInputW(console, $0.baseAddress, DWORD(min(Int(pending), $0.count)), &count)
            }
            guard read else { continue }
            var bytes: [UInt8] = []
            var resized = false
            for record in records[..<Int(count)] {
                switch Int32(record.EventType) {
                case KEY_EVENT:
                    unsafe decoder.decode(record.Event.KeyEvent, into: &bytes)
                case WINDOW_BUFFER_SIZE_EVENT:
                    resized = true
                default:
                    // Focus and menu records, and the console's own mouse
                    // records: a mouse report the app asked for comes as bytes,
                    // under `ENABLE_VIRTUAL_TERMINAL_INPUT`.
                    break
                }
            }
            receive(bytes)
            if resized { resize?() }
        }
    }

    /// Holds `bytes` for the loop, up to ``holdLimit``, and tells it they are
    /// there. What the reader does with what it read: internal, so a test can
    /// stand in for a console.
    func receive(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        let handlers = condition.withLock {
            queued.append(contentsOf: bytes.prefix(max(0, Self.holdLimit - queued.count)))
            condition.broadcast()
            return self.handlers
        }
        handlers?.arrival()
    }
}

/// Turns key records into the bytes a POSIX terminal sends: each key-down
/// record's UTF-16 code unit, repeated as the record says, as UTF-8, a
/// surrogate pair across two records made one character.
///
/// A key-up record is dropped: under `ENABLE_VIRTUAL_TERMINAL_INPUT` the
/// console sends each byte of a sequence as a down and an up, and the down is
/// the byte. So is a record with no character (a modifier pressed alone, a
/// dead key), with one exception: ⌃Space and ⌃@, whose character is NUL, which
/// is what a POSIX terminal sends for them.
struct KeyRecordDecoder {
    /// The first half of a surrogate pair, waiting for its second.
    private var highSurrogate: UInt16?

    mutating func decode(_ key: KEY_EVENT_RECORD, into bytes: inout [UInt8]) {
        guard key.bKeyDown.boolValue else { return }
        let unit = unsafe key.uChar.UnicodeChar
        let control = key.dwControlKeyState & DWORD(LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED) != 0
        let isNull = unit == 0 && control && (key.wVirtualKeyCode == WORD(VK_SPACE) || key.wVirtualKeyCode == 0x32)
        guard unit != 0 || isNull else { return }
        for _ in 0..<max(1, Int(key.wRepeatCount)) {
            append(unit, to: &bytes)
        }
    }

    private mutating func append(_ unit: UInt16, to bytes: inout [UInt8]) {
        if UTF16.isLeadSurrogate(unit) {
            highSurrogate = unit
            return
        }
        let scalar: Unicode.Scalar?
        if UTF16.isTrailSurrogate(unit) {
            guard let high = highSurrogate else { return }
            scalar = Unicode.Scalar(0x10000 + ((UInt32(high) - 0xD800) << 10) + (UInt32(unit) - 0xDC00))
        } else {
            scalar = Unicode.Scalar(unit)
        }
        highSurrogate = nil
        guard let scalar else { return }
        bytes.append(contentsOf: UTF8.encode(scalar)!)
    }
}

#endif
