//  🖥️ TUI — A Terminal UI framework for Swift
//  AttributeScopes+CoreText.swift
//
//  A paragraph's attributes, which SwiftUI's attribute scope takes from Core
//  Text: under Core Text's names and value types, declared by TUI on every
//  platform, so that `string.alignment = .center` compiles and draws (G3 L4,
//  the owner's ruling A-ATTRED-3 of 2026-11-17).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension AttributeScopes {
    /// The namespace of the paragraph attributes SwiftUI's scope declares —
    /// mirrors Core Text's `AttributeScopes.CoreTextAttributes` (macOS 26).
    ///
    /// Not a scope of its own, as Core Text's is not: its keys are reached
    /// through ``SwiftUIAttributes``, as `string.alignment`.
    ///
    /// > Important: These are TUI's own declarations under Core Text's names,
    /// > so they exist on macOS 15, Linux and Windows. On macOS, Core Text's
    /// > declarations of the same names are visible to an app as well wherever
    /// > Core Text is loaded, which TUI does (its SF Symbols table reads a font
    /// > through it), unless the app builds with the `MemberImportVisibility`
    /// > upcoming feature and imports none of AppKit, SwiftUI or Core Text.
    /// > Setting an attribute picks TUI's (see ``SwiftUIAttributes``), but
    /// > spelling one of these types in a type position —
    /// > `let alignment: AttributedString.TextAlignment` — is ambiguous there,
    /// > as spelling ``SwiftUIAttributes`` is. Let the value's type be
    /// > inferred (`string.alignment = .center`). Linux and Windows have no
    /// > second declaration.
    public struct CoreTextAttributes {}
}

extension AttributeScopes.CoreTextAttributes {
    /// The alignment of a paragraph's lines — mirrors Core Text's
    /// `TextAlignmentAttribute`.
    ///
    /// Bounded by paragraphs: setting it on part of a paragraph sets it on the
    /// whole of it, and text typed into the paragraph takes it.
    @frozen public enum TextAlignmentAttribute: CodableAttributedStringKey {
        public typealias Value = AttributedString.TextAlignment
        /// Not Core Text's own name, which its interface does not show: a
        /// value carrying Core Text's attribute of the same meaning keeps it
        /// under that name, invisible here rather than read as the wrong type.
        public static let name = "TUI.TextAlignment"
        public static let runBoundaries: AttributedString.AttributeRunBoundaries? = .paragraph
    }
}

extension AttributedString {
    /// How a paragraph's lines sit across the width they are laid out in —
    /// mirrors Core Text's `AttributedString.TextAlignment` (macOS 26).
    ///
    /// ```swift
    /// var heading = AttributedString("Chapter One\n")
    /// heading.alignment = .center
    /// ```
    ///
    /// A ``Text`` aligns each line of the paragraph within the text's own
    /// width (its widest line), as ``View/multilineTextAlignment(_:)`` aligns
    /// all of them, and a paragraph's alignment wins over that modifier for its
    /// own lines. A `TextEditor` aligns each row of the paragraph within the
    /// editor's width. `left` and `right` are the sides of the screen, as
    /// Core Text's are, not a writing direction's leading and trailing.
    public enum TextAlignment: CaseIterable, Codable, Hashable, Sendable {
        case left
        case center
        case right
    }
}

extension AttributedString.TextAlignment {
    /// The blank cells in front of a line `lineWidth` cells wide set in
    /// `width` cells, as ``multilineAlignment`` pads a text's lines: none for
    /// `left`, half the rest (rounded down) for `center`, all of it for
    /// `right`, and none for a line as wide as `width` or wider.
    package func leadingCells(lineWidth: Int, in width: Int) -> Int {
        multilineAlignment.leadingPad(lineWidth: lineWidth, blockWidth: width)
    }

    /// The same alignment as a text's ``TUIFoundation/TextAlignment``, which
    /// aligns a whole text's lines.
    package var multilineAlignment: TUIFoundation.TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
