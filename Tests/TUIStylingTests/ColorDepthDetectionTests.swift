//  🖥️ TUI — A Terminal UI framework for Swift
//  ColorDepthDetectionTests.swift
//
//  `ColorDepth.detect()` had one call site — the lazy initializer of
//  `processCurrent` — and no test. Every colour test pins the depth through
//  `withCurrent`/`withCap` instead, so the whole TERM decision table was
//  unasserted whichever way the ambient environment happened to branch, and
//  under CI (where TERM is usually unset) detection returned at the second
//  rung and never reached the table at all.
//
//  The order is load-bearing: "xterm-256color" also contains "color", so
//  putting the basic16 rule first silently downgrades the most common
//  termtype — and the depth gates the WCAG contrast floor, the SGR encoding
//  and the pulse ramp.
//
//  The table is posed on a DICTIONARY, never on the real environment. The
//  first version of this file set `TERM` process-wide and restored it, which
//  left a window in which a parallel test could be the one to trigger the
//  lazy `processCurrent` initializer and latch the process at a fake value;
//  the guard against that was a single hand-written `_ = ColorDepth.current`
//  nobody was obliged to remember. `detect(environment:)` removes the window
//  rather than guarding it, and `.swiftlint.yml`'s
//  `process_terminal_environment_mutation` rule keeps it removed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIStyling

/// The documented detection order, one test per rung.
///
/// Every case is a dictionary handed to ``ColorDepth/detect(environment:)``,
/// so nothing here touches the process environment, nothing has to be
/// restored, and the suite needs no serialization.
@Suite("Colour depth detection")
struct ColorDepthDetectionTests {

    @Test(
        "Every documented TERM rung answers as documented",
        arguments: [
            // Rung 3: the one terminal that gets no escape codes at all.
            ("dumb", ColorDepth.noColor),
            // Rung 4: a truecolour terminal named by TERM alone — what ssh
            // forwards. Each fell to rung 8 before the rung existed.
            ("xterm-ghostty", .truecolor),
            ("xterm-kitty", .truecolor),
            ("wezterm", .truecolor),
            ("alacritty", .truecolor),
            ("foot", .truecolor),
            // Rung 5: direct colour.
            ("xterm-direct", .truecolor),
            ("iterm2-direct", .truecolor),
            // Rung 6: the common case. These also contain "color", which is
            // why this rung has to be tested before rung 7 is trusted.
            ("xterm-256color", .palette256),
            ("screen-256color", .palette256),
            ("tmux-256color", .palette256),
            // Rung 7: some colour, but not 256.
            ("xterm-16color", .basic16),
            ("xterm-color", .basic16),
            // Rung 8: set but unrecognised.
            ("vt100", .basic16),
            ("xterm", .basic16),
        ])
    func termTable(term: String, expected: ColorDepth) {
        #expect(ColorDepth.detect(environment: ["TERM": term]) == expected, "TERM=\(term)")
    }

    @Test("TERM is matched case-insensitively")
    func termIsLowercased() {
        #expect(ColorDepth.detect(environment: ["TERM": "XTERM-256COLOR"]) == .palette256)
        #expect(ColorDepth.detect(environment: ["TERM": "DUMB"]) == .noColor)
        #expect(ColorDepth.detect(environment: ["TERM": "XTERM-GHOSTTY"]) == .truecolor)
    }

    /// Rung 4 is evidence about one program each, so a terminfo name that
    /// merely contains one of them is not credited: it falls to the rungs
    /// that read the name's own suffixes.
    @Test("A truecolour terminal's name is matched whole")
    func truecolorNamesAreWhole() {
        #expect(ColorDepth.detect(environment: ["TERM": "footer"]) == .basic16)
        #expect(ColorDepth.detect(environment: ["TERM": "xterm-kitty-like"]) == .basic16)
        #expect(ColorDepth.detect(environment: ["TERM": "screen.xterm-ghostty"]) == .basic16)
    }

    /// The case the rung exists for, posed whole: what an OpenSSH hop hands
    /// the far side. `COLORTERM` is absent rather than unhelpful, and a
    /// `COLORTERM` that is present but claims nothing must not stop the name
    /// from answering either.
    @Test("Over ssh, Ghostty and kitty keep truecolour without COLORTERM")
    func truecolorSurvivesAnSSHHop() {
        for term in ["xterm-ghostty", "xterm-kitty"] {
            #expect(ColorDepth.detect(environment: ["TERM": term, "SSH_TTY": "/dev/ttys001"]) == .truecolor)
            #expect(ColorDepth.detect(environment: ["TERM": term, "COLORTERM": ""]) == .truecolor)
        }
    }

    @Test("An unset TERM means truecolor, not no colour")
    func unsetTermIsTruecolor() {
        // The deliberate asymmetry: an absent TERM is an IDE, a redirect or an
        // environment that was not propagated — no positive evidence of a
        // limited terminal — and the rule is to downgrade only on evidence.
        #expect(ColorDepth.detect(environment: [:]) == .truecolor)
    }

