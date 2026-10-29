//  🖥️ TUI — A Terminal UI framework for Swift
//  StatedLength.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension Int {
    /// The most cells, either way, a length an app states is taken at — a
    /// frame's width, an inset, a stack's spacing, an offset: 2^16, past every
    /// screen, and far enough inside `Int` that the layout's sums of lengths
    /// cannot overflow.
    ///
    /// Layout adds what it is told: a padding's two insets and its content, a
    /// stack's gaps, a frame's width and an alignment's offset. `Int.max`
    /// spelled for "as long as it goes", or a length computed to 10^18, trapped
    /// in the first such sum, and one an allocation could survive asked a
    /// `String` for 10^18 spaces. Held here, each is a long drawing, not a
    /// crash — and a length is drawn: a frame 2^20 rows tall took a debug
    /// build seconds a frame, where 2^16 takes a fraction of one.
    package static let statedLengthLimit = 1 << 16

    /// This length held to ±``statedLengthLimit``.
    package var heldToStatedLength: Int {
        Swift.min(Swift.max(self, -Self.statedLengthLimit), Self.statedLengthLimit)
    }
}
