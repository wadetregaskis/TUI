//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+LineStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension Text {
    /// How a line under or through text is drawn — mirrors SwiftUI's
    /// `Text.LineStyle`.
    ///
    /// It is the value of an attributed string's
    /// ``Foundation/AttributeScopes/SwiftUIAttributes/underlineStyle`` and
    /// ``Foundation/AttributeScopes/SwiftUIAttributes/strikethroughStyle``:
    ///
    /// ```swift
    /// var deadline = AttributedString("Friday")
    /// deadline.underlineStyle = .single
    /// Text("Due ") + Text(deadline)
    /// ```
    ///
    /// Only ``single`` is here: one solid line in the text's own colour, which
    /// is what SGR 4 and SGR 9 draw on every terminal. SwiftUI's
    /// `init(pattern:color:)` — dotted and dashed lines, a line of another
    /// colour — waits on measurements of which terminals draw the styled
    /// underline (`4:x`) and its colour (SGR 58), so a pattern fails to
    /// compile rather than drawing as a solid line.
    public struct LineStyle: Hashable, Sendable {
        init() {}

        /// A single solid line in the text's colour.
        public static let single = Self()
    }
}
