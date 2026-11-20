//  🖥️ TUI — A Terminal UI framework for Swift
//  AttributeScopes+LineHeight.swift
//
//  A paragraph's line height, which SwiftUI's attribute scope takes from Core
//  Text (G3 L4, the owner's rulings A-ATTRED-3 of 2026-11-17 and A-ATTRED-13
//  (b) of 2026-11-19): Core Text's own type where there is Core Text, TUI's
//  identical one where there is not, and no attribute of TUI's own. A
//  terminal draws whole rows only, so a paragraph's lines are drawn with
//  blank rows after them, rounded from the factor (`ParagraphLineRows`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// How many rows each line of a paragraph takes, from its line height: the
/// rule `Text` and `TextEditor` share, so both draw a value alike.
///
/// A terminal row is a whole line of text, so a line height is drawn crudely
/// (the owner's ruling A-ATTRED-3, 2026-11-17): `.multiple(factor:)` takes
/// `factor` rows, rounded half away from zero, at least one and at most
/// ``maximum``; the rows past the first are blank, below the line's text. So
/// 1.5 and 2 put a blank row after each line, 2.5 and 3 two; 1.2 or 1.4 none.
/// Every other value takes one row: the presets (`normal`, `tight`, `loose`,
/// `variable`) and `leading(increase:)` and `exact(points:)`, whose points have
/// no fixed rows in a terminal (a row is as tall as the terminal's font makes
/// it, which TUI does not know), and which Core Text cannot be read back for.
package enum ParagraphLineRows {
    /// The most rows a line takes: a factor past 8.5 draws 8, seven blank rows
    /// after each line, which is already far apart; a factor of a million
    /// would otherwise ask for a million rows a line.
    package static let maximum = 8

    /// The rows a line takes at a line height of `factor` times its own:
    /// `factor` rounded half away from zero, within `1...maximum`. Not a
    /// number takes one.
    package static func rows(forFactor factor: Double) -> Int {
        guard factor.isFinite else { return factor == .infinity ? maximum : 1 }
        return Int(min(Double(maximum), max(1, factor.rounded())))
    }

    /// The factors Core Text's `LineHeight` is read by on Apple's platforms,
    /// in twentieths: every multiple of 0.05 from 1.5, the least that takes a
    /// second row, to 8.45, the most below ``maximum``'s rounding up. Core
    /// Text's type has no accessor for its factor, so TUI compares the value
    /// with `.multiple(factor:)` of each (the owner's ruling A-ATTRED-13 (b));
    /// any other factor draws one row there. Off Apple's platforms TUI's own
    /// type reads every factor.
    package static let readableTwentieths = 30...169
}

