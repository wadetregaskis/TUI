//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalPointerShapes.swift
//
//  Which terminals let an app set the mouse pointer's shape (OSC 22), and by
//  which names. See `Documentation/Terminals/Terminal compatibility survey.md`,
//  "Pointer shapes (OSC 22)".
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - The shapes

/// A shape TUIkit can ask a terminal to give the mouse pointer: what a
/// SwiftUI `PointerStyle` comes down to, before a host spells it
/// (``PointerShapeHost/name(for:)``).
///
/// One case per shape a host can draw, the directions of a resize folded in,
/// because the names are per shape: CSS has `col-resize` for a divider either
/// way and `w-resize` for one that only goes left, and the X11 cursor font
/// has an arrow for each side.
package enum PointerShape: UInt8, CaseIterable, Hashable, Sendable {
    /// The platform's arrow: `PointerStyle.default`.
    case arrow
    /// The I-beam of horizontal text.
    case text
    /// The I-beam of vertical text.
    case verticalText
    /// A pointing hand: a link.
    case link
    /// An open hand: content that can be dragged about.
    case grab
    /// A closed hand: content being dragged about.
    case grabbing
    /// A column's divider, resizable either way.
    case columnResize
    /// A column's divider that only goes left.
    case columnResizeLeft
    /// A column's divider that only goes right.
    case columnResizeRight
    /// A row's divider, resizable either way.
    case rowResize
    /// A row's divider that only goes up.
    case rowResizeUp
    /// A row's divider that only goes down.
    case rowResizeDown
    /// A frame's edge or corner, moved toward the given compass point: one
    /// way (`north` … `northWest`) or both (`northSouth` … `northWestSouthEast`).
    case resizeNorth, resizeSouth, resizeEast, resizeWest
    case resizeNorthEast, resizeNorthWest, resizeSouthEast, resizeSouthWest
    case resizeNorthSouth, resizeEastWest, resizeNorthEastSouthWest, resizeNorthWestSouthEast
    /// A crosshair: precise rectangular selection.
    case crosshair
    /// A magnifying glass with a plus.
    case zoomIn
    /// A magnifying glass with a minus.
    case zoomOut
}

// MARK: - The hosts

/// A terminal documented to set the pointer's shape when asked by name with
/// OSC 22 (`ESC ] 22 ; name ESC \`), and so the names it takes.
///
/// Every one of them reads the sequence by name, and the names are not
/// agreed: Ghostty, kitty and foot take CSS's `cursor` keywords, xterm the X11
/// cursor font's, and iTerm2 a subset of X11's of its own. Ghostty's page says
/// as much, and says to send the sequence only when the program can "switch
/// between cursor names by detecting the current terminal" — which TUIkit
/// does, and why there is a case per host rather than one per naming scheme.
///
/// What each was read from, 2026-10-19 (the shape is not in the byte stream,
/// so nothing here could be measured from inside; `pointer_shape_card.py`
/// shows a person each one):
///
/// | Host | Since | Names | No style (mid-run) | Reset |
/// |---|---|---|---|---|
/// | Ghostty | 1.0.0 (its VT reference) | CSS, X11 aliases too | `default` | the mouse modes going off (its source) |
/// | kitty | 0.31.0 (its pointer-shapes page) | CSS | empty | empty; a stack per screen |
/// | foot | 1.12.0 (its changelog) | CSS, X11 fallbacks | empty | empty |
/// | iTerm2 | 3.5.0 (its source, unchanged to 3.6.11) | 19 X11 names | empty | empty |
/// | xterm | patch #367 (its changelog) | X11 cursor font | empty | empty |
package enum PointerShapeHost: Equatable, Sendable {
    /// Ghostty, from 1.0.0.
    case ghostty
    /// kitty, from 0.31.0.
    case kitty
    /// foot, from 1.12.0.
    case foot
    /// iTerm2, from 3.5.0.
    case iTerm2
    /// xterm, from patch #367.
    case xterm
    /// A terminal nothing here names, turned on by the user or the app
    /// (``TerminalClient/pointerShapeSupport``): spoken to in CSS's names, the
    /// ones most hosts that take OSC 22 read.
    case unnamed

    /// The name this host takes for `shape`, or `nil` where it has none — the
    /// pointer then shows the host's own (``unsetName``), never a shape left
    /// over from somewhere else.
    package func name(for shape: PointerShape) -> String? {
        switch self {
        case .ghostty: Self.ghosttyName(shape)
        case .kitty, .foot, .unnamed: Self.cssName(shape)
        case .xterm: Self.x11Name(shape)
        case .iTerm2: Self.iTerm2Name(shape)
        }
    }

    /// The name that puts the host's own pointer back while the app runs,
    /// with its mouse reporting on.
    ///
    /// Empty everywhere it is read as a reset, but on Ghostty, whose older
    /// releases ignore an empty name (its source: an empty name became a reset
    /// only later; an unknown one is logged and dropped). There it is
    /// `default`, the arrow — what Ghostty draws itself while an app reports
    /// the mouse.
    package var unsetName: String {
        self == .ghostty ? "default" : ""
    }

    /// Whether a person has seen this host's pointer put back as the app
    /// leaves — after the teardown, the shell's own pointer over the window
    /// again, on a quit and on a suspend. TUIkit's own controls set shapes
    /// without being asked (``TerminalClient/builtInPointerShapes``) only
    /// where this is so, because a pointer left in a shape the app never
    /// asked for is a defect of TUIkit's, not of the app's.
    ///
    /// iTerm2 alone so far: the owner read `pointer_shape_card.py` in iTerm2
    /// 3.7.6 on 2026-10-19 and had the shell's own pointer back once the card
    /// closed. Quit and suspend write the same reset, the empty name. Every
    /// other host's reset is documented (the table above), and the card is
    /// what turns its row on, once its reading is in the compatibility survey.
    package var resetIsMeasured: Bool { self == .iTerm2 }
}

