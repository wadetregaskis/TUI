//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonFaceEdges.swift
//
//  How a bordered button's face ends: the caps either side of its label, and
//  the ring round a three-row face — the one table ``ControlSize`` and
//  ``ButtonBorderShape`` are read into.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// How a bordered button's face ends: the cap either side of the label, and,
/// on a three-row face, the rows above and below it.
///
/// What they are drawn in follows the ``Appearance`` in force — the family —
/// and the ``ButtonBorderShape`` picks the member of it (``ButtonFaceFamily``).
/// A SOLID face (`.block`) is filled: one row's caps are drawn in the face's
/// colour, the accent's breath while the button holds the focus
/// (``ButtonCapCycle``), and three rows are the shape drawn in quadrants, the
/// whole of it breathing (``_ButtonStyleBody/breathingFace(focused:face:context:draw:)``).
/// A LINES face (any other appearance with a border) has no field: its caps
/// and box are lines, which breathe the focus with the label
/// (``_ButtonStyleBody/breathingOutline(focused:lines:label:context:draw:)``).
/// A face with no caps — a ``ControlSize/mini`` one, or any under `.blank` —
/// ends where its label does, and shows the focus by breathing the label.
struct ButtonFaceEdges: Equatable, Sendable {
    /// The cap before the label and the cap after it; `nil` for none.
    let caps: (open: Character, close: Character)?
    /// The rows above and below a three-row face; `nil` for a one-row face.
    let ring: Ring?
    /// Whether the face is drawn in lines alone, with no field under the
    /// label. Its caps and box are drawn in the lines' ink on the surface,
    /// and the lines and the label breathe the focus together.
    var isOutline = false
    /// Whether an outline face with no caps draws a line under its label
    /// instead (``ButtonBorderShape/underline``): in the lines' ink, under the
    /// label's own cells and not its padding.
    var underlinesLabel = false
    /// Whether a solid face's caps are cells of the face itself rather than
    /// glyphs in its colour: a one-row rectangle's square ends, and the label's
    /// row of every three-row solid face, whose shape is full there. Such a
    /// face is drawn whole in one colour and breathes whole.
    var capsAreFace = false

    /// The rows above and below a three-row face.
    enum Ring: Equatable, Sendable {
        /// A solid face: `shape` drawn in quadrants, three rows tall — or, in
        /// `wholeCells`, in whole cells of the face, for a terminal that draws
        /// Block Elements short of the line (``EnvironmentValues/blockElementsFillTheLine``).
        case solid(TallShape, wholeCells: Bool)
        /// A box of lines round an outline face: the glyphs of its row above
        /// and its row below.
        case box(top: BoxRow, bottom: BoxRow)
        /// A dotted outline of `shape`, `thickness` Braille dots thick, round
        /// an outline face: its rows above and below drawn from the shape at
        /// the face's width.
        case dots(TallShape, thickness: Int)
    }

    /// The shape a three-row solid face is drawn in.
    enum TallShape: Equatable, Sendable {
        /// Ends rounded right through: half the face's height in radius.
        case capsule
        /// Corners rounded by a quadrant (`radius` 1.5 cells) or not at all (0).
        case rectangle(radius: Double)
        /// A disc, as wide as the face is tall.
        case circle
    }

    /// One row of a box: its leading corner, its edge, its trailing corner.
    struct BoxRow: Equatable, Sendable {
        let leading: Character
        let edge: Character
        let trailing: Character
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.caps?.open == rhs.caps?.open && lhs.caps?.close == rhs.caps?.close && lhs.ring == rhs.ring
            && lhs.isOutline == rhs.isOutline && lhs.capsAreFace == rhs.capsAreFace
            && lhs.underlinesLabel == rhs.underlinesLabel
    }

    /// The cells the caps take, both together.
    var capsWidth: Int { caps == nil ? 0 : 2 }

    /// The rows the face takes.
    var rows: Int { ring == nil ? 1 : 3 }

