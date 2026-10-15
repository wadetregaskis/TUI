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
/// The caps and the ring are drawn in the caps' colour — the face's own at
/// rest, so they round or square it off, and the accent's breath while the
/// button holds the focus (``ButtonCapCycle``). A face with no caps (a
/// ``ControlSize/mini`` one) ends where its label does, and shows the focus by
/// breathing the label instead.
struct ButtonFaceEdges: Equatable, Sendable {
    /// The cap before the label and the cap after it; `nil` for none.
    let caps: (open: Character, close: Character)?

    /// The rows above and below a three-row face; `nil` for a one-row face.
    let ring: Ring?

    /// The row above a three-row face and the row below it: an edge glyph
    /// along the face, between two corners.
    struct Ring: Equatable, Sendable {
        let topEdge: Character
        let bottomEdge: Character
        let topCorners: (leading: Character, trailing: Character)
        let bottomCorners: (leading: Character, trailing: Character)

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.topEdge == rhs.topEdge && lhs.bottomEdge == rhs.bottomEdge
                && lhs.topCorners == rhs.topCorners && lhs.bottomCorners == rhs.bottomCorners
        }

        /// The row above a face `width` cells wide, caps included.
        func top(width: Int) -> String { row(topEdge, corners: topCorners, width: width) }

        /// The row below a face `width` cells wide, caps included.
        func bottom(width: Int) -> String { row(bottomEdge, corners: bottomCorners, width: width) }

        private func row(_ edge: Character, corners: (leading: Character, trailing: Character), width: Int) -> String {
            guard width >= 2 else { return String(repeating: edge, count: max(0, width)) }
            return String(corners.leading) + String(repeating: edge, count: width - 2) + String(corners.trailing)
        }
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

    /// A capsule three rows tall: half blocks above and below the face, which
    /// stop short of the corners, so the ends round off.
    static let tallCapsule = Self(
        caps: (TerminalSymbols.openCap, TerminalSymbols.closeCap),
        ring: Ring(
            topEdge: "\u{2584}", bottomEdge: "\u{2580}",
            topCorners: (" ", " "), bottomCorners: (" ", " ")))

    /// A rounded rectangle three rows tall: half blocks above and below the
    /// face, met by quadrant corners, so the face is square to its corners.
    static let tallRoundedRectangle = Self(
        caps: (TerminalSymbols.openCap, TerminalSymbols.closeCap),
        ring: Ring(
            topEdge: "\u{2584}", bottomEdge: "\u{2580}",
            topCorners: ("\u{2597}", "\u{2596}"), bottomCorners: ("\u{259D}", "\u{2598}")))
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
    /// | `.large`      | 3    | ring | the style's |
    /// | `.extraLarge` | 3    | ring | the style's + 1 |
    ///
    /// A `.circle` has no padding at any size.
    func sized(_ size: ControlSize, shape: ButtonBorderShape) -> Self {
        guard !isPlain else { return self }
        var sized = self
        let square = shape.kind == .roundedRectangle
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
            sized.edges = square ? .tallRoundedRectangle : .tallCapsule
        case .extraLarge:
            sized.horizontalPadding += 1
            sized.edges = square ? .tallRoundedRectangle : .tallCapsule
        }
        if shape.kind == .circle { sized.horizontalPadding = 0 }
        return sized
    }
}

// MARK: - Drawing the edges

extension _ButtonStyleBody {
    /// The SGR introducer the caps (and a ring) are drawn in now.
    static func capSequence(_ caps: ButtonCapCycle) -> String? {
        var capStyle = TextStyle()
        capStyle.foregroundColor = caps.colorNow
        return ANSIRenderer.styleSequence(for: capStyle)
    }

    /// `face` — a one-row face, or a taller label's — with the ring of a
    /// three-row face (``ButtonFaceEdges/ring``) above and below it, drawn in
    /// the caps' colour and breathing with them; `face` as it is when the
    /// edges have no ring.
    @MainActor
    static func ringed(
        _ face: FrameBuffer, edges: ButtonFaceEdges, caps: ButtonCapCycle, context: RenderContext
    ) -> FrameBuffer {
        guard let ring = edges.ring, face.height > 0 else { return face }
        let width = face.width
        let sequence = capSequence(caps)
        var buffer = FrameBuffer(lines: [ANSIRenderer.wrap(ring.top(width: width), in: sequence)])
        buffer.appendVertically(face)
        buffer.appendVertically(FrameBuffer(lines: [ANSIRenderer.wrap(ring.bottom(width: width), in: sequence)]))
        if !context.isMeasuring {
            buffer.animatedCells += caps.ringRuns(ring, width: width, bottomRow: face.height + 1)
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
