//  🖥️ TUI — A Terminal UI framework for Swift
//  NoTerminal.swift
//
//  What an app launched without a terminal to draw on is told: what is missing,
//  and what it can do instead.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
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
        #else
            let terminal = open("/dev/tty", O_RDWR | O_NOCTTY)
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
        let line = "\(ProcessInfo.processInfo.processName): \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        return 1
    }
}

// MARK: - Finding out

#if !canImport(WASILibc)
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
        guard fstat(descriptor, &status) == 0 else { return .closed }
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
        let terminal = open("/dev/tty", O_RDWR | O_NOCTTY)
        guard terminal >= 0 else { return false }
        defer { close(terminal) }
        if lacksInput, dup2(terminal, STDIN_FILENO) < 0 { return false }
        if lacksOutput, dup2(terminal, STDOUT_FILENO) < 0 { return false }
        return true
    }
}

#endif