    /// The half-block caps, `▐ … ▌`, which round a solid face's ends: a
    /// capsule's, and every bordered button TUIkit drew until the families.
    static let capsule = Self(caps: (TerminalSymbols.openCap, TerminalSymbols.closeCap), ring: nil)

    /// Square ends of the face itself: a solid rectangle one row tall.
    static let solidRectangle = Self(caps: (" ", " "), ring: nil, capsAreFace: true)

    /// No caps: the face ends where its label does.
    static let none = Self(caps: nil, ring: nil)

    /// No caps and no field: a label alone, which breathes the focus.
    static let bareOutline = Self(caps: nil, ring: nil, isOutline: true)

    /// No caps and no field, and a line under the label in the lines' ink.
    static let underlined = Self(caps: nil, ring: nil, isOutline: true, underlinesLabel: true)

    /// A solid face three rows tall, in `shape`.
    static func solid(_ shape: TallShape, wholeCells: Bool) -> Self {
        Self(caps: (" ", " "), ring: .solid(shape, wholeCells: wholeCells), capsAreFace: true)
    }

    /// An outline face between `caps`, one row tall, or three in a box of
    /// `style`'s lines.
    static func lines(_ caps: (Character, Character), box style: BorderStyle?) -> Self {
        Self(
            caps: caps,
            ring: style.map {
                .box(
                    top: BoxRow(leading: $0.topLeft, edge: $0.horizontal, trailing: $0.topRight),
                    bottom: BoxRow(leading: $0.bottomLeft, edge: $0.horizontal, trailing: $0.bottomRight))
            },
            isOutline: true)
    }
}

/// The family a bordered button's face is drawn in: what the ``Appearance``
/// in force says of every control's chrome.
enum ButtonFaceFamily: Equatable, Sendable {
    /// Filled faces: `.block`, whose border paints its own background.
    case solid
    /// Faces of lines in this border style's glyphs: `.rounded` (the
    /// default), `.line`, `.heavy`, `.doubleLine`, and any appearance of an
    /// app's own with a border of lines.
    case lines(BorderStyle)
    /// No chrome at all: `.blank`.
    case blank
    /// Dotted outlines of the shape, `thickness` Braille dots thick:
    /// `.braille` and `.braille(thickness:)`.
    case braille(thickness: Int)

    /// The family controls are drawn in under `appearance` and `control`: the
    /// control style where it names one, and under ``ControlStyle/automatic``
    /// filled faces, unless the appearance's border is Braille dots or blank,
    /// whose controls follow it.
    init(_ appearance: Appearance, _ control: ControlStyle) {
        let style = appearance.borderStyle
        switch control {
        case .block:
            self = .solid
        case .lines:
            let drawsLines = style.brailleThickness == nil && style != .none && !style.paintsBackground
            self = .lines(drawsLines ? style : .rounded)
        case .braille(let thickness):
            self = .braille(thickness: min(max(thickness, 1), 4))
        case .blank:
            self = .blank
        case .automatic:
            if let thickness = style.brailleThickness {
                self = .braille(thickness: thickness)
            } else if style == .none {
                self = .blank
            } else {
                self = .solid
            }
        }
    }

    /// The family controls are drawn in where `environment` says.
    ///
    /// Under ``ControlStyle/automatic`` two looks that exist only apart from a
    /// filled face keep theirs, where the default would otherwise fill them:
    /// a glass button takes its glass's rim family, as plain glass does — a
    /// filled face would cover the glass it is made of — and a
    /// ``ButtonBorderShape/brackets(_:_:)`` or ``ButtonBorderShape/underline``
    /// face is drawn in lines, which is all those shapes are. A control style
    /// named outright is drawn as named.
    init(_ environment: EnvironmentValues) {
        let appearance = environment.appearance
        let control = environment.controlStyle
        if control != .automatic {
            self = Self(appearance, control)
        } else if environment.glassIsAControl {
            self = Self(rimOf: appearance)
        } else {
            let family = Self(appearance, .automatic)
            self = family == .solid && environment.buttonBorderShape.isDrawnInLinesOnly
                ? Self(appearance, .lines) : family
        }
    }

