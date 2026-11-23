//  🖥️ TUI — A Terminal UI framework for Swift
//  NoTerminal.swift
//
//  What an app launched without a terminal to draw on is told: what is missing,
//  and what it can do instead.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation
import TUITerminalHost

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
#elseif os(Windows)
    import WinSDK
#endif

/// Why an app can't draw: what its standard input and output are connected to,
/// when at least one of them is no use to a full-screen interface.
///
/// ``App/main()`` asks ``App/runWithoutTerminal(_:)`` what to do, instead of
/// entering the alternate screen, when stdout or stdin isn't a terminal, as in
/// `myapp > report.txt`, `myapp | grep x`, `myapp < /dev/null` or a CI step, or when
/// `TERM` is `dumb`. By default that prints one line to stderr and exits with
/// status 1, with no escape codes anywhere. An app that has something useful to
/// do in that situation implements it:
///
/// ```swift
/// @main
/// struct Inventory: App {
///     var body: some Scene { WindowGroup { InventoryView() } }
///
///     static func runWithoutTerminal(_ situation: NoTerminal) async -> NoTerminal.Outcome {
///         guard !situation.lacksOutput else {
///             // `inventory > stock.txt`: the same data, as a report.
///             renderOnce { StockReport() }
///             return 0
///         }
///         return situation.reportFailure()
///     }
/// }
/// ```
///
/// TUI-specific: SwiftUI's apps always have a screen. The nearest thing there is
/// a Mac app choosing not to show a window.
public struct NoTerminal {
    /// What a standard stream is connected to.
    public enum Connection: Sendable, Equatable {
        /// A terminal that can draw.
        case terminal
        /// A terminal, but one whose `TERM` is `dumb`: it has no way to place
        /// the cursor, so a full-screen interface would come out as junk. Only
        /// ever of ``NoTerminal/output``: such a terminal's keys read as well as
        /// any.
        case dumbTerminal
        /// A pipe: `myapp | less`, or `cat data | myapp`.
        case pipe
        /// A regular file: `myapp > report.txt`, or `myapp < data.txt`.
        case file
        /// A socket, as a process supervisor may connect.
        case socket
        /// Some other device, `/dev/null` being the usual one.
        case device
        /// Nothing: the stream was closed before the program started.
        case closed
    }

    /// What standard input is connected to.
    public let input: Connection

    /// What standard output is connected to.
    public let output: Connection

    /// Standard input, kept apart from the terminal, where it is a pipe, a file
    /// or a socket: what a tool like `fzf` reads its data from. It stays open
    /// after ``Outcome/drawOnControllingTerminal``, which points descriptor 0
    /// at the terminal, so read this rather than `stdin` or `readLine()`.
    public let pipedInput: FileHandle?

    /// Standard output, kept apart from the terminal, where it is a pipe, a file
    /// or a socket: where a tool like `fzf` writes its answer. It stays open after
    /// ``Outcome/drawOnControllingTerminal``, which points descriptor 1 at the
    /// terminal, so write to this rather than with `print`.
    public let pipedOutput: FileHandle?

    /// Whether standard input is no use for reading keys.
    public var lacksInput: Bool { input != .terminal }

    /// Whether standard output is no use for drawing.
    public var lacksOutput: Bool { output != .terminal }

    /// Whether the process has a controlling terminal it could draw on anyway,
    /// which ``Outcome/drawOnControllingTerminal`` asks for: there is one,
    /// though stdin or stdout goes elsewhere, and it isn't a dumb one. No, in a
    /// CI step or under a process supervisor.
    public var canDrawOnControllingTerminal: Bool {
        guard environment["TERM"] != "dumb" else { return false }
        #if canImport(WASILibc)
            return false
        #elseif os(Windows)
            // The process's console, as `/dev/tty` is its controlling terminal.
            guard let console = unsafe Self.openConsole("CONOUT$") else { return false }
            unsafe CloseHandle(console)
            return true
        #else
            let terminal = unsafe open("/dev/tty", O_RDWR | O_NOCTTY)
            guard terminal >= 0 else { return false }
            close(terminal)
            return true
        #endif
    }

    /// What ``App/runWithoutTerminal(_:)`` says to do next.
    ///
    /// An integer literal is an exit status, so `return 0` reads as it does in
    /// any program.
    public enum Outcome: Sendable, Equatable, ExpressibleByIntegerLiteral {
        /// End the process with this exit status.
        case exit(Int32)

        /// Run the app after all, drawing on and reading keys from the
        /// process's controlling terminal (`/dev/tty`): what `fzf` and `less`
        /// do so they can sit in a pipeline. Whichever of stdin and stdout
        /// isn't a terminal is pointed there, and its pipe or file stays
        /// reachable through ``NoTerminal/pipedInput`` and
        /// ``NoTerminal/pipedOutput``.
        ///
        /// With no controlling terminal, it reports the failure and exits with
        /// status 1. Ask ``NoTerminal/canDrawOnControllingTerminal`` first to
        /// do something else then.
        case drawOnControllingTerminal