// MARK: - The names

extension PointerShapeHost {
    /// CSS's `cursor` keyword for `shape`: Ghostty's, kitty's and foot's.
    /// Every shape has one (``cssNames`` is total, which a test holds).
    static func cssName(_ shape: PointerShape) -> String {
        cssNames[shape] ?? "default"
    }

    /// Ghostty's name for `shape`: CSS's, but for the shapes its macOS app
    /// draws nothing for.
    ///
    /// Ghostty reads every CSS keyword (its `mouse.zig`), but its macOS app
    /// gives only some of them a cursor and IGNORES the rest
    /// (`SurfaceView.setCursorShape`, 1.3.1: "We ignore unknown shapes"),
    /// leaving the pointer in whatever shape it had before. Read off the
    /// pointer card by the owner, 2026-10-19: `col-resize`, `row-resize`, the
    /// diagonals and the magnifying glasses showed nothing new. So a divider
    /// either way takes the two-way arrow the app does draw (`ew-resize`,
    /// `ns-resize`), and a diagonal or a magnifying glass, which it has
    /// nothing for, Ghostty's own pointer (`nil`, sent as ``unsetName``)
    /// rather than the last shape. Ghostty on Linux draws all of CSS's, but a
    /// terminal reached over ssh cannot be told apart by its platform, so
    /// every Ghostty is spoken to as macOS's is.
    static func ghosttyName(_ shape: PointerShape) -> String? {
        if ghosttyUndrawn.contains(shape) { return nil }
        return ghosttySubstitutes[shape] ?? cssName(shape)
    }

    /// The CSS keywords Ghostty's macOS app ignores, for which it draws a
    /// keyword it does take that means the same (``ghosttyName(_:)``).
    static let ghosttySubstitutes: [PointerShape: String] = [
        .columnResize: "ew-resize", .rowResize: "ns-resize",
    ]

    /// The shapes Ghostty's macOS app has no cursor for at all
    /// (``ghosttyName(_:)``).
    static let ghosttyUndrawn: Set<PointerShape> = [
        .resizeNorthEast, .resizeNorthWest, .resizeSouthEast, .resizeSouthWest,
        .resizeNorthEastSouthWest, .resizeNorthWestSouthEast, .zoomIn, .zoomOut,
    ]

    /// The X11 cursor font's name for `shape`: xterm's.
    static func x11Name(_ shape: PointerShape) -> String? {
        x11Names[shape]
    }