    /// The family a surface's rim takes from the border of `appearance`, as a
    /// box does: lines under a border of lines, filled under `.block`, dots
    /// under `.braille`, nothing under `.blank` — whatever the controls are
    /// drawn in.
    init(rimOf appearance: Appearance) {
        let style = appearance.borderStyle
        if let thickness = style.brailleThickness {
            self = .braille(thickness: thickness)
        } else if style == .none {
            self = .blank
        } else if style.paintsBackground {
            self = .solid
        } else {
            self = .lines(style)
        }
    }
}

extension Appearance {
    /// The border style whose lines controls' chrome is drawn in under
    /// `control` — ``ControlStyle/lines`` — or `nil` where controls are
    /// solid, blank or Braille: what a text field reads to draw line caps on
    /// its surface rather than half-blocks (``ButtonFaceFamily/lines(_:)``).
    package func controlLines(under control: ControlStyle) -> BorderStyle? {
        if case .lines(let style) = ButtonFaceFamily(self, control) { style } else { nil }
    }
}

extension _ButtonAppearance {
    /// This appearance at `size`, in `shape`, in `family`: the density table
    /// of ``ControlSize``, the members of each family for each
    /// ``ButtonBorderShape``. A plain appearance has no face, and is returned
    /// as it is.
    ///
    /// | size          | rows | caps | padding |
    /// |---------------|------|------|---------|
    /// | `.mini`       | 1    | none | 0       |
    /// | `.small`      | 1    | yes  | 0       |
    /// | `.regular`    | 1    | yes  | the style's |
    /// | `.large`      | 3    | yes, and the rows above and below | the style's |
    /// | `.extraLarge` | 3    | yes, and the rows above and below | the style's + 1 |
    ///
    /// | shape | lines | solid |
    /// |---|---|---|
    /// | capsule | `( OK )`; three rows `╭────╮` / `( OK )` / `╰────╯` | `▐ OK ▌`; three rows a capsule in quadrants |
    /// | rounded rectangle | `│ OK │`; the box `╭────╮` / `│ OK │` / `╰────╯` | square-ended face; quadrant-cornered on three |
    /// | radius zero | `[ OK ]`; a square-cornered box | a square face |
    /// | ``ButtonBorderShape/brackets(_:_:)`` | between its glyphs; the rectangle's box | as the rounded rectangle |
    /// | ``ButtonBorderShape/underline`` | `OK` over a line, the label's width, at `.mini` too; the rectangle's box | as the rounded rectangle |
    /// | circle | `(★)`; the capsule's box, as wide as tall | `▐★▌`; a disc in quadrants |
    ///
    /// A braille face (`.braille`) is a dotted outline of the shape, drawn at
    /// dot resolution (``_ButtonStyleBody/dotRows(_:width:rows:thickness:)``):
    /// on one row its ends, on three the whole outline.
    ///
    /// A lines face draws its box in the appearance's own border glyphs —
    /// rounded corners under `.rounded`, square ones under `.line`, heavy and
    /// double lines under `.heavy` and `.doubleLine`. A circle has no padding
    /// on one row, and enough on three to be about as wide as it is tall.
    /// Where the terminal draws Block Elements short of the line (Apple
    /// Terminal), a solid three-row face is drawn in whole cells.
    ///
    /// A `segment` of a face drawn round several controls
    /// (``EnvironmentValues/isControlSegment``, a ``ControlGroup``'s) has no
    /// caps and one row at any size, as a segmented picker's segment: the
    /// face's ends are drawn round the group.
    func sized(
        _ size: ControlSize, shape: ButtonBorderShape, family: ButtonFaceFamily, blockElementsFillTheLine: Bool,
        segment: Bool = false
    ) -> Self {
        guard !isPlain else { return self }
        var sized = self
        let tall = size >= .large && !segment
        sized.horizontalPadding = size.padding(regular: horizontalPadding)
        let caps = size.drawsEndCaps && !segment
        switch family {
        case .blank:
            sized.edges = .bareOutline
        case .solid:
            sized.edges = caps ? Self.solidEdges(shape, tall: tall, wholeCells: !blockElementsFillTheLine) : .none
            if shape.kind == .circle { sized.horizontalPadding = tall ? 2 : 0 }
        case .lines(let style):
            // An underline is drawn without caps at every size, and costs no cell
            // of its own, so `.mini` keeps it (owner, 2026-10-24); a segment's
            // label is the group's, and stays bare.
            let underlined = shape.kind == .underline && !segment
            sized.edges =
                caps ? Self.lineEdges(shape, tall: tall, style: style) : underlined ? .underlined : .bareOutline
            if shape.kind == .circle { sized.horizontalPadding = tall ? 1 : 0 }
        case .braille(let thickness):
            sized.edges = caps ? Self.dotEdges(shape, tall: tall, thickness: thickness) : .bareOutline
            if shape.kind == .circle { sized.horizontalPadding = tall ? 2 : 0 }
        }
        return sized
    }

