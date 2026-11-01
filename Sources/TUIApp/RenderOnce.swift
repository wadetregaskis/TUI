//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderOnce.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation
import TUIStyling

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
#endif

/// What ``renderOnce(output:content:)`` writes: plain text, or the escape
/// sequences that style it.
public enum RenderOnceOutput: Sendable, Equatable {
    /// Decided when it draws: escape sequences to a terminal, plain text to
    /// anything else, such as a file or a pipe to another command. The person
    /// running the program can overrule that with an environment variable, in
    /// this order:
    ///
    /// 1. `TUI_FORCE_ESCAPES`: `0` for plain text; anything else not empty for
    ///    escape sequences, even down a pipe.
    /// 2. Whatever asks for colour wherever the output goes, as `ColorDepth`
    ///    reads the environment: `FORCE_COLOR` or `CLICOLOR_FORCE`, unless `NO_COLOR`
    ///    is set too. Escape sequences, even down a pipe.
    ///
    /// A terminal whose `TERM` is `dumb` gets plain text, unless those say
    /// otherwise: it would print the sequences as text.
    ///
    /// The sequences have the colours `ColorDepth.current` allows, which is the
    /// answer a running app gets. So `NO_COLOR` leaves the colours out of them, and
    /// a terminal still gets bold and the other text attributes.
    case automatic

    /// Plain text, whatever stdout is: no colour and no attributes.
    case plainText

    /// The escape sequences, whatever stdout is and whatever the environment
    /// says. Nothing moves the cursor but the newlines, so the output can be
    /// captured and printed later.
    case escapeSequences

    /// How a one-off render writes, once decided.
    enum Resolved: Equatable {
        /// Text alone.
        case plainText
        /// With its escape sequences, in the colours `ColorDepth.current` allows.
        case styled
        /// With its escape sequences, at `depth` rather than at the depth the person
        /// running the program asked for.
        case styledAt(ColorDepth)
    }

    /// What this asks for, given what stdout is and the environment. A
    /// parameter rather than a read of the process's, as
    /// `ColorDepth.detect(environment:)` is, so a test can pose the table
    /// without writing to the environment.
    func resolved(stdoutIsTerminal: Bool, environment: [String: String]) -> Resolved {
        let request = ColorRequest(environment: environment)
        switch self {
        case .plainText:
            return .plainText
        case .escapeSequences:
            // This is the program speaking, as a `--color=always` flag does, and
            // no-color.org has that outrank `NO_COLOR`. A request that stated no colour
            // has already set the depth, so this has to state it back.
            return request == .off ? .styledAt(ColorDepth.terminalDepth(environment: environment)) : .styled
        case .automatic:
            break
        }
        if let forced = ColorRequest.stated("TUI_FORCE_ESCAPES", in: environment) {
            return forced == "0" ? .plainText : .styled
        }
        if case .forced = request { return .styled }
        guard stdoutIsTerminal, environment["TERM"] != "dumb" else { return .plainText }
        return .styled
    }
}

/// Draws a view once, from the line the cursor is on, for a command-line tool
/// that doesn't need a full ``App``.
///
/// It takes nothing over: no alternate screen, no raw mode, no keys. The view
/// goes where the program's next `print` would, at the size it wants up to the
/// terminal's width, and the cursor ends up on the line after it, so whatever
/// comes next follows on. A view taller than the screen scrolls, as any long
/// output does. It is one frame: `onAppear` and `.task` don't run, and nothing
/// animates.
///
/// To a terminal it writes styled text. To anything else, such as a file or
/// a pipe to another command, it writes plain text, without the escape sequences
/// or the spaces a row ends in, as wide as `COLUMNS` says, or 80. See
/// ``RenderOnceOutput`` for how to change that.
///
/// # Example
///
/// ```swift
/// renderOnce {
///     VStack(alignment: .leading) {
///         Text("Hello, TUI!")
///             .bold()
///             .foregroundStyle(.cyan)
///         Divider()
///         Text("Version \(tuiVersion)")
///             .dim()
///     }
/// }
/// ```
///
/// - Parameters:
///   - output: What to write: by default, whatever suits where stdout goes.
///   - content: A ViewBuilder closure that defines the view to render.
@MainActor
public func renderOnce<Content: View>(
    output: RenderOnceOutput = .automatic, @ViewBuilder content: () -> Content
) {
    let view = content()
    // What the program printed first goes first: `print` buffers down a pipe, and
    // `Terminal` writes past that buffer.
    fflush(nil)
    let renderer = ViewRenderer(terminal: Terminal())
    switch output.resolved(stdoutIsTerminal: stdoutIsTerminal, environment: ProcessInfo.processInfo.environment) {
    case .plainText:
        renderer.render(view, plainText: true)
    case .styled:
        renderer.render(view)
    case .styledAt(let depth):
        ColorDepth.withCurrent(depth) { renderer.render(view) }
    }
}

/// Whether standard output is a terminal. A wasm program's stdio is no
/// terminal to `isatty`, whatever its host is drawing with, so there the answer
/// is yes: a host that wants plain text can ask for it.
private var stdoutIsTerminal: Bool {
    #if canImport(WASILibc)
        true
    #else
        isatty(STDOUT_FILENO) == 1
    #endif
}
