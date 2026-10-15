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
/// A one-row face's caps are drawn in the caps' colour — the face's own at
/// rest, so they round or square it off, and the accent's breath while the
/// button holds the focus (``ButtonCapCycle``). A three-row face is drawn
/// whole in one colour, caps and rows and the label's field together, and
/// the whole of it breathes to the accent while the button holds the focus
/// (``_ButtonStyleBody/breathingFace(focused:face:context:draw:)``). A face with no caps
/// (a ``ControlSize/mini`` one) ends where its label does, and shows the
/// focus by breathing the label instead.
struct ButtonFaceEdges: Equatable, Sendable {
    /// The cap before the label and the cap after it; `nil` for none.
    let caps: (open: Character, close: Character)?
    /// The rows above and below a three-row face; `nil` for a one-row face.
    let ring: Ring?

    /// The rows above and below a three-row face, and how its caps are drawn.
    enum Ring: Equatable, Sendable {
        /// Half blocks above and below the label's row, met by quadrant
        /// corners — `▗▄▄▖` / `▐ … ▌` / `▝▀▀▘` — so the face is a capsule a
        /// row and a half tall: `.large`.
        case halfBlocks
        /// Two rows of the face itself above and below the label's row,
        /// their corners quadrants — `▗  ▖` / `▐ … ▌` / `▝  ▘` — so the face
        /// is a capsule three rows tall: `.extraLarge`.
        case faceRows
        /// Three rows of the face itself and no Block Elements glyph at all,
        /// the caps included: what a terminal that draws those glyphs short
        /// of the line gets for either (``EnvironmentValues/blockElementsFillTheLine``).
        case plainRows
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.caps?.open == rhs.caps?.open && lhs.caps?.close == rhs.caps?.close && lhs.ring == rhs.ring
    }

    /// The cells the caps take, both together.
    var capsWidth: Int { caps == nil ? 0 : 2 }

    /// The rows the face takes.
    var rows: Int { ring == nil ? 1 : 3 }

    /// The half-block caps, `▐ … ▌`, which round the face's ends: a capsule,
    /// and every bordered button TUIkit has drawn.
    static let capsule = Self(caps: (TerminalSymbols.openCap, TerminalSymbols.closeCap), ring: nil)

    /// The one-eighth edges, `▕ … ▏`, which square the face's ends: a
    /// rounded rectangle.
    static let roundedRectangle = Self(caps: ("\u{2595}", "\u{258F}"), ring: nil)

    /// No caps: the face ends where its label does.
    static let none = Self(caps: nil, ring: nil)

    /// A face three rows tall, its label's row between the half-block caps.
    static func tall(_ ring: Ring) -> Self {
        Self(caps: (TerminalSymbols.openCap, TerminalSymbols.closeCap), ring: ring)
    }
}