    /// A dotted outline face in `shape`, `thickness` dots thick: its caps the
    /// ends of the shape's label row, which are the same whatever the face's
    /// width, and on three rows the shape's rows above and below.
    private static func dotEdges(_ shape: ButtonBorderShape, tall: Bool, thickness: Int) -> ButtonFaceEdges {
        let outline: ButtonFaceEdges.TallShape
        switch shape.kind {
        case .automatic, .capsule: outline = .capsule
        case .circle: outline = tall ? .circle : .capsule
        case .roundedRectangle, .brackets, .underline: outline = .rectangle(radius: tall ? 1.5 : 0)
        case .square: outline = .rectangle(radius: 0)
        }
        let rows = tall ? 3 : 1
        // Wide enough that the label row's ends are the shape's own, not a
        // narrow face's: the caps are its first and last cells.
        let labelRow = _ButtonStyleBody.dotRows(outline, width: 12, rows: rows, thickness: thickness)[rows / 2]
        return ButtonFaceEdges(
            caps: (labelRow.first ?? " ", labelRow.last ?? " "),
            ring: tall ? .dots(outline, thickness: thickness) : nil, isOutline: true)
    }

    /// A solid face in `shape`.
    private static func solidEdges(_ shape: ButtonBorderShape, tall: Bool, wholeCells: Bool) -> ButtonFaceEdges {
        switch shape.kind {
        case .automatic, .capsule:
            return tall ? .solid(.capsule, wholeCells: wholeCells) : .capsule
        case .circle:
            return tall ? .solid(.circle, wholeCells: wholeCells) : .capsule
        case .roundedRectangle, .brackets, .underline:
            return tall ? .solid(.rectangle(radius: 1.5), wholeCells: wholeCells) : .solidRectangle
        case .square:
            return tall ? .solid(.rectangle(radius: 0), wholeCells: wholeCells) : .solidRectangle
        }
    }

    /// A lines face in `shape`, its box in `style`'s glyphs.
    private static func lineEdges(_ shape: ButtonBorderShape, tall: Bool, style: BorderStyle) -> ButtonFaceEdges {
        // A square shape takes square corners whatever the border's are.
        let squareStyle = style == .rounded ? BorderStyle.line : style
        let sides = (style.vertical, style.rightVertical)
        switch shape.kind {
        case .automatic, .capsule, .circle:
            return .lines(("(", ")"), box: tall ? style : nil)
        case .roundedRectangle:
            return .lines(sides, box: tall ? style : nil)
        case .square:
            return tall ? .lines(sides, box: squareStyle) : .lines(("[", "]"), box: nil)
        case .brackets(let open, let close):
            guard !tall else { return .lines(sides, box: style) }
            let fits = String(open).strippedLength == 1 && String(close).strippedLength == 1
            return .lines(fits ? (open, close) : sides, box: nil)
        case .underline:
            return tall ? .lines(sides, box: style) : .underlined
        }
    }
}

// MARK: - The terminal's block elements