    /// iTerm2's name for `shape`, from the table its OSC 22 is read through.
    static func iTerm2Name(_ shape: PointerShape) -> String? {
        iTerm2Names[shape]
    }

    /// CSS's keywords, one for every shape.
    static let cssNames: [PointerShape: String] = [
        .arrow: "default", .text: "text", .verticalText: "vertical-text", .link: "pointer",
        .grab: "grab", .grabbing: "grabbing",
        .columnResize: "col-resize", .columnResizeLeft: "w-resize", .columnResizeRight: "e-resize",
        .rowResize: "row-resize", .rowResizeUp: "n-resize", .rowResizeDown: "s-resize",
        .resizeNorth: "n-resize", .resizeSouth: "s-resize", .resizeEast: "e-resize", .resizeWest: "w-resize",
        .resizeNorthEast: "ne-resize", .resizeNorthWest: "nw-resize",
        .resizeSouthEast: "se-resize", .resizeSouthWest: "sw-resize",
        .resizeNorthSouth: "ns-resize", .resizeEastWest: "ew-resize",
        .resizeNorthEastSouthWest: "nesw-resize", .resizeNorthWestSouthEast: "nwse-resize",
        .crosshair: "crosshair", .zoomIn: "zoom-in", .zoomOut: "zoom-out",
    ]

    /// The X11 cursor font's names. It has no closed hand, no vertical I-beam
    /// and no magnifying glass, and no arrow two ways along a diagonal; `hand1`
    /// is the open hand (foot and Ghostty read it as CSS's `grab`), and a
    /// diagonal pair takes the corner it starts from.
    static let x11Names: [PointerShape: String] = [
        .arrow: "left_ptr", .text: "xterm", .link: "hand2", .grab: "hand1",
        .columnResize: "sb_h_double_arrow", .columnResizeLeft: "sb_left_arrow",
        .columnResizeRight: "sb_right_arrow",
        .rowResize: "sb_v_double_arrow", .rowResizeUp: "sb_up_arrow", .rowResizeDown: "sb_down_arrow",
        .resizeNorth: "top_side", .resizeSouth: "bottom_side", .resizeEast: "right_side", .resizeWest: "left_side",
        .resizeNorthEast: "top_right_corner", .resizeNorthWest: "top_left_corner",
        .resizeSouthEast: "bottom_right_corner", .resizeSouthWest: "bottom_left_corner",
        .resizeNorthSouth: "sb_v_double_arrow", .resizeEastWest: "sb_h_double_arrow",
        .resizeNorthEastSouthWest: "top_right_corner", .resizeNorthWestSouthEast: "top_left_corner",
        .crosshair: "crosshair",
    ]

    /// iTerm2's names, from the table its OSC 22 is read through
    /// (`PTYSession.screenSetPointerShape`, the same from 3.5.0 to 3.6.11):
    /// nineteen X11 names, each mapped to an `NSCursor`. It has no hand but the
    /// pointing one (`hand1` and `hand2` both), so no grab; no vertical I-beam,
    /// zoom or diagonal resize; and its downward arrow is `based_arrow_down`.
    /// (Its development branch adds `fleur` for an open hand and
    /// `plus`/`minus` for zoom; none is in a release yet.)
    static let iTerm2Names: [PointerShape: String] = [
        .arrow: "arrow", .text: "xterm", .link: "hand2",
        .columnResize: "sb_h_double_arrow", .resizeEastWest: "sb_h_double_arrow",
        .columnResizeLeft: "sb_left_arrow", .resizeWest: "sb_left_arrow",
        .columnResizeRight: "sb_right_arrow", .resizeEast: "sb_right_arrow",
        .rowResize: "sb_v_double_arrow", .resizeNorthSouth: "sb_v_double_arrow",
        .rowResizeUp: "sb_up_arrow", .resizeNorth: "sb_up_arrow",
        .rowResizeDown: "based_arrow_down", .resizeSouth: "based_arrow_down",
        .crosshair: "crosshair",
    ]
}

// MARK: - The sequence

extension PointerShapeHost {
    /// `ESC ] 22 ; name ESC \`: the pointer's shape set by name, or, with an
    /// empty name, put back. String Terminator, as TUIkit ends every OSC
    /// (`TerminalHyperlink`): each host here takes it.
    package static func sequence(naming name: String) -> String {
        "\u{1B}]22;\(name)\u{1B}\\"
    }

