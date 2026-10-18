//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SheetCornerRadius.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - Carrying the corner radius to the sheet's box

private struct SheetCornerRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// The corner radius the presented sheet's box takes, set by the modal host
    /// when the content named one with `presentationCornerRadius(_:)` — `nil`
    /// for the appearance's corners.
    ///
    /// A terminal sheet has no card of its own: the presented content's
    /// outermost box (a `Dialog`, a `Panel`, a `.border()`) is the sheet, so the
    /// radius reaches that box, as ``sheetDetentHeight`` does, and that box
    /// consumes it for its children. A radius is read as the box-drawing tier
    /// reads one (the shapes' `B-W1-2`): zero is a square corner, `┌`; any other
    /// a rounded one, `╭`.
    package var sheetCornerRadius: CGFloat? {
        get { self[SheetCornerRadiusKey.self] }
        set { self[SheetCornerRadiusKey.self] = newValue }
    }
}

extension BorderStyle {
    /// This style with its corners rounded for a `radius` above zero and
    /// squared for zero, where the style has both — the light lines, whose
    /// corners are `╭` and `┌` — or as it is: heavy and double lines, dots and
    /// blocks have no rounded corner to swap in. `nil` leaves it as it is.
    package func withCornerRadius(_ radius: CGFloat?) -> BorderStyle {
        guard let radius, horizontal == "─", vertical == "│" else { return self }
        let rounded = radius > 0
        return BorderStyle(
            topLeft: rounded ? "╭" : "┌", topRight: rounded ? "╮" : "┐",
            bottomLeft: rounded ? "╰" : "└", bottomRight: rounded ? "╯" : "┘",
            horizontal: horizontal, vertical: vertical, leftT: leftT, rightT: rightT,
            bottomHorizontal: bottomHorizontal, rightVertical: rightVertical, paintsBackground: paintsBackground)
    }
}