/// Whether the terminal draws Block Elements glyphs the full height of the
/// line; `true` where nothing has said otherwise (headless, tests).
private struct BlockElementsFillTheLineKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the terminal draws a Block Elements glyph (U+2580–259F) the
    /// full height of its line, so that a half block meets the row above or
    /// below it. Set by the run loop from `TerminalHost`, per tmux client
    /// where there are any; read by a three-row button face, which is built
    /// of half blocks and quadrants and comes apart where they fall short.
    package var blockElementsFillTheLine: Bool {
        get { self[BlockElementsFillTheLineKey.self] }
        set { self[BlockElementsFillTheLineKey.self] = newValue }
    }
}

// MARK: - Drawing the edges

extension _ButtonStyleBody {
    /// The SGR introducer a one-row face's caps are drawn in now.
    static func capSequence(_ caps: ButtonCapCycle) -> String? {
        var capStyle = TextStyle()
        capStyle.foregroundColor = caps.colorNow
        return ANSIRenderer.styleSequence(for: capStyle)
    }

    /// One cell of a solid face: nothing, a glyph in the face's colour, or a
    /// cell of the face itself.
    enum FaceCell: Equatable, Sendable {
        case empty
        case glyph(Character)
        case face
    }

    /// A solid three-row face `width` cells wide in `shape`, a row of cells
    /// at a time: the shape sampled at each quadrant — a quadrant is half a
    /// cell across and a whole cell's width down, a row being two cells'
    /// widths tall — or, in `wholeCells`, at each cell's middle.
    static func solidRows(_ shape: ButtonFaceEdges.TallShape, width: Int, wholeCells: Bool) -> [[FaceCell]] {
        let (w, h) = (Double(width), 6.0)
        func inside(_ x: Double, _ y: Double) -> Bool { contains(shape, width: w, height: h, x: x, y: y) }
        return (0..<3).map { row in
            (0..<width).map { column in
                let (x, y) = (Double(column), Double(row) * 2)
                var bits = 0
                if inside(x + 0.25, y + 0.5) { bits |= 1 }
                if inside(x + 0.75, y + 0.5) { bits |= 2 }
                if inside(x + 0.25, y + 1.5) { bits |= 4 }
                if inside(x + 0.75, y + 1.5) { bits |= 8 }
                // In whole cells a cell is the face only where the shape covers
                // all four of its quarters. A cell the curve only nicks is left
                // out, so a rounded rectangle loses its corner cells and a capsule
                // two at each end, where testing the cell's centre filled every
                // corner and drew all three shapes as the same square block
                // (owner #20, 2026-10-23).
                if wholeCells { return bits == 15 ? .face : .empty }
                return bits == 15 ? .face : bits == 0 ? .empty : .glyph(TerminalSymbols.quadrants[bits])
            }
        }
    }

    /// Whether the point (`x`, `y`) is inside `shape` drawn `width` by
    /// `height`, in a cell's widths — a row being two of them tall.
    nonisolated static func contains(
        _ shape: ButtonFaceEdges.TallShape, width w: Double, height h: Double, x: Double, y: Double
    ) -> Bool {
        guard x >= 0, y >= 0, x <= w, y <= h else { return false }
        switch shape {
        case .capsule:
            let r = min(h, w) / 2
            let cx = min(max(x, r), w - r)
            let cy = min(max(y, r), h - r)
            return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r
        case .rectangle(let radius):
            let r = min(radius, h / 2, w / 2)
            guard r > 0 else { return true }
            let cx = min(max(x, r), w - r)
            let cy = min(max(y, r), h - r)
            return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r
        case .circle:
            let (dx, dy) = ((x - w / 2) / (w / 2), (y - h / 2) / (h / 2))
            return dx * dx + dy * dy <= 1
        }
    }

