//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Alignment+UnitPoint.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - From an Alignment

extension Alignment {
    /// This alignment as the anchor point ``LayoutSubview/place(in:anchor:proposal:)``
    /// wants.
    ///
    /// The two spell the same idea — "put it against that edge" — in the two
    /// vocabularies the layout system uses: `Alignment` names edges, placement
    /// takes fractions. Custom alignment guides collapse to the nearest of the
    /// three standard positions, because an anchor is a fraction of the
    /// subview's own size and a guide is an offset within it: there is no
    /// fraction that means "wherever this view said its first baseline was".
    var unitPoint: UnitPoint {
        let x: Double =
            switch horizontal {
            case .leading: 0
            case .trailing: 1
            default: 0.5
            }
        let y: Double =
            switch vertical {
            case .top: 0
            case .bottom: 1
            default: 0.5
            }
        return UnitPoint(x: x, y: y)
    }
}
