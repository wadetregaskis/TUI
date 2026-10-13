//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerViewCore+Overflow.swift
//
//  What a box's content draws past its region (`OverlayLayer.isOverflow`), in
//  the box's stacking order: under the footer, which comes after the body,
//  and under the rules and the divider, which SwiftUI's border draws over its
//  content's overflow (measured; decisions-GUIDE3 B-GUIDE3-5). The box draws
//  its chrome by hand rather than composing it, so no combining operation
//  cuts the overflow under it.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _ContainerViewCore {
    /// The body's floating layers, shifted by (`dx`, `dy`) to where the box
    /// draws the body, with what the body draws past its region cut where the
    /// footer, `separatorRows` below the body, paints — as a stack's next
    /// child cuts it.
    ///
    /// The body's layers as they are, shifted, unless the body carries
    /// overflow and the box has a footer, which is almost never.
    func carriedBodyOverlays(
        _ bodyBuffer: FrameBuffer, footer footerBuffer: FrameBuffer?, separatorRows: Int, shiftedByX dx: Int, y dy: Int
    ) -> [OverlayLayer] {
        guard let footer = footerBuffer, !footer.isEmpty, !bodyBuffer.overlaysHoldNoOverflow else {
            return bodyBuffer.shiftedOverlays(byX: dx, y: dy)
        }
        return bodyBuffer.overflowCovered(under: footer, at: (x: 0, y: bodyBuffer.lines.count + separatorRows))
            .map { $0.shifted(byX: dx, y: dy) }
    }

    /// Cuts what `box` carries past its regions under the box's rules — its
    /// top and bottom rows, and the side columns around an `innerWidth`-wide
    /// inside — and under its footer divider at `dividerRow`, when it has one.
    /// Past them it is still drawn.
    ///
    /// Nothing unless the box carries overflow, which is almost never.
    static func coverOverflowUnderRules(of box: inout FrameBuffer, innerWidth: Int, dividerRow: Int?) {
        guard !box.overlaysHoldNoOverflow else { return }
        let (width, rows) = (box.width, box.height)
        var rules = [
            (x: 0, y: 0, width: width, height: 1), (x: 0, y: rows - 1, width: width, height: 1),
            (x: 0, y: 0, width: 1, height: rows), (x: innerWidth + 1, y: 0, width: 1, height: rows),
        ]
        if let dividerRow { rules.append((x: 0, y: dividerRow, width: width, height: 1)) }
        box.coverOverflow(underRects: rules)
    }
}
