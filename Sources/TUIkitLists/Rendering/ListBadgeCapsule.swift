//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListBadgeCapsule.swift
//
//  The capsule a list row's badge sits in: in the control family, for a
//  `.standard` or `.increased` badge, and none for a `.decreased` one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

/// What a list row's badge is drawn in round its text: the capsule macOS draws
/// a `.standard` and an `.increased` badge in, in the control family in force,
/// and nothing round a `.decreased` one, which macOS draws as plain text
/// (measured on 15.8; decisions B72; owner, B72-CAPSULE (c), 2026-10-23).
///
/// | control family | `.standard`, `.increased` | `.decreased` |
/// |---|---|---|
/// | filled (the default) | ` 12 `, a field of the control face's tint, a cell wider each side | `12` |
/// | lines | `(12)`, the cap set's caps (``ControlEnds``) in the lines' ink, no field | `12` |
/// | Braille | the shape's dotted ends, no field | `12` |
/// | blank | `12` | `12` |
///
/// The capsule's cells are the badge's: a list's measure, its badged line's
/// fit and its claims all read ``cells`` with the text's width, so they agree
/// about where the badge is.
struct ListBadgeCapsule {
    /// What is drawn round the text.
    enum Chrome {
        /// Nothing: the text alone.
        case plain
        /// A cell either side of the text, the whole on `field`; `nil` where
        /// the control face's tint cannot be measured (it is then the page),
        /// so the cells are blank.
        case field(Color?)
        /// The two caps, in `ink`, on no field.
        case caps(open: Character, close: Character, ink: Color)
    }

    let chrome: Chrome

    /// The cells the capsule adds to the text's: one each side, or none.
    var cells: Int {
        if case .plain = chrome { 0 } else { 2 }
    }

    /// The capsule a badge of `prominence` sits in, in `environment`.
    @MainActor
    init(prominence: BadgeProminence, environment: EnvironmentValues) {
        guard prominence != .decreased else {
            chrome = .plain
            return
        }
        let ends = ControlEnds(in: environment, size: .regular)
        let palette = environment.palette
        let surface = environment.enclosingSurface
        switch ends.kind {
        case .none:
            chrome = .plain
        case .filled, .face:
            // Spent over what the list is drawn on, so the field states no alpha
            // of its own over the row's fill.
            chrome = .field(
                palette.accentTintIsMeasurable ? palette.restingControlFace.spendingAlpha(over: surface) : nil)
        case .lines:
            chrome = .caps(
                open: ends.open, close: ends.close,
                ink: ControlEnds.lineInk(palette: palette, surface: surface, hovered: false, disabled: false))
        }
    }

    /// The cells a badge of `prominence` adds round its text in `environment`,
    /// without building its colours — what a list's measure asks of every
    /// badged row.
    @MainActor
    static func cells(prominence: BadgeProminence, environment: EnvironmentValues) -> Int {
        guard prominence != .decreased else { return 0 }
        return ControlEnds(in: environment, size: .regular).kind == .none ? 0 : 2
    }

    /// The badge's text ink: `ink`, floored against the field it sits on.
    func textInk(_ ink: Color) -> Color {
        guard case .field(let field?) = chrome else { return ink }
        return ink.ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: field)
    }

    /// `text` in its capsule, the text in `ink` (already ``textInk(_:)``),
    /// emboldened where `bold`. Opaque bytes: the text's alpha is claimed by
    /// the list, over the text's columns.
    func drawn(_ text: String, ink: Color, bold: Bool) -> String {
        switch chrome {
        case .plain:
            return ANSIRenderer.colorize(text, foreground: ink.opaqueSpelling, bold: bold)
        case .field(let field):
            return ANSIRenderer.colorize(
                " " + text + " ", foreground: ink.opaqueSpelling, background: field?.opaqueSpelling, bold: bold)
        case .caps(let open, let close, let lines):
            return ANSIRenderer.colorize(String(open), foreground: lines.opaqueSpelling)
                + ANSIRenderer.colorize(text, foreground: ink.opaqueSpelling, bold: bold)
                + ANSIRenderer.colorize(String(close), foreground: lines.opaqueSpelling)
        }
    }
}

/// A row's badge as the list draws it: its value, and the capsule round it.
struct DrawnBadge {
    let value: BadgeValue
    let capsule: ListBadgeCapsule

    /// The cells the badge takes, its capsule's included.
    var width: Int { value.displayText.strippedLength + capsule.cells }
}