extension _ButtonAppearance {
    /// This appearance at `size`, in `shape`: the density table of
    /// ``ControlSize`` and ``ButtonBorderShape``. A plain appearance has no
    /// face, and is returned as it is.
    ///
    /// | size          | rows | caps | padding |
    /// |---------------|------|------|---------|
    /// | `.mini`       | 1    | none | 0       |
    /// | `.small`      | 1    | yes  | 0       |
    /// | `.regular`    | 1    | yes  | the style's |
    /// | `.large`      | 3    | half-block ring | the style's |
    /// | `.extraLarge` | 3    | rows of the face (a capsule's) | the style's + 1 |
    ///
    /// A `.circle` has no padding at any size. Where the terminal draws Block
    /// Elements short of the line (Apple Terminal), a three-row face is three
    /// plain rows of the face (``ButtonFaceEdges/Ring/plainRows``).
    func sized(_ size: ControlSize, shape: ButtonBorderShape, blockElementsFillTheLine: Bool) -> Self {
        guard !isPlain else { return self }
        var sized = self
        let square = shape.kind == .roundedRectangle
        func tall(_ ring: ButtonFaceEdges.Ring) -> ButtonFaceEdges {
            .tall(blockElementsFillTheLine ? ring : .plainRows)
        }
        switch size {
        case .mini:
            sized.horizontalPadding = 0
            sized.edges = .none
        case .small:
            sized.horizontalPadding = 0
            sized.edges = square ? .roundedRectangle : .capsule
        case .regular:
            sized.edges = square ? .roundedRectangle : .capsule
        case .large:
            sized.edges = tall(.halfBlocks)
        case .extraLarge:
            sized.horizontalPadding += 1
            sized.edges = tall(square ? .halfBlocks : .faceRows)
        }
        if shape.kind == .circle { sized.horizontalPadding = 0 }
        return sized
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

    /// The row above a three-row face (`top`) or below it, `width` cells
    /// wide with its caps, in `face`.
    static func tallFace(top: Bool, width: Int, ring: ButtonFaceEdges.Ring, face: Color) -> String {
        let inner = String(repeating: " ", count: max(0, width - 2))
        let corners: (String, String) = top ? ("\u{2597}", "\u{2596}") : ("\u{259D}", "\u{2598}")
        guard width >= 2, ring != .plainRows else {
            return ANSIRenderer.colorize(String(repeating: " ", count: max(0, width)), background: face)
        }
        if ring == .halfBlocks {
            let edge = String(repeating: top ? "\u{2584}" : "\u{2580}", count: width - 2)
            return ANSIRenderer.colorize(corners.0 + edge + corners.1, foreground: face)
        }
        return ANSIRenderer.colorize(corners.0, foreground: face)
            + ANSIRenderer.colorize(inner, background: face)
            + ANSIRenderer.colorize(corners.1, foreground: face)
    }

    /// A three-row face around `middle`, its label's row drawn in `face`
    /// with its caps: the rows of `ring` above and below it.
    static func tallFace(around middle: FrameBuffer, ring: ButtonFaceEdges.Ring, face: Color) -> FrameBuffer {
        let width = middle.width
        var buffer = FrameBuffer(lines: [tallFace(top: true, width: width, ring: ring, face: face)])
        buffer.appendVertically(middle)
        buffer.appendVertically(FrameBuffer(lines: [tallFace(top: false, width: width, ring: ring, face: face)]))
        return buffer
    }

    /// A face drawn whole in one colour — `draw(face)` — breathing from
    /// `face` to the accent while `focused`: drawn once per colour of the
    /// breath, each row of it handed to the run loop as a run, as
    /// ``BreathingLabel`` hands over a label. A face or accent the terminal
    /// decides (no RGB) holds the accent instead of breathing.
    @MainActor
    static func breathingFace(
        focused: Bool, face: Color, context: RenderContext, draw: (Color) -> FrameBuffer
    ) -> FrameBuffer {
        let palette = context.environment.palette
        let cycle = context.environment.selectionEmphasis.cycle(focused)
        let accent = palette.accent.spendingAlpha(over: face)
        let measurable =
            face.resolve(with: palette).rgbComponents != nil
            && palette.accent.resolve(with: palette).rgbComponents != nil
        let breath = !focused ? [] : measurable ? cycle.colors(dim: face, bright: accent) : [accent]
        var buffer = draw(breath.isEmpty ? face : breath[cycle.step % breath.count])
        guard !context.isMeasuring, breath.count > 1, cycle.isAnimating else { return buffer }
        let framed = breath.map { draw($0).lines }
        buffer.animatedCells += buffer.lines.indices.compactMap { row in
            let rowFrames = framed.compactMap { row < $0.count ? $0[row] : nil }
            guard rowFrames.count == framed.count, let first = rowFrames.first else { return nil }
            return AnimatedCellRun(
                offsetX: 0, offsetY: row, width: first.strippedLength,
                frames: rowFrames, frameTicks: cycle.frameTicks, clock: cycle.clock)
        }
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