    /// The sequence that puts the pointer back as the app leaves — on a quit,
    /// a suspend, and in the debt a signal pays, once a shape has been sent:
    /// the empty name, every host's reset. Written before the mouse modes go
    /// off, because on Ghostty their going off is itself the reset, to the
    /// I-beam a shell has, and a name after them would undo it.
    package static let reset = sequence(naming: "")
}

// MARK: - Identifying the host

extension PointerShapeHost {
    /// The host `environment` names, if it is one documented to take OSC 22
    /// in a version that does — `nil` for every other terminal, which is left
    /// alone.
    ///
    /// By the environment alone, as the other detectors are: no portable
    /// query reports OSC 22 (kitty's `?` query is kitty's), and each host here
    /// names itself there. A multiplexer that draws its panes itself is never
    /// one, whatever runs it — tmux, GNU screen (`STY`), zellij (`ZELLIJ`,
    /// `ZELLIJ_SESSION_NAME`): whether any passes OSC 22 on to the terminal
    /// is unmeasured, and the hypothesis is that each drops it, while the
    /// terminal the session inherited in `TERM_PROGRAM` is the one outside it.
    /// Apple Terminal and Warp document nothing.
    ///
    /// `KITTY_WINDOW_ID` and `XTERM_VERSION` count only where no terminal is
    /// named: every program a shell starts inherits them, so a VS Code or a
    /// WezTerm opened from a kitty or xterm shell carries them beside its own
    /// `TERM_PROGRAM`. `TERM` is the terminal's own, so `xterm-kitty` and
    /// `foot` stand whatever is named beside them.
    ///
    /// A version is checked where the environment states one, and a host that
    /// states none is taken to be recent: every host here parses OSC, so an
    /// older one swallows the sequence and nothing comes of it.
    package static func detect(environment: [String: String]) -> Self? {
        if TerminalHost.detectTmux(environment: environment) || isInsideScreenOrZellij(environment) { return nil }
        if TerminalHost.detectGhostty(environment: environment) {
            return version(environment, program: "ghostty", atLeast: [1, 0]) ? .ghostty : nil
        }
        if TerminalHost.detectITerm2(environment: environment) {
            return version(environment, program: "iTerm.app", atLeast: [3, 5]) ? .iTerm2 : nil
        }
        if TerminalHost.detectAppleTerminal(environment: environment)
            || TerminalHost.detectWarp(environment: environment)
        {
            return nil
        }
        let named = TerminalHost.hostProgram(environment: environment)
        let term = environment["TERM"] ?? ""
        if named == "kitty" || term == "xterm-kitty" { return .kitty }
        if named == "foot" || term == "foot" || term.hasPrefix("foot-") { return .foot }
        // Any other terminal named is that terminal, not one whose variables
        // it inherited.
        guard named == nil else { return nil }
        if environment["KITTY_WINDOW_ID"]?.isEmpty == false { return .kitty }
        if let xterm = environment["XTERM_VERSION"], !xterm.isEmpty {
            let recent = xtermPatch(xterm).map { $0 >= 367 } ?? true
            return recent ? .xterm : nil
        }
        return nil
    }

    /// Whether the process runs inside GNU screen or zellij, by the variables
    /// each sets inside its sessions (the ones `SessionLocality` reads for
    /// them too).
    static func isInsideScreenOrZellij(_ environment: [String: String]) -> Bool {
        ["STY", "ZELLIJ", "ZELLIJ_SESSION_NAME"].contains { environment[$0]?.isEmpty == false }
    }

    /// Whether the version `environment` states for `program` is at least
    /// `minimum` — `true` where it states none, or none that parses.
    ///
    /// `TERM_PROGRAM_VERSION` beside its `TERM_PROGRAM`, or iTerm2's
    /// `LC_TERMINAL_VERSION` beside its `LC_TERMINAL`, which its shell
    /// integration sets and ssh forwards.
    static func version(_ environment: [String: String], program: String, atLeast minimum: [Int]) -> Bool {
        let stated: String? =
            if environment["TERM_PROGRAM"] == program {
                environment["TERM_PROGRAM_VERSION"]
            } else if program == "iTerm.app", environment["LC_TERMINAL"] == "iTerm2" {
                environment["LC_TERMINAL_VERSION"]
            } else {
                nil
            }
        guard let stated, let components = versionComponents(stated) else { return true }
        // Part by part, a missing part read as 0, so "1" is 1.0.
        for index in 0..<max(components.count, minimum.count) {
            let part = index < components.count ? components[index] : 0
            let least = index < minimum.count ? minimum[index] : 0
            if part != least { return part > least }
        }
        return true
    }