    /// A dotted outline of `shape` `width` cells wide and `rows` tall, a row
    /// of cells at a time: each cell's Braille glyph, blank where it has no
    /// dots. A dot — half a cell's width each way, so square — is on the
    /// outline when it is inside the shape and within `thickness` dots of
    /// the outside.
    nonisolated static func dotRows(_ shape: ButtonFaceEdges.TallShape, width: Int, rows: Int, thickness: Int) -> [[Character]] {
        let (w, h) = (Double(width), Double(rows) * 2)
        let (columns, lines) = (width * 2, rows * 4)
        func inside(_ dx: Int, _ dy: Int) -> Bool {
            dx >= 0 && dy >= 0 && dx < columns && dy < lines
                && contains(shape, width: w, height: h, x: (Double(dx) + 0.5) / 2, y: (Double(dy) + 0.5) / 2)
        }
        func onOutline(_ dx: Int, _ dy: Int) -> Bool {
            inside(dx, dy)
                && (1...max(1, thickness)).contains { step in
                    !inside(dx - step, dy) || !inside(dx + step, dy) || !inside(dx, dy - step) || !inside(dx, dy + step)
                }
        }
        // Each dot's bit, by row and column of the cell (Unicode's Braille numbering).
        let bits: [[UInt32]] = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]]
        return (0..<rows).map { row in
            (0..<width).map { column in
                var mask: UInt32 = 0
                for dy in 0..<4 {
                    for dx in 0..<2 where onOutline(column * 2 + dx, row * 4 + dy) { mask |= bits[dy][dx] }
                }
                return mask == 0 ? " " : Unicode.Scalar(0x2800 + mask).map(Character.init) ?? " "
            }
        }
    }

    /// `cells` drawn in `face`: glyphs in its colour, its own cells as its
    /// background, a run of them in one introducer.
    static func drawn(_ cells: some Collection<FaceCell>, face: Color) -> String {
        var line = ""
        var faceRun = 0
        func flush() {
            if faceRun > 0 { line += ANSIRenderer.colorize(String.spaces(faceRun), background: face) }
            faceRun = 0
        }
        for cell in cells {
            switch cell {
            case .face: faceRun += 1
            case .empty: flush(); line += " "
            case .glyph(let glyph): flush(); line += ANSIRenderer.colorize(String(glyph), foreground: face)
            }
        }
        flush()
        return line
    }

    /// A solid three-row face round `middle`, its label's row drawn in
    /// `face` between ``solidRows(_:width:wholeCells:)``'s middle row's ends:
    /// that shape's rows above and below it.
    static func solidFace(
        around middle: FrameBuffer, shape: ButtonFaceEdges.TallShape, wholeCells: Bool, face: Color
    ) -> FrameBuffer {
        let rows = solidRows(shape, width: middle.width, wholeCells: wholeCells)
        var buffer = FrameBuffer(lines: [drawn(rows[0], face: face)])
        buffer.appendVertically(middle)
        buffer.appendVertically(FrameBuffer(lines: [drawn(rows[2], face: face)]))
        return buffer
    }

    /// A face drawn whole in one colour — `draw(face)` — breathing from
    /// `face` to the accent while it holds the focus (``FaceBreath``): drawn
    /// once per colour of the breath, each row of it handed to the run loop as
    /// a run, as ``BreathingLabel`` hands over a label.
    @MainActor
    static func breathingFace(_ breath: FaceBreath, context: RenderContext, draw: (Color) -> FrameBuffer) -> FrameBuffer {
        var buffer = draw(breath.now)
        guard !context.isMeasuring, breath.animates else { return buffer }
        return handingOver(&buffer, frames: breath.ramp.map { draw($0).lines }, cycle: breath.cycle)
    }

    /// `buffer` with each of its rows handed to the run loop as a run of
    /// `frames`' rows, the drawing at each step of `cycle`.
    static func handingOver(_ buffer: inout FrameBuffer, frames: [[String]], cycle: SelectionEmphasisCycle) -> FrameBuffer {
        buffer.animatedCells += buffer.lines.indices.compactMap { row in
            let rowFrames = frames.compactMap { row < $0.count ? $0[row] : nil }
            guard rowFrames.count == frames.count, let first = rowFrames.first else { return nil }
            return AnimatedCellRun(
                offsetX: 0, offsetY: row, width: first.strippedLength,
                frames: rowFrames, frameTicks: cycle.frameTicks, clock: cycle.clock)
        }
        return buffer
    }

    /// An outline face drawn whole — `draw(lines, label)` — its lines and its
    /// label breathing together to the accent while it holds the focus
    /// (``OutlineBreath``); drawn once per step of the breath and handed to the
    /// run loop a row at a time, as ``breathingFace(_:context:draw:)`` is.
    @MainActor
    static func breathingOutline(
        _ breath: OutlineBreath, context: RenderContext, draw: (Color, Color) -> FrameBuffer
    ) -> FrameBuffer {
        var buffer = draw(breath.now.lines, breath.now.label)
        guard !context.isMeasuring, breath.animates else { return buffer }
        return handingOver(&buffer, frames: zip(breath.lines, breath.labels).map { draw($0, $1).lines }, cycle: breath.cycle)
    }

    /// The ink an outline face's lines rest in: the border's, held visible on
    /// the surface at the colours the terminal can show
    /// (``ViewConstants/buttonOutlineContrastFloor``); lifted under the
    /// pointer — ``Palette/hoveredForeground(_:)``, the
    /// lift a plain button's label takes, so the hover shows on every palette —
    /// and faded with the label while disabled.
    static func outlineInk(palette: any Palette, surface: Color, hovered: Bool, disabled: Bool) -> Color {
        if disabled {
            return palette.foregroundTertiary
                .opacity(ViewConstants.disabledForeground, over: palette.background)
                .spendingAlpha(over: surface)
        }
        let resting = palette.border.resolve(with: palette).spendingAlpha(over: surface)
            .ensuringRenderedContrast(atLeast: ViewConstants.buttonOutlineContrastFloor, against: surface)
        return hovered ? palette.hoveredForeground(resting) : resting
    }

    /// A row of a box round an outline face `width` cells wide, its caps
    /// included, in `lines`.
    static func outlineBox(_ row: ButtonFaceEdges.BoxRow, width: Int, lines: Color) -> String {
        guard width >= 2 else { return String.spaces(max(0, width)) }
        return ANSIRenderer.colorize(
            String(row.leading) + String(repeating: row.edge, count: width - 2) + String(row.trailing),
            foreground: lines)
    }

    /// An outline face round `middle`, its label's row: the box's rows above
    /// and below it where the edges have one, and `middle` as it is where
    /// they have none.
    static func outline(around middle: FrameBuffer, edges: ButtonFaceEdges, lines: Color) -> FrameBuffer {
        let rows: (top: String, bottom: String)
        switch edges.ring {
        case .box(let top, let bottom):
            rows = (outlineBox(top, width: middle.width, lines: lines), outlineBox(bottom, width: middle.width, lines: lines))
        case .dots(let shape, let thickness):
            let dots = dotRows(shape, width: middle.width, rows: 3, thickness: thickness)
            rows = (
                ANSIRenderer.colorize(String(dots[0]), foreground: lines),
                ANSIRenderer.colorize(String(dots[2]), foreground: lines)
            )
        case .solid, nil:
            return middle
        }
        var buffer = FrameBuffer(lines: [rows.top])
        buffer.appendVertically(middle)
        buffer.appendVertically(FrameBuffer(lines: [rows.bottom]))
        return buffer
    }

    /// A face with no caps — a `.mini` button — around a string label: the label
    /// on the face, breathing while the button holds the focus, as a link's
    /// does, since there are no caps to breathe.
    @MainActor
    static func capless(
        _ label: String, label ink: Color, face: Color, bold: Bool, context: RenderContext, focused: Bool
    ) -> FrameBuffer {
        var style = TextStyle()
        style.foregroundColor = ink.opaqueSpelling
        style.backgroundColor = face.opaqueSpelling
        style.isBold = bold
        var buffer = BreathingLabel.draw(
            label, style: style, ends: BorderRenderer.breathEnds(from: ink, on: face),
            cycle: context.environment.selectionEmphasis.cycle(focused), indicating: focused,
            isMeasuring: context.isMeasuring)
        if let claim = OpacityRegion.claim(
            offsetX: 0, width: label.strippedLength, height: 1, ink: ink, field: face)
        {
            buffer.opacityRegions.append(claim)
        }
        return buffer
    }
}

