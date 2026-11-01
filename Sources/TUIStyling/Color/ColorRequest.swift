//  🖥️ TUI — A Terminal UI framework for Swift
//  ColorRequest.swift
//
//  What the person running the program said about colour, through the
//  environment. One reading, so that everything that asks gets the same answer.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What the environment says the person running the program wants of colour:
/// `NO_COLOR`, `FORCE_COLOR`, `CLICOLOR_FORCE` and `CLICOLOR`.
///
/// # The sources
///
/// Read on 2026-11-01:
///
/// - no-color.org: `NO_COLOR` present and not empty, whatever its value, stops
///   ANSI colour being added. It says nothing against bold, underline or italic.
///   A user's config file or a program's command-line flag overrides it.
/// - force-color.org: `FORCE_COLOR` present and not empty, whatever its value,
///   forces colour. It defines no levels. Its example checks it after `NO_COLOR`,
///   so it wins.
/// - bixense.com/clicolors, deprecated in favour of those two: an empty variable
///   counts as unset. `NO_COLOR` beats `CLICOLOR_FORCE` beats `CLICOLOR`. `FORCE_COLOR`
///   is an alias for `CLICOLOR_FORCE`, "unless `NO_COLOR` is also set". `CLICOLOR`
///   means use colour on a terminal, which is what new programs do anyway.
/// - Node (`cli.html`, `tty.getColorDepth`): `FORCE_COLOR` of `1`, `true` or empty is
///   16 colours, `2` is 256, `3` is millions, and anything else, `0` and `false`
///   among them, is none. A supported value makes it ignore `NO_COLOR`, with a warning.
/// - `supports-color`, which chalk uses: `false` is none; `true` and empty turn colour
///   on and leave the level to detection; digits name a level exactly, capped at 3,
///   and `0` is none; anything else is ignored. It doesn't read `NO_COLOR`.
/// - Python 3.13 (`_colorize.can_colorize`): `NO_COLOR` not empty is off, then
///   `FORCE_COLOR` not empty is on, whatever its value, and it beats `TERM=dumb`.
///   Its documentation says `NO_COLOR` takes precedence.
///
/// # Where they disagree
///
/// - **`NO_COLOR` and `FORCE_COLOR` both set: no colour.** The clicolors text and
///   Python say so outright, and force-color.org only implies the opposite through
///   the order of two lines in an example. A person sets `NO_COLOR` for their own
///   eyes, whereas `FORCE_COLOR` is often set for them, by a CI service or a wrapper.
///   Getting it wrong the other way shows colour to someone who asked not to see it.
/// - **`FORCE_COLOR` empty: unset.** As force-color.org, no-color.org, clicolors and
///   Python have it, and against Node and `supports-color`, which read it as on.
///   `FORCE_COLOR= myapp` is how a shell clears a variable, and every other variable
///   here reads an empty value that way.
/// - **`FORCE_COLOR=0` and `false`: off.** As Node and `supports-color` have it, and
///   against the letter of force-color.org and Python, which would force colour.
///   Nobody writes `0` to mean on.
/// - **`FORCE_COLOR` digits: at least that level.** It asks for colour, so it can
///   raise what `TERM` understates and never takes colour away: `1` leaves a
///   truecolor terminal at truecolor, where Node and `supports-color` would lower
///   it. `4` and above is the top level, as `supports-color` has it, rather than
///   none, as Node does.
/// - **`FORCE_COLOR` of any other word: on, at the detected level.** `true` is
///   `supports-color`'s reading, and force-color.org's "regardless of its value" covers
///   the rest, against `supports-color` ignoring them and Node turning colour off.
/// - **`CLICOLOR=0`: off.** The current clicolors text calls any value not empty "set",
///   but until June 2023 it said `CLICOLOR == 0` meant no colour, and Rust's
///   `anstyle-query` still reads it so. `false` goes with it, for consistency.
/// - **`CLICOLOR_FORCE=0`: not a force, and not an off.** `anstyle-query` and the current
///   text would force, but the text until 2023 forced on `CLICOLOR_FORCE != 0`. It is a
///   way of not asking, so the next variable decides.
/// - **Any other `CLICOLOR`: nothing.** A TUI app already uses colour on a terminal,
///   which is all it asks for, so it doesn't count as stated.
package enum ColorRequest: Equatable, Sendable {
    /// Nothing: colour is up to what the terminal can do and where the output goes.
    case unstated

    /// No colour.
    case off

    /// Colour, wherever the output goes: at `depth`, or, where that's `nil`, at what
    /// the terminal can do, but at least ``ColorDepth/basic16``.
    case forced(ColorDepth?)

    /// Reads the request from `environment`.
    ///
    /// A parameter rather than a read of the process's, as
    /// ``ColorDepth/detect(environment:)`` is, so a test can pose a table
    /// without writing to the environment.
    package init(environment: [String: String]) {
        func stated(_ name: String) -> String? { Self.stated(name, in: environment) }
        if stated("NO_COLOR") != nil {
            self = .off
        } else if let force = stated("FORCE_COLOR") {
            self = Self.forceColor(force)
        } else if let force = stated("CLICOLOR_FORCE"), !Self.saysOff(force) {
            self = .forced(nil)
        } else if let colour = stated("CLICOLOR"), Self.saysOff(colour) {
            self = .off
        } else {
            self = .unstated
        }
    }

    /// The value of the variable `name`, unless it is missing or empty: an
    /// empty variable is taken as unset.
    package static func stated(_ name: String, in environment: [String: String]) -> String? {
        guard let value = environment[name], !value.isEmpty else { return nil }
        return value
    }

    /// What a `FORCE_COLOR` that isn't empty asks for.
    private static func forceColor(_ value: String) -> Self {
        if saysOff(value) { return .off }
        guard value.allSatisfy({ $0.isASCII && $0.isNumber }) else { return .forced(nil) }
        // Digits rather than `Int(value)`: a number too large for an `Int` is still
        // only "the most there is".
        switch value.drop(while: { $0 == "0" }) {
        case "1": return .forced(.basic16)
        case "2": return .forced(.palette256)
        default: return .forced(.truecolor)
        }
    }

    /// Whether a value says no: `false`, in any case, or a number that is zero.
    private static func saysOff(_ value: String) -> Bool {
        value.allSatisfy { $0 == "0" } || value.lowercased() == "false"
    }
}
