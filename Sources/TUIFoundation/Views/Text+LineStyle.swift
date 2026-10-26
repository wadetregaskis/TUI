//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+LineStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension Text {
    /// How a line under or through text is drawn — mirrors SwiftUI's
    /// `Text.LineStyle`.
    ///
    /// It is the value of an attributed string's
    /// ``AttributeScopes/SwiftUIAttributes/underlineStyle`` and
    /// ``AttributeScopes/SwiftUIAttributes/strikethroughStyle``, and what
    /// ``Text/underline(_:pattern:color:)`` and its kin draw:
    ///
    /// ```swift
    /// var deadline = AttributedString("Friday")
    /// deadline.underlineStyle = Text.LineStyle(pattern: .dash, color: .red)
    /// Text("Due \(Text(deadline))")
    /// ```
    ///
    /// A terminal draws an underline in five shapes — single, double, curly,
    /// dotted and dashed — and some colour it apart from the text. Each
    /// terminal draws a different subset, and one that is sent a shape it
    /// does not know can draw a background or a blink instead, so what a
    /// line asks for is reduced to what the terminal draws: a shape it lacks
    /// is a single line, a colour it lacks the text's own (see *Terminal
    /// compatibility survey*, "Underline shapes and colours"). A strikethrough
    /// is always one solid line; only iTerm2 colours it.
    public struct LineStyle: Hashable, Sendable {
        /// The pattern a line is drawn in — mirrors SwiftUI's
        /// `Text.LineStyle.Pattern`, with two more for the shapes a terminal
        /// underline has that SwiftUI's patterns do not name.
        ///
        /// A terminal has a dotted and a dashed underline and no others, so
        /// ``dashDot`` and ``dashDotDot`` draw dashed.
        public struct Pattern: Hashable, Sendable {
            let shape: Shape

            /// A solid line.
            public static let solid = Self(shape: .solid)

            /// A dotted line.
            public static let dot = Self(shape: .dot)

            /// A dashed line.
            public static let dash = Self(shape: .dash)

            /// Alternating dashes and dots — a dashed line on a terminal,
            /// which has no dash-dot underline.
            public static let dashDot = Self(shape: .dashDot)

            /// A dash then two dots, repeating — a dashed line on a terminal,
            /// which has no dash-dot-dot underline.
            public static let dashDotDot = Self(shape: .dashDotDot)

            /// Two solid lines (SGR `4:2`). TUI-only: SwiftUI spells a
            /// double underline with `NSUnderlineStyle`, which a terminal app
            /// has no reason to import.
            public static let double = Self(shape: .double)

            /// A wavy line (SGR `4:3`), the spelling checker's. TUI-only:
            /// SwiftUI has no wavy line.
            public static let curly = Self(shape: .curly)
        }

        /// The shapes ``Pattern`` names, in one byte.
        enum Shape: UInt8, Hashable, Sendable {
            case solid, dot, dash, dashDot, dashDotDot, double, curly
        }

        /// The pattern this line is drawn in.
        let pattern: Pattern

        /// The line's own colour, stated or not, without its alpha: see
        /// `TextStyleStatements`.
        let statedColor: StatedColorValue

        /// The line's colour, opaque, or `nil` for the text's own.
        var color: Color? { statedColor.value }

        /// A line in `pattern`, coloured `color` or, for `nil`, as the text is
        /// — mirrors SwiftUI's `init(pattern:color:)`.
        ///
        /// The colour is drawn opaque: SGR states a line's colour with no
        /// alpha, so a translucent one keeps its hue and loses its opacity.
        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.statedColor = StatedColorValue(color)
        }

        /// A single solid line in the text's colour.
        public static let single = Self()

        /// This line with its colour resolved against `palette`, as a
        /// `TextStyle`'s own colours are.
        func resolved(with palette: any Palette) -> Self {
            guard let color else { return self }
            return Self(pattern: pattern, color: color.resolve(with: palette))
        }

        /// This line as an UNDERLINE in a terminal that draws `support`: its
        /// shape, the single line where the terminal lacks it, and its colour
        /// only where the terminal draws one.
        func fittingUnderline(to support: LineStyleSupport) -> Self {
            let fitted: Pattern
            switch pattern.shape {
            case .solid: fitted = .solid
            case .double: fitted = support.doubleUnderline ? .double : .solid
            case .dot, .dash, .dashDot, .dashDotDot, .curly: fitted = support.patternedUnderlines ? pattern : .solid
            }
            return Self(pattern: fitted, color: support.underlineColour ? color : nil)
        }

        /// This line as a STRIKETHROUGH in a terminal that draws `support`:
        /// solid, whatever it asked, as SGR 9 is the only strikethrough, and
        /// coloured only where SGR 58 reaches it.
        func fittingStrikethrough(to support: LineStyleSupport) -> Self {
            Self(pattern: .solid, color: support.strikethroughColour ? color : nil)
        }

        /// The SGR parameter that draws this line as an underline: `4`, or
        /// `4:n` for another shape.
        var underlineParameter: String {
            switch pattern.shape {
            case .solid: "4"
            case .double: "4:2"
            case .curly: "4:3"
            case .dot: "4:4"
            case .dash, .dashDot, .dashDotDot: "4:5"
            }
        }
    }
}

/// The line styles the terminal draws as asked; every underline shape and
/// colour where nothing has said otherwise (headless, tests).
private struct LineStyleSupportKey: EnvironmentKey {
    static let defaultValue = LineStyleSupport.underlines
}

extension EnvironmentValues {
    /// The line styles the terminal draws as asked: set by the run loop from
    /// `TerminalHost.lineStyles`, and read by text as it spells its lines
    /// (``TextStyle/fittingLines(to:)``).
    package var lineStyleSupport: LineStyleSupport {
        get { self[LineStyleSupportKey.self] }
        set { self[LineStyleSupportKey.self] = newValue }
    }
}