    @Test("An empty TERM counts as unset, as every other variable here does")
    func emptyTermIsUnset() {
        // `TERM= myapp` is how a shell clears it. It used to fall to the bottom
        // of the table, "set but unrecognized", and draw in 16 colours.
        #expect(ColorDepth.detect(environment: ["TERM": ""]) == .truecolor)
        #expect(ColorDepth.detect(environment: ["TERM": "", "NO_COLOR": "1"]) == .noColor)
    }

    @Test(
        "COLORTERM outranks the whole TERM table",
        arguments: ["truecolor", "24bit", "TrueColor", "24BIT"])
    func colortermWins(colorterm: String) {
        // Rung 1, and it must beat rung 3: a terminal that sets COLORTERM and
        // an unhelpful TERM is common, and `dumb` is the strongest thing the
        // table can say.
        #expect(
            ColorDepth.detect(environment: ["TERM": "dumb", "COLORTERM": colorterm])
                == .truecolor)
        #expect(
            ColorDepth.detect(environment: ["TERM": "vt100", "COLORTERM": colorterm])
                == .truecolor)
    }

    @Test("A COLORTERM that claims nothing falls through to TERM")
    func unhelpfulColortermIsIgnored() {
        // Only "truecolor" and "24bit" are claims. Anything else — and some
        // terminals set COLORTERM to their own name — must not upgrade.
        #expect(
            ColorDepth.detect(environment: ["TERM": "xterm-16color", "COLORTERM": "gnome-terminal"])
                == .basic16)
        #expect(ColorDepth.detect(environment: ["TERM": "dumb", "COLORTERM": ""]) == .noColor)
    }

    @Test("Detection memoizes nothing")
    func detectionIsNotCached() {
        // What makes `detect(environment:)` usable after a terminal change, and
        // what the latched `current` deliberately is not: two calls, two
        // environments, two answers — no first answer is kept.
        #expect(ColorDepth.detect(environment: ["TERM": "xterm-256color"]) == .palette256)
        #expect(ColorDepth.detect(environment: ["TERM": "dumb"]) == .noColor)
        #expect(ColorDepth.detect(environment: ["TERM": "xterm-256color"]) == .palette256)
    }

    // MARK: - What the person running the program asks for

    @Test("NO_COLOR: present and not empty, whatever its value", arguments: ["1", "0", "false", "true", "anything"])
    func noColorAnyValue(value: String) {
        #expect(ColorDepth.detect(environment: ["NO_COLOR": value, "TERM": "xterm-256color"]) == .noColor)
        #expect(ColorDepth.detect(environment: ["NO_COLOR": value, "COLORTERM": "truecolor"]) == .noColor)
    }

    @Test("An empty variable counts as unset", arguments: ["NO_COLOR", "FORCE_COLOR", "CLICOLOR_FORCE", "CLICOLOR"])
    func emptyIsUnset(name: String) {
        #expect(ColorDepth.detect(environment: [name: "", "TERM": "xterm-256color"]) == .palette256)
        #expect(ColorDepth.detect(environment: [name: "", "TERM": "dumb"]) == .noColor)
    }

    @Test(
        "FORCE_COLOR digits ask for at least that level, and never lower one",
        arguments: [
            ("0", ColorDepth.noColor), ("00", .noColor), ("1", .basic16), ("01", .basic16), ("2", .palette256),
            ("3", .truecolor), ("4", .truecolor), ("16", .truecolor), ("99999999999999999999999", .truecolor),
        ])
    func forceColorLevels(value: String, depth: ColorDepth) {
        for term in ["xterm", "xterm-256color", "xterm-ghostty", "dumb"] {
            let expected = depth == .noColor ? depth : max(ColorDepth.terminalDepth(environment: ["TERM": term]), depth)
            #expect(ColorDepth.detect(environment: ["FORCE_COLOR": value, "TERM": term]) == expected, "TERM=\(term)")
        }
        let onTruecolor: ColorDepth = depth == .noColor ? .noColor : .truecolor
        #expect(ColorDepth.detect(environment: ["FORCE_COLOR": value, "COLORTERM": "truecolor"]) == onTruecolor)
    }

    @Test("FORCE_COLOR=false is off, in any case", arguments: ["false", "False", "FALSE"])
    func forceColorFalse(value: String) {
        #expect(ColorDepth.detect(environment: ["FORCE_COLOR": value]) == .noColor)
    }

    @Test(
        "FORCE_COLOR of any other word, and CLICOLOR_FORCE: what the terminal can do, but at least 16 colours",
        arguments: [
            ("FORCE_COLOR", "true"), ("FORCE_COLOR", "TRUE"), ("FORCE_COLOR", "yes"), ("FORCE_COLOR", "-1"),
            ("FORCE_COLOR", "1.5"), ("FORCE_COLOR", "٣"), ("CLICOLOR_FORCE", "1"), ("CLICOLOR_FORCE", "true"),
        ])
    func forcedWithoutALevel(name: String, value: String) {
        #expect(ColorDepth.detect(environment: [name: value, "TERM": "xterm"]) == .basic16)
        #expect(ColorDepth.detect(environment: [name: value, "TERM": "xterm-256color"]) == .palette256)
        #expect(ColorDepth.detect(environment: [name: value, "COLORTERM": "truecolor"]) == .truecolor)
        #expect(ColorDepth.detect(environment: [name: value, "TERM": "dumb"]) == .basic16)
    }

    @Test("CLICOLOR_FORCE=0 neither forces nor turns colour off", arguments: ["0", "false"])
    func cliColorForceZero(value: String) {
        #expect(ColorDepth.detect(environment: ["CLICOLOR_FORCE": value, "TERM": "xterm-256color"]) == .palette256)
        #expect(ColorDepth.detect(environment: ["CLICOLOR_FORCE": value, "TERM": "dumb"]) == .noColor)
        #expect(
            ColorDepth.detect(environment: ["CLICOLOR_FORCE": value, "CLICOLOR": "0", "TERM": "xterm"]) == .noColor)
    }

    @Test("CLICOLOR=0 is off, and any other value changes nothing, not even on a dumb terminal")
    func cliColor() {
        #expect(ColorDepth.detect(environment: ["CLICOLOR": "0", "TERM": "xterm-256color"]) == .noColor)
        #expect(ColorDepth.detect(environment: ["CLICOLOR": "false", "TERM": "xterm-256color"]) == .noColor)
        #expect(ColorDepth.detect(environment: ["CLICOLOR": "1", "TERM": "xterm-256color"]) == .palette256)
        #expect(ColorDepth.detect(environment: ["CLICOLOR": "1", "TERM": "dumb"]) == .noColor)
    }

    @Test(
        "The order: NO_COLOR, then FORCE_COLOR, then CLICOLOR_FORCE, then CLICOLOR",
        arguments: [
            (["NO_COLOR": "1", "FORCE_COLOR": "3"], ColorDepth.noColor),
            (["NO_COLOR": "1", "CLICOLOR_FORCE": "1"], .noColor),
            (["NO_COLOR": "", "FORCE_COLOR": "2", "TERM": "xterm"], .palette256),
            (["FORCE_COLOR": "0", "CLICOLOR_FORCE": "1"], .noColor),
            (["FORCE_COLOR": "2", "CLICOLOR_FORCE": "1", "CLICOLOR": "0", "TERM": "xterm"], .palette256),
            (["FORCE_COLOR": "", "CLICOLOR_FORCE": "1", "CLICOLOR": "0"], .truecolor),
            (["CLICOLOR_FORCE": "1", "CLICOLOR": "0"], .truecolor),
        ] as [([String: String], ColorDepth)])
    func precedence(environment: [String: String], depth: ColorDepth) {
        #expect(ColorDepth.detect(environment: environment) == depth)
    }

    @Test("What the terminal can do ignores what the person asks for")
    func terminalDepthIsTheTerminals() {
        let asked = ["NO_COLOR": "1", "FORCE_COLOR": "1", "TERM": "xterm-256color"]
        #expect(ColorDepth.terminalDepth(environment: asked) == .palette256)
    }

    @Test("The default environment is the live one, read per call")
    func defaultArgumentIsTheProcessEnvironment() {
        // `detect()` must keep answering for the process that calls it, since
        // that is the call the lazy `processCurrent` initializer makes. A
        // default argument is evaluated at each call site, so this reads the
        // environment now rather than a snapshot taken at type-initialization.
        #expect(
            ColorDepth.detect()
                == ColorDepth.detect(environment: ProcessInfo.processInfo.environment))
    }

    @Test("The process-wide depth still says what this process's environment says")
    func processDepthIsNotLatchedToAFakeValue() {
        // The runtime backstop to the lint rule, and the only check that also
        // covers the OTHER route to the same defect: `ColorDepth.current` has a
        // setter, and a test assigning it process-wide would poison every
        // concurrently-rendering test exactly as a fake `TERM` would. Both pins
        // (`withCurrent`/`withCap`) are task-local and invisible here, and
        // `cap` defaults to `.truecolor`, so `current` should be precisely what
        // detection says about this process.
        //
        // It is a BACKSTOP, not the mechanism: it can only fire if the
        // poisoning happened earlier in this same process, which under the
        // parallel runner means the same shard. What makes forgetting
        // impossible is the lint rule; this catches the case the regex cannot
        // see (`let name = "TERM"; setenv(name, …)`) when luck cooperates.
        #expect(ColorDepth.current == ColorDepth.detect())
    }
}