// MARK: - The breaths

/// The breath of a solid face drawn whole: from the face to the accent while
/// the button holds the focus, and the face at rest. Worked out once, so that
/// the drawing and the measure's probe of it ask of the same view.
struct FaceBreath {
    let cycle: SelectionEmphasisCycle
    /// One colour per step of the breath; empty at rest.
    let ramp: [Color]
    /// The colour the face is drawn in now.
    let now: Color

    /// Whether the run loop has a breath to replay.
    var animates: Bool { ramp.count > 1 && cycle.isAnimating }

    /// The breath of `face` while `focused`. A face or accent the terminal
    /// decides (no RGB) holds the accent instead of breathing.
    @MainActor
    init(focused: Bool, face: Color, context: RenderContext) {
        let palette = context.environment.palette
        cycle = context.environment.selectionEmphasis.cycle(focused)
        let accent = palette.accent.spendingAlpha(over: face)
        let measurable =
            face.resolve(with: palette).rgbComponents != nil
            && palette.accent.resolve(with: palette).rgbComponents != nil
        ramp = !focused ? [] : measurable ? cycle.colors(dim: face, bright: accent) : [accent]
        now = ramp.isEmpty ? face : ramp[cycle.step % ramp.count]
    }
}

/// The breath of an outline face: its lines and its label, each from its
/// own resting colour to the accent, while the button holds the focus.
/// Worked out once, so that the drawing and the measure's probe of it ask of
/// the same view.
struct OutlineBreath {
    let cycle: SelectionEmphasisCycle
    /// The lines' colour at each step of the breath; empty when still.
    let lines: [Color]
    /// The label's colour at each step of the breath; empty when still.
    let labels: [Color]
    /// The lines' colour and the label's now.
    let now: (lines: Color, label: Color)

