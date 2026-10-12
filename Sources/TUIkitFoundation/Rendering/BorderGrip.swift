//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BorderGrip.swift
//
//  The handle drawn on a box's border to say that edge can be dragged: its
//  glyphs, its size, its ink, and how it is stamped onto the border. Split out
//  of `_UserResizableCore.swift` so every edge that resizes draws the same
//  handle.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

/// A handle stamped onto a border cell run, in the tint vocabulary every
/// affordance uses: quiet at rest, brighter under the pointer, breathing while
/// focused.
///
/// A terminal cannot change the pointer's shape at an edge, so an edge that
/// can be grabbed has to say so in ink. The handle is purely that: the whole
/// edge takes the drag, and the mark says where.
@MainActor
package enum BorderGrip {
    /// How many cells of a horizontal border the handle occupies, and how many
    /// rows of a vertical one.
    ///
    /// Wide enough to read as a handle rather than as a blemish, and odd so it
    /// centres exactly. Shrunk to fit on a small box, down to the single cell a
    /// three-row box has between its corners — being told an edge can be
    /// dragged matters more on a small view than the border cell of separation
    /// that used to be reserved either side.
    package enum Size {
        package static let horizontal = 7
        static let vertical = 3
    }

    /// The glyphs a handle is drawn with — chosen to stand out from the border
    /// it sits on, which is the whole job of a mark.
    package struct Glyphs {
        package let horizontal: String
        let vertical: String
        let corner: String

        /// Doubled lines against a single-line or heavy border; heavy ones
        /// against a double-line border, where doubles would BE the border and
        /// the handle would say nothing at all. Both families are Box Drawing
        /// rather than pictographs, so every terminal in
        /// `Documentation/Terminals/Terminal compatibility survey.md` advances them by exactly
        /// the cells claimed.
        static let doubled = Self(horizontal: "═", vertical: "║", corner: "╝")
        static let heavy = Self(horizontal: "━", vertical: "┃", corner: "┛")

        /// The family that stands out from `border`, the glyph already in the
        /// cell.
        ///
        /// Read from the cell rather than from a ``BorderStyle``, because the
        /// border is drawn INSIDE the content and the handle is stamped on it
        /// from outside: there is no style to consult, only the result.
        /// U+2550…U+256C is the Box Drawing block's double-line run — the
        /// rounded corners (U+256D…U+2570) sit just past it, and the heavy
        /// glyphs well below, so both correctly ask for doubles.
        package static func standingOut(from border: Character?) -> Self {
            guard let border, ("\u{2550}"..."\u{256C}").contains(border) else { return .doubled }
            return .heavy
        }
    }

    /// Whether `cell` is a `.block` border's, which paints its cells rather
    /// than drawing lines on them (see `BorderStyle.paintsBackground`).
    ///
    /// A line-drawing glyph stamped onto one would punch a hole in a solid
    /// edge — the mark would read as damage rather than as an affordance — so
    /// such a border keeps its glyph and is marked by the TINT alone, which is
    /// the same three-step vocabulary either way.
    static func paintsItsCells(_ cell: Character?) -> Bool {
        cell.map { ("\u{2580}"..."\u{259F}").contains($0) } ?? false
    }

    /// What a handle is drawn in this frame.
    package struct Ink {
        /// The ink drawn now.
        let colour: Color
        /// The focused breath, whose run replays over the handle.
        let animated: AnimatedColor?
        /// The page's background, the field under every cell of the handle.
        let background: Color
    }

    /// The ink for a handle that is focused, hovered, or at rest.
    ///
    /// Focused is loudest, hovered next, resting quiet but present — the same
    /// three-step vocabulary every other affordance uses, and floored against
    /// the surface it sits on for the same reason. Focused, the handle
    /// breathes: a still highlight on a terminal reads as decoration, a
    /// breathing one reads as "this is where the keyboard is".
    package static func ink(isFocused: Bool, isHovered: Bool, environment: EnvironmentValues) -> Ink {
        let palette = environment.palette
        let resting = palette.border
        let background = palette.background
        let animated = AnimatedColor.activeSection(isFocused, in: environment)
        // The ink drawn now. Focused, it is the breath's current frame: the colour
        // the run replays over it on the next tick, opaque at both ends. It used to
        // be the raw accent, floored — so a faded tint reached the emitter, and the
        // grip jumped shade on the first replayed tick (§62).
        let colour =
            animated?.current
            ?? (isHovered ? palette.hoveredForeground(resting) : resting)
                .ensuringRenderedContrast(atLeast: 2.4, against: background)
        return Ink(colour: colour, animated: animated, background: background)
    }

    /// `size` cells of a border run `extent` long, centred between its two
    /// corners — the run is `1..<(extent - 1)` — or `nil` when there is no
    /// room for even one.
    package static func centredSpan(in extent: Int, size cap: Int) -> Range<Int>? {
        let run = extent - 2
        let size = min(cap, run)
        guard size >= 1 else { return nil }
        return (1 + (run - size) / 2)..<(1 + (run - size) / 2 + size)
    }

    /// Paints `text`, `cells` wide, over the border at `cell` — in `ink`, on
    /// the page's own background — and leaves the focused breath's run over
    /// it.
    ///
    /// Through `ClaimingRow`, so the bytes state the opaque spelling and the
    /// overlay carries the claim. `composited` punches the border's own claim
    /// from those cells and lifts this one in its place, so each is claimed
    /// once; and the claim holds for every frame of the run, since the breath's
    /// ink is opaque at both ends and the field is the page's in all of them.
    package static func mark(
        _ text: String, cells: Int, into buffer: inout FrameBuffer, at cell: (x: Int, y: Int), ink: Ink
    ) {
        var drawn = ClaimingRow()
        drawn.append(text, cells: cells, ink: ink.colour, field: ink.background)
        var overlay = FrameBuffer(lines: [drawn.text])
        overlay.opacityRegions = drawn.claims
        buffer = buffer.composited(with: overlay, at: cell)
        let background = ink.background
        if let run = ink.animated?.run(offsetX: cell.x, offsetY: cell.y, draw: { colour in
            var frame = ClaimingRow()
            frame.append(text, cells: cells, ink: colour, field: background)
            return frame.text
        }) {
            buffer.animatedCells.append(run)
        }
    }
}
