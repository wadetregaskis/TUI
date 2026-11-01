//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+Layout.swift
//
//  SwiftUI's `Text.Layout`: a text's lines, runs and glyphs, as a
//  `TextRenderer` is handed them to draw (the owner's TEXT-EFFECTS ruling,
//  2026-10-28; `TextRenderer design study, O16`). In cells: a line is a row
//  of the text, a run a span of one style and one set of custom attributes,
//  and a glyph (a run slice of one) a grapheme cluster, one or two cells
//  wide. Geometry is CGFloat in cells, as the shapes' is: a point is a cell
//  across and a row down.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import TUICore

@MainActor extension Text {
    /// A value describing the layout and custom attributes of a tree of
    /// `Text` views — mirrors SwiftUI's `Text.Layout`.
    ///
    /// A collection of the text's lines, each of its runs, each of its glyphs.
    /// TUI has no baseline: a line's origin is its first cell's top-left, and
    /// a glyph's bounds are the cells it covers (``TypographicBounds``).
    public struct Layout: RandomAccessCollection, Equatable, Sendable {
        public typealias Element = Line
        public typealias Index = Int
        public typealias Indices = Range<Int>

        /// The lines, top to bottom.
        let lines: [Line]

        /// Whether the text was cut short to fit (a line limit, or a frame
        /// too small, with its truncation mode's ellipsis).
        public let isTruncated: Bool

        init(lines: [Line], isTruncated: Bool) {
            self.lines = lines
            self.isTruncated = isTruncated
        }

        public var startIndex: Int { lines.startIndex }
        public var endIndex: Int { lines.endIndex }
        public subscript(index: Int) -> Line { lines[index] }

        /// The index of a character in the text: its offset in the text's
        /// characters (SwiftUI counts UTF-16 units in the attributed string; a
        /// terminal text is indexed by `Character` everywhere — a deliberate
        /// deviation).
        @frozen public struct CharacterIndex: Strideable, Hashable, Sendable {
            // swiftlint:disable:next nesting
            public typealias Stride = Int

            @usableFromInline let offset: Int

            @inlinable init(offset: Int) { self.offset = offset }

            public static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
            public func advanced(by n: Int) -> Self { Self(offset: offset + n) }
            public func distance(to other: Self) -> Int { other.offset - offset }
        }

        /// The extent of a line, a run or a glyph — mirrors SwiftUI's
        /// `Text.Layout.TypographicBounds`. In cells: `origin` is the first
        /// cell's top-left, `width` the cells across, and a row is all ascent —
        /// `ascent` 1, `descent` 0, `leading` 0 — so ``rect`` is exactly the
        /// cells covered, and its middle is the row's.
        @frozen public struct TypographicBounds: Equatable, Sendable {
            public var origin: CGPoint
            public var width: CGFloat
            public var ascent: CGFloat
            public var descent: CGFloat
            public var leading: CGFloat

            public init() {
                origin = .zero
                width = 0
                ascent = 0
                descent = 0
                leading = 0
            }

            init(column: Int, row: Int, width: Int) {
                origin = CGPoint(x: CGFloat(column), y: CGFloat(row))
                self.width = CGFloat(width)
                ascent = 1
                descent = 0
                leading = 0
            }

            /// The rectangle the bounds cover, the line's top at `origin.y`.
            public var rect: CGRect {
                CGRect(x: origin.x, y: origin.y, width: width, height: ascent + descent)
            }
        }

        /// Options for drawing a line, a run or a glyph — mirrors SwiftUI's
        /// `Text.Layout.DrawingOptions`. A cell has no subpixels to quantize, so
        /// the one option changes nothing here.
        @frozen public struct DrawingOptions: OptionSet, Sendable {
            public let rawValue: UInt32
            public init(rawValue: UInt32) { self.rawValue = rawValue }

            /// Turns off subpixel quantization of the glyphs' positions:
            /// nothing to turn off on a terminal.
            public static var disablesSubpixelQuantization: Self { Self(rawValue: 1 << 0) }
        }

        /// One line of a text — mirrors SwiftUI's `Text.Layout.Line`: its
        /// runs, left to right.
        public struct Line: RandomAccessCollection, Equatable, Sendable {
            // swiftlint:disable:next nesting
            public typealias Indices = Range<Int>

            /// Where the line starts: its first cell's top-left, in the text's
            /// own cells.
            public var origin: CGPoint