#if canImport(CoreText)
    import CoreText

    // Core Text's `AttributedString.LineHeight` and its key (macOS 26), as for a
    // paragraph's alignment (`AttributeScopes+CoreText.swift`): one declaration,
    // so naming the type is never ambiguous, and `string.lineHeight` wants macOS
    // 26 as SwiftUI's does. Before macOS 26 a program cannot set a line height,
    // as in SwiftUI (the cost ledger's row M12). The scope's member is computed,
    // as `alignment`'s is (deviation T14, which the owner approved on
    // 2026-11-19 and which covers both).

    extension AttributeScopes.SwiftUIAttributes {
        // Computed, never called: a key path to it names the key, and nothing
        // reads the value (an uninhabited key type has none to return).

        /// A property for accessing a paragraph's line height — mirrors
        /// SwiftUI's, whose key and value are Core Text's
        /// (`AttributedString.LineHeight`).
        ///
        /// A terminal draws whole rows only: `.multiple(factor:)` puts blank
        /// rows after each of the paragraph's lines, its factor rounded
        /// (`multiple(factor: 2)` one, `multiple(factor: 3)` two), and every
        /// other value draws one row a line. TUI reads the factor by comparing
        /// the value with each multiple of 0.05 from 1.5 to 8.45; any other
        /// factor draws one row. macOS 26, as SwiftUI's.
        @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
        public var lineHeight: AttributeScopes.CoreTextAttributes.LineHeightAttribute {
            fatalError("a scope's attribute is named by its key path, never read")
        }
    }

    extension AttributeDynamicLookup {
        /// The ``AttributeScopes/SwiftUIAttributes/lineHeight`` attribute, as
        /// `string.lineHeight`.
        @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
        public subscript(
            dynamicMember keyPath: KeyPath<
                AttributeScopes.SwiftUIAttributes, AttributeScopes.CoreTextAttributes.LineHeightAttribute
            >
        ) -> AttributeScopes.CoreTextAttributes.LineHeightAttribute {
            self[AttributeScopes.CoreTextAttributes.LineHeightAttribute.self]
        }
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    extension AttributedString.LineHeight {
        /// The rows each line of a paragraph of this height takes
        /// (``ParagraphLineRows``): the presets one, and a `.multiple(factor:)`
        /// whose factor is one of ``ParagraphLineRows/readableTwentieths``
        /// that factor's; any other value one.
        package var drawnRows: Int {
            if self == .normal || self == .tight || self == .loose || self == .variable { return 1 }
            for twentieths in ParagraphLineRows.readableTwentieths
            where self == .multiple(factor: CGFloat(twentieths) / 20) {
                return ParagraphLineRows.rows(forFactor: Double(twentieths) / 20)
            }
            return 1
        }
    }
#else
    extension AttributeScopes.CoreTextAttributes {
        /// The height of a paragraph's lines — mirrors Core Text's
        /// `LineHeightAttribute`.
        ///
        /// Bounded by paragraphs: setting it on part of a paragraph sets it on
        /// the whole of it, and text typed into the paragraph takes it. Not
        /// Codable, as Core Text's is not.
        @frozen public enum LineHeightAttribute: AttributedStringKey {
            public typealias Value = AttributedString.LineHeight
            /// Not Core Text's own name, which its interface does not show.
            public static let name = "TUI.LineHeight"
            public static let runBoundaries: AttributedString.AttributeRunBoundaries? = .paragraph
        }
    }

    extension AttributedString {
        /// How tall a paragraph's lines are — mirrors Core Text's
        /// `AttributedString.LineHeight` (macOS 26), its makers and nothing
        /// more.
        ///
        /// ```swift
        /// var poem = AttributedString("Roses are red,\nviolets are blue.")
        /// poem.lineHeight = .multiple(factor: 2)
        /// ```
        ///
        /// A terminal draws whole rows only: `.multiple(factor:)` puts blank
        /// rows after each of the paragraph's lines, its factor rounded
        /// (`multiple(factor: 2)` one, `multiple(factor: 3)` two), and every
        /// other value draws one row a line (``ParagraphLineRows``).
        public struct LineHeight: Codable, Hashable, Sendable {
            /// What it was made as: Core Text keeps its own privately.
            enum Storage: Codable, Hashable, Sendable {
                case variable, normal, tight, loose
                case multiple(CGFloat)
                case leading(CGFloat)
                case exact(CGFloat)
            }

            let storage: Storage

            /// The font's own line height, varying with the characters a line
            /// holds.
            public static var variable: Self { Self(storage: .variable) }
            /// The font's standard line height.
            public static var normal: Self { Self(storage: .normal) }
            /// A line height a little less than the font's.
            public static var tight: Self { Self(storage: .tight) }
            /// A line height a little more than the font's.
            public static var loose: Self { Self(storage: .loose) }

            /// A multiple of the font's line height: `factor` rows a line,
            /// rounded, here.
            public static func multiple(factor: CGFloat) -> Self { Self(storage: .multiple(factor)) }
            /// The font's line height with `increase` points more between
            /// lines: one row a line, here.
            public static func leading(increase: CGFloat) -> Self { Self(storage: .leading(increase)) }
            /// A line height of exactly `points`: one row a line, here.
            public static func exact(points: CGFloat) -> Self { Self(storage: .exact(points)) }

            /// The rows each line of a paragraph of this height takes
            /// (``ParagraphLineRows``): a multiple's factor rounded, any other
            /// value one.
            package var drawnRows: Int {
                guard case .multiple(let factor) = storage else { return 1 }
                return ParagraphLineRows.rows(forFactor: Double(factor))
            }
        }
    }

    extension AttributeDynamicLookup {
        /// The ``AttributeScopes/SwiftUIAttributes/lineHeight`` attribute, as
        /// `string.lineHeight`.
        public subscript(
            dynamicMember keyPath: KeyPath<
                AttributeScopes.SwiftUIAttributes, AttributeScopes.CoreTextAttributes.LineHeightAttribute
            >
        ) -> AttributeScopes.CoreTextAttributes.LineHeightAttribute {
            self[AttributeScopes.CoreTextAttributes.LineHeightAttribute.self]
        }
    }
#endif

extension AttributedSubstring {
    /// The rows each line of this stretch's paragraph is drawn in: its line
    /// height's (``ParagraphLineRows``), or one where it states none, or the
    /// platform has none (a Mac before macOS 26). Read off a substring, as
    /// `drawnParagraphAlignment` is, for Windows.
    package var drawnLineRows: Int {
        #if canImport(CoreText)
            if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *), let height = self.lineHeight {
                return height.drawnRows
            }
            return 1
        #else
            return self.lineHeight?.drawnRows ?? 1
        #endif
    }
}