    /// Whether the run loop has a breath to replay.
    var animates: Bool { lines.count > 1 && labels.count == lines.count && cycle.isAnimating }

    /// The breath of `lines` and `label` while `focused`.
    ///
    /// - A label colour the app stated (`labelBreathes` false) is drawn as
    ///   stated: only the lines breathe.
    /// - Under the pointer the bright end lifts too, as every colour in force
    ///   does (``Palette/hoveredForeground(_:)``), so a hovered button that
    ///   holds the focus still shows the hover.
    /// - An accent, lines or surface the terminal decides (no RGB) leave
    ///   nothing to breathe between: the focused outline holds the bright end,
    ///   still — no run, and no clock read — as a face's caps hold the accent
    ///   (``ButtonCapCycle``).
    @MainActor
    init(
        focused: Bool, hovered: Bool, lines resting: Color, label: Color, labelBreathes: Bool,
        context: RenderContext
    ) {
        let palette = context.environment.palette
        let surface = context.environment.enclosingSurface
        cycle = context.environment.selectionEmphasis.cycle(focused)
        let spent = palette.accent.spendingAlpha(over: surface)
        let accent = hovered ? palette.hoveredForeground(spent) : spent
        let bright = labelBreathes ? accent : label
        let measurable =
            palette.accent.resolve(with: palette).rgbComponents != nil
            && resting.resolve(with: palette).rgbComponents != nil
            && surface.resolve(with: palette).rgbComponents != nil
        guard focused, measurable,
            cycle.isAnimating(dim: resting, bright: accent) || labelBreathes && cycle.isAnimating(dim: label, bright: accent)
        else {
            lines = []
            labels = []
            now = focused ? (accent, bright) : (resting, label)
            return
        }
        lines = cycle.colors(dim: resting, bright: accent)
        labels = labelBreathes ? cycle.colors(dim: label, bright: accent) : Array(repeating: label, count: lines.count)
        let step = cycle.step % lines.count
        now = (lines[step], labels[step % labels.count])
    }
}