    /// `"3.6.11"` as `[3, 6, 11]`; the digits that lead each dotted part, so
    /// `"1.3.1-main+abc"` reads as `[1, 3, 1]`. `nil` when the first part has
    /// none.
    static func versionComponents(_ version: String) -> [Int]? {
        var components: [Int] = []
        for part in version.split(separator: ".") {
            guard let number = Int(part.prefix(while: \.isNumber)) else { break }
            components.append(number)
        }
        return components.isEmpty ? nil : components
    }

    /// xterm's patch number from its `XTERM_VERSION`, `"XTerm(390)"`.
    static func xtermPatch(_ version: String) -> Int? {
        guard let open = version.firstIndex(of: "(") else { return nil }
        return Int(version[version.index(after: open)...].prefix(while: \.isNumber))
    }
}

// MARK: - The run-time answer

extension TerminalClient {
    /// Force the answer to "does this terminal take pointer shapes", whatever
    /// was detected — the counterpart of ``hyperlinkSupport`` for OSC 22.
    ///
    /// `true` turns shapes on for a host with no documentation here (spoken to
    /// in CSS's names); `false` turns them off on one that has it. `nil` (the
    /// default) means the table, unless `TUIKIT_POINTER_SHAPES` is set in the
    /// environment: `1` on, `0` off, and `all` on with TUIkit's own controls'
    /// shapes as well.
    ///
    /// Read once, as the app starts: set it in your `App`'s `init`.
    @MainActor public static var pointerShapeSupport: Bool?

    /// Whether `pointerStyle(_:)` changes the pointer in the terminal
    /// painting this app's output — the override, then the environment, then
    /// the table of documented hosts (Ghostty from 1.0.0, kitty, foot, iTerm2
    /// from 3.5.0, xterm). See *Terminal compatibility survey*, "Pointer
    /// shapes (OSC 22)".
    ///
    /// A view reads it as `\.terminalCapabilities`'
    /// ``TerminalCapabilities/Feature/pointerShapes``: supported where this is
    /// `true`, but undetermined where nobody knows whether the person sees
    /// the shape (GNOME Terminal and tmux, and a terminal TUIkit did not
    /// identify where this is `false`).
    @MainActor public static var pointerShapesSupported: Bool {
        pointerShapeHost(override: pointerShapeSupport, environment: ProcessInfo.processInfo.environment) != nil
    }

    /// The ladder behind ``pointerShapesSupported``, posed on its inputs: the
    /// host to speak to, or `nil` for none.
    package static func pointerShapeHost(override: Bool?, environment: [String: String]) -> PointerShapeHost? {
        let detected = PointerShapeHost.detect(environment: environment)
        let wanted: Bool? =
            switch override {
            case .some(let override): override
            case .none:
                switch environment["TUIKIT_POINTER_SHAPES"] {
                case "1", "all": true
                case "0": false
                default: nil
                }
            }
        switch wanted {
        case .some(true): return detected ?? .unnamed
        case .some(false): return nil
        case .none: return detected
        }
    }

    /// Whether TUIkit's own controls set the pointer's shape without being
    /// asked — the I-beam over a text field, a hand over a link or a button,
    /// a resize arrow over a divider — on `host`: where a person has seen its
    /// pointer put back as the app leaves (``PointerShapeHost/resetIsMeasured``,
    /// iTerm2 so far), or where `TUIKIT_POINTER_SHAPES=all` asks for them.
    package static func builtInPointerShapes(host: PointerShapeHost?, environment: [String: String]) -> Bool {
        guard let host else { return false }
        return environment["TUIKIT_POINTER_SHAPES"] == "all" || host.resetIsMeasured
    }
}