            let runs: [Run]
            let width: Int

            init(origin: CGPoint, runs: [Run], width: Int) {
                self.origin = origin
                self.runs = runs
                self.width = width
            }

            public var startIndex: Int { runs.startIndex }
            public var endIndex: Int { runs.endIndex }
            public subscript(index: Int) -> Run { runs[index] }

            /// The cells the line covers.
            public var typographicBounds: TypographicBounds {
                TypographicBounds(column: Int(origin.x), row: Int(origin.y), width: width)
            }
        }

        /// A span of a line in one style and one set of custom attributes —
        /// mirrors SwiftUI's `Text.Layout.Run`: its glyphs, left to right.
        public struct Run: RandomAccessCollection, Equatable, Sendable {
            // A run's glyphs sliced are a run slice, as SwiftUI's are.
            // swiftlint:disable:next nesting
            public typealias SubSequence = RunSlice
            // swiftlint:disable:next nesting
            public typealias Indices = Range<Int>

            /// The glyphs: a grapheme cluster each, where it is drawn.
            let glyphs: [Glyph]
            /// The style the run is drawn in.
            let style: SGRState
            /// The run's custom attributes.
            let attributes: TextAttributes?

            init(glyphs: [Glyph], style: SGRState, attributes: TextAttributes?) {
                self.glyphs = glyphs
                self.style = style
                self.attributes = attributes
            }

            public var startIndex: Int { glyphs.startIndex }
            public var endIndex: Int { glyphs.endIndex }
            public subscript(index: Int) -> RunSlice { RunSlice(run: self, indices: index..<(index + 1)) }
            public subscript(bounds: Range<Int>) -> RunSlice { RunSlice(run: self, indices: bounds) }

            /// The custom attribute of type `T` on this run, or `nil`
            /// (``Text/customAttribute(_:)``).
            public subscript<T: TextAttribute>(key: T.Type) -> T? { attributes?[key] }

            /// Left to right: TUI lays text out so until right-to-left text lands.
            public var layoutDirection: LayoutDirection { .leftToRight }

            /// The cells the run covers.
            public var typographicBounds: TypographicBounds { Self.bounds(of: glyphs[...]) }

            /// Where each glyph's characters start in the text.
            public var characterIndices: [CharacterIndex] { glyphs.map(\.characterIndex) }

            static func bounds(of glyphs: ArraySlice<Glyph>) -> TypographicBounds {
                guard let first = glyphs.first, let last = glyphs.last else { return TypographicBounds() }
                return TypographicBounds(
                    column: first.column, row: first.row, width: last.column + last.width - first.column)
            }
        }

        /// Some of a run's glyphs — mirrors SwiftUI's `Text.Layout.RunSlice`.
        /// A slice of one is a glyph: one grapheme cluster.
        public struct RunSlice: RandomAccessCollection, Equatable, Sendable {
            // A slice's glyphs sliced are a run slice again, as SwiftUI's are.
            // swiftlint:disable:next nesting prefer_self_in_static_references
            public typealias SubSequence = RunSlice
            // swiftlint:disable:next nesting
            public typealias Indices = Range<Int>

            /// The run the glyphs are of.
            public var run: Run
            /// Which of its glyphs.
            public var indices: Range<Int>

            public init(run: Run, indices: Range<Int>) {
                self.run = run
                self.indices = indices
            }

            public var startIndex: Int { indices.lowerBound }
            public var endIndex: Int { indices.upperBound }
            public subscript(index: Int) -> Self { Self(run: run, indices: index..<(index + 1)) }
            public subscript(bounds: Range<Int>) -> Self { Self(run: run, indices: bounds) }

            /// The custom attribute of type `T` on the slice's run, or `nil`.
            public subscript<T: TextAttribute>(key: T.Type) -> T? { run[key] }

            /// The cells the glyphs cover.
            public var typographicBounds: TypographicBounds { Run.bounds(of: run.glyphs[indices]) }

            /// Where each glyph's characters start in the text.
            public var characterIndices: [CharacterIndex] { run.glyphs[indices].map(\.characterIndex) }
        }

        /// One grapheme cluster where it is drawn.
        struct Glyph: Equatable, Sendable {
            let character: String
            let column: Int
            let row: Int
            let width: Int
            let characterIndex: CharacterIndex
        }
    }
}