        public init(integerLiteral value: Int32) {
            self = .exit(value)
        }
    }

    /// The environment this was read from, for what it goes on to ask.
    private let environment: [String: String]

    /// The one line ``reportFailure()`` prints, in the app's language: what
    /// is missing, in words, without the program's name. For an app that
    /// reports it somewhere else.
    public var message: String {
        let service = LocalizationService.shared
        if output == .dumbTerminal {
            return service.string(for: LocalizationKey.NoTerminal.dumbTerminal.rawValue)
        }
        let key: LocalizationKey.NoTerminal =
            lacksInput
            ? (lacksOutput ? .neither : .noInput)
            : .noOutput
        return service.string(for: key.rawValue)
    }

    /// Prints ``message`` to stderr as one line, starting with the program's name,
    /// and gives the outcome that fails: status 1. What an app that doesn't
    /// implement ``App/runWithoutTerminal(_:)`` gets, and the way out for
    /// situations an app that does has no answer to.
    public func reportFailure() -> Outcome {
        let line = "\(programName): \(message)\n"
        StandardError.write(line)
        return 1
    }
}

// MARK: - Finding out

#if os(Windows)
extension NoTerminal {
    /// The situation of a process whose stdin is `inputDescriptor` and whose
    /// stdout is `outputDescriptor`, or `nil` where it can draw and read keys as
    /// usual: the POSIX arm's, asked of the C library's descriptors' handles.
    static func current(
        input inputDescriptor: Int32 = 0, output outputDescriptor: Int32 = 1,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self? {
        let input = connection(of: inputDescriptor, environment: environment)
        let output = connection(of: outputDescriptor, environment: environment)
        guard input != .terminal || output != .terminal else { return nil }
        return Self(
            input: input == .dumbTerminal ? .terminal : input, output: output,
            pipedInput: kept(inputDescriptor, input), pipedOutput: kept(outputDescriptor, output),
            environment: environment)
    }

    /// What `descriptor` is connected to: a console is the terminal; otherwise
    /// what its handle's file type says. A socket's handle says it is a pipe.
    private static func connection(of descriptor: Int32, environment: [String: String]) -> Connection {
        let raw = _get_osfhandle(descriptor)
        guard raw != -1, raw != -2, let handle = unsafe HANDLE(bitPattern: raw) else { return .closed }
        var mode: DWORD = 0
        if unsafe GetConsoleMode(handle, &mode) { return environment["TERM"] == "dumb" ? .dumbTerminal : .terminal }
        switch unsafe Int32(GetFileType(handle)) {
        case FILE_TYPE_PIPE: return .pipe
        case FILE_TYPE_DISK: return .file
        case FILE_TYPE_CHAR: return .device
        default: return .closed
        }
    }

    /// `descriptor` under a number of its own, where it carries data, as
    /// ``pipedInput`` and ``pipedOutput`` keep it.
    private static func kept(_ descriptor: Int32, _ connection: Connection) -> FileHandle? {
        guard connection == .pipe || connection == .file || connection == .socket else { return nil }
        let copy = _dup(descriptor)
        return copy >= 0 ? FileHandle(fileDescriptor: copy, closeOnDealloc: true) : nil
    }

    /// Opens one of the process's console's own devices, `CONIN$` or `CONOUT$`,
    /// or `nil` where the process has no console.
    fileprivate static func openConsole(_ name: String) -> HANDLE? {
        let handle = name.withCString(encodedAs: UTF16.self) {
            unsafe CreateFileW(
                $0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil,
                DWORD(OPEN_EXISTING), 0, nil)
        }
        guard let handle = unsafe handle, unsafe handle != INVALID_HANDLE_VALUE else { return nil }
        return unsafe handle
    }

    /// Points whichever of stdin and stdout isn't a terminal at the process's
    /// console, as ``Outcome/drawOnControllingTerminal`` asks: its standard
    /// handle, which the console layer reads and writes, and the C library's
    /// descriptor with it.
    ///
    /// - Returns: Whether it could: not with no console, or where `TERM` is
    ///   `dumb`.
    func pointStandardStreamsAtControllingTerminal() -> Bool {
        guard environment["TERM"] != "dumb" else { return false }
        if lacksInput, !Self.point(STD_INPUT_HANDLE, descriptor: 0, at: "CONIN$") { return false }
        if lacksOutput, !Self.point(STD_OUTPUT_HANDLE, descriptor: 1, at: "CONOUT$") { return false }
        return true
    }

    /// Points the standard handle `standard`, and the C library's `descriptor`,
    /// at the console device `name`.
    private static func point(_ standard: DWORD, descriptor: Int32, at name: String) -> Bool {
        guard let console = unsafe openConsole(name) else { return false }
        guard unsafe SetStdHandle(standard, console) else {
            unsafe CloseHandle(console)
            return false
        }
        let opened = _open_osfhandle(Int(bitPattern: console), 0)
        if opened >= 0, opened != descriptor { _ = _dup2(opened, descriptor) }
        return true
    }
}

#elseif !canImport(WASILibc)
extension NoTerminal {
    /// The situation of a process whose stdin is `inputDescriptor` and whose
    /// stdout is `outputDescriptor`, or `nil` where it can draw and read keys as usual.
    ///
    /// Duplicates the descriptors behind ``pipedInput`` and ``pipedOutput``,
    /// so a parameter rather than a read of the process's, for a test to hand it a
    /// pipe.
    static func current(
        input inputDescriptor: Int32 = STDIN_FILENO, output outputDescriptor: Int32 = STDOUT_FILENO,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self? {
        let input = connection(of: inputDescriptor, environment: environment)
        let output = connection(of: outputDescriptor, environment: environment)
        guard input != .terminal || output != .terminal else { return nil }
        // A dumb terminal is a terminal to read keys from: only its drawing is
        // the trouble, so stdin is not the one to name.
        return Self(
            input: input == .dumbTerminal ? .terminal : input, output: output,
            pipedInput: kept(inputDescriptor, input), pipedOutput: kept(outputDescriptor, output),
            environment: environment)
    }

    /// What `descriptor` is connected to.
    private static func connection(of descriptor: Int32, environment: [String: String]) -> Connection {
        if isatty(descriptor) == 1 { return environment["TERM"] == "dumb" ? .dumbTerminal : .terminal }
        var status = stat()
        guard unsafe fstat(descriptor, &status) == 0 else { return .closed }
        switch status.st_mode & S_IFMT {
        case S_IFIFO: return .pipe
        case S_IFREG: return .file
        case S_IFSOCK: return .socket
        default: return .device
        }
    }

    /// `descriptor` under a number of its own, where it carries data, as
    /// ``pipedInput`` and ``pipedOutput`` keep it; not `/dev/null`, nor a closed
    /// stream, nor a terminal.
    private static func kept(_ descriptor: Int32, _ connection: Connection) -> FileHandle? {
        guard connection == .pipe || connection == .file || connection == .socket else { return nil }
        let copy = fcntl(descriptor, F_DUPFD_CLOEXEC, 3)
        return copy >= 0 ? FileHandle(fileDescriptor: copy, closeOnDealloc: true) : nil
    }

    /// Points whichever of stdin and stdout isn't a terminal at the process's
    /// controlling terminal, as ``Outcome/drawOnControllingTerminal`` asks.
    ///
    /// - Returns: Whether it could: not with no controlling terminal, or where
    ///   `TERM` is `dumb`.
    func pointStandardStreamsAtControllingTerminal() -> Bool {
        guard environment["TERM"] != "dumb" else { return false }
        let terminal = Self.openControllingTerminal()
        guard terminal >= 0 else { return false }
        defer { close(terminal) }
        if lacksInput, dup2(terminal, STDIN_FILENO) < 0 { return false }
        if lacksOutput, dup2(terminal, STDOUT_FILENO) < 0 { return false }
        return true
    }

    /// The process's controlling terminal, opened to read and write, or -1
    /// where it has none.
    ///
    /// On Darwin by the terminal's own device (`/dev/ttys005`), not by
    /// `/dev/tty`: a descriptor of `/dev/tty` is one Darwin's `poll(2)` answers
    /// `POLLNVAL` for and its `kqueue(2)` refuses, so nothing can wait on it
    /// (TUITerminalHost's `ProcessAncestry.ownTerminalDevicePath()`). Pointed at it, stdin
    /// read as input at its end (`StdinArrivalNotifier.isAtEndOfInput`, which
    /// takes any answer from `poll` for readable), so no key was ever heard
    /// and ⌃Q did not quit (CI 106 on, every macOS lane; no_terminal_smoke
    /// case 6). `/dev/tty` where the device has no name, or the one named is
    /// not this session's terminal.
    static func openControllingTerminal() -> Int32 {
        #if canImport(Darwin)
            if let path = ProcessAncestry.ownTerminalDevicePath() {
                let device = unsafe open(path, O_RDWR | O_NOCTTY)
                if device >= 0, tcgetsid(device) == getsid(0) { return device }
                if device >= 0 { close(device) }
            }
        #endif
        return unsafe open("/dev/tty", O_RDWR | O_NOCTTY)
    }
}

#endif
