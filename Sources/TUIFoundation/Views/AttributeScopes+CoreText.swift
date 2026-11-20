//  🖥️ TUI — A Terminal UI framework for Swift
//  AttributeScopes+CoreText.swift
//
//  A paragraph's alignment, which SwiftUI's attribute scope takes from Core
//  Text (G3 L4, the owner's rulings A-ATTRED-3 of 2026-11-17 and attralign of
//  2026-11-19): Core Text's own types where the SDK declares them, TUI's
//  identical ones where it does not, and TUI's `paragraphAlignment`, which
//  works everywhere.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// Which declaration of `AttributedString.TextAlignment` an app sees (the owner's
// ruling attralign, 2026-11-19: "(a) but provide our own version anywhere that
// Core Text doesn't"). Measured with the stand-ins in
// `Tools/SwiftUIProbes/Paragraph attribute types (attralign)/`:
//
// - Apple's SDKs declare Core Text's (TUI builds against the macOS 26 SDK, and
//   no older one), and TUI uses it: one declaration, so naming it is never
//   ambiguous, and `string.alignment` wants macOS 26 as SwiftUI's does. The
//   `TUI` umbrella re-exports Core Text there, because a SwiftUI file built
//   with `MemberImportVisibility` names the type and its cases with
//   `import SwiftUI` alone (not this module: its importers would see Dispatch's
//   names where they see none today).
// - Linux, Windows and WebAssembly have no Core Text, so TUI declares Core
//   Text's names itself, with no availability: nothing else is named so there.
// - A stored property cannot be newer than its type, so with Core Text the
//   scope's `alignment` is a computed property, declared here; elsewhere it is
//   stored, in the scope (`AttributeScopes+SwiftUI.swift`). Foundation finds a
//   scope's keys through its stored properties, so with Core Text, coding with
//   `\.swiftUI`'s scope drops the alignment (not measured: it needs macOS 26):
//   Deliberate deviations from SwiftUI T14, approved by the owner's ruling
//   A-ATTRED-14 (2026-11-19).
#if canImport(CoreText)
    import CoreText

    extension AttributeScopes.SwiftUIAttributes {
        // Computed, never called: a key path to it names the key, and nothing
        // reads the value (an uninhabited key type has none to return).

        /// A property for accessing a paragraph's alignment — mirrors
        /// SwiftUI's, whose key and value are Core Text's
        /// (`AttributedString.TextAlignment`: `left`, `center`, `right`).
        ///
        /// Bounded by paragraphs: setting it on part of a paragraph sets it
        /// on the whole of it, and text typed into the paragraph takes it. A
        /// ``Text`` aligns each line of the paragraph within the text's own
        /// width (its widest line), as ``View/multilineTextAlignment(_:)``
        /// aligns all of them, and wins over that modifier for its own lines;
        /// a `TextEditor` aligns each row within the editor's width.
        ///
        /// macOS 26, as SwiftUI's: before it, set
        /// ``AttributeScopes/SwiftUIAttributes/paragraphAlignment`` instead,
        /// which TUI draws on every macOS.
        @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
        public var alignment: AttributeScopes.CoreTextAttributes.TextAlignmentAttribute {
            fatalError("a scope's attribute is named by its key path, never read")
        }
    }

    extension AttributeDynamicLookup {
        /// The ``AttributeScopes/SwiftUIAttributes/alignment`` attribute, as
        /// `string.alignment`.
        @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
        public subscript(
            dynamicMember keyPath: KeyPath<
                AttributeScopes.SwiftUIAttributes, AttributeScopes.CoreTextAttributes.TextAlignmentAttribute
            >
        ) -> AttributeScopes.CoreTextAttributes.TextAlignmentAttribute {
            self[AttributeScopes.CoreTextAttributes.TextAlignmentAttribute.self]
        }
    }
#else
    extension AttributeScopes {
        /// The namespace of the paragraph attributes SwiftUI's scope declares —
        /// mirrors Core Text's `AttributeScopes.CoreTextAttributes`, which
        /// TUI uses itself where there is Core Text (Apple's platforms).
        ///
        /// Not a scope of its own, as Core Text's is not: its keys are reached
        /// through ``SwiftUIAttributes``, as `string.alignment`.
        public struct CoreTextAttributes {}
    }

    extension AttributeScopes.CoreTextAttributes {
        /// The alignment of a paragraph's lines — mirrors Core Text's
        /// `TextAlignmentAttribute`.
        ///
        /// Bounded by paragraphs: setting it on part of a paragraph sets it on
        /// the whole of it, and text typed into the paragraph takes it.
        @frozen public enum TextAlignmentAttribute: CodableAttributedStringKey {
            public typealias Value = AttributedString.TextAlignment
            /// Not Core Text's own name, which its interface does not show.
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
        /// width (its widest line), as ``View/multilineTextAlignment(_:)``
        /// aligns all of them, and a paragraph's alignment wins over that
        /// modifier for its own lines. A `TextEditor` aligns each row of the
        /// paragraph within the editor's width. `left` and `right` are the
        /// sides of the screen, as Core Text's are, not a writing direction's
        /// leading and trailing.
        public enum TextAlignment: CaseIterable, Codable, Hashable, Sendable {
            case left
            case center
            case right
        }
    }

    extension AttributeDynamicLookup {
        /// The ``AttributeScopes/SwiftUIAttributes/alignment`` attribute, as
        /// `string.alignment`.
        public subscript(
            dynamicMember keyPath: KeyPath<
                AttributeScopes.SwiftUIAttributes, AttributeScopes.CoreTextAttributes.TextAlignmentAttribute
            >
        ) -> AttributeScopes.CoreTextAttributes.TextAlignmentAttribute {
            self[AttributeScopes.CoreTextAttributes.TextAlignmentAttribute.self]
        }
    }
#endif

extension AttributeScopes.SwiftUIAttributes {
    /// A paragraph's alignment, as TUI's ``TextAlignment`` — TUI's own
    /// attribute, which SwiftUI does not have.
    ///
    /// SwiftUI's `alignment` takes Core Text's `AttributedString.TextAlignment`,
    /// which on Apple platforms exists from macOS 26 only. This one works on
    /// every platform and every macOS, so an app that runs on macOS 15 can
    /// align a paragraph:
    ///
    /// ```swift
    /// var heading = AttributedString("Chapter One\n")
    /// heading.paragraphAlignment = .center
    /// ```
    ///
    /// It is drawn as `alignment` is: bounded by paragraphs, each line of a
    /// ``Text`` aligned within the text's width and winning over
    /// ``View/multilineTextAlignment(_:)``, each row of a `TextEditor`
    /// within the editor's. Where a paragraph states both, `alignment` wins.
    @frozen public enum ParagraphAlignmentAttribute: AttributedStringKey {
        public typealias Value = TextAlignment
        public static let name = "TUI.ParagraphAlignment"
        public static let runBoundaries: AttributedString.AttributeRunBoundaries? = .paragraph
    }
}

extension AttributeDynamicLookup {
    /// The ``AttributeScopes/SwiftUIAttributes/paragraphAlignment`` attribute,
    /// as `string.paragraphAlignment`.
    public subscript(
        dynamicMember keyPath: KeyPath<
            AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.ParagraphAlignmentAttribute
        >
    ) -> AttributeScopes.SwiftUIAttributes.ParagraphAlignmentAttribute {
        self[AttributeScopes.SwiftUIAttributes.ParagraphAlignmentAttribute.self]
    }
}

extension AttributedSubstring {
    /// The alignment this stretch's paragraph is drawn with: SwiftUI's
    /// `alignment` where the platform has it, else TUI's
    /// `paragraphAlignment`; `nil` where it states neither. Read off a
    /// substring rather than a `Runs.Run`, as `Text(AttributedString)` reads
    /// its attributes, since a program on Windows that uses `runs` does not
    /// link (`Documentation/Windows port.md`, "Toolchain").
    package var drawnParagraphAlignment: TextAlignment? {
        #if canImport(CoreText)
            if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *), let alignment = self.alignment {
                switch alignment {
                case .left: return .leading
                case .center: return .center
                case .right: return .trailing
                @unknown default: break
                }
            }
        #else
            if let alignment = self.alignment {
                switch alignment {
                case .left: return .leading
                case .center: return .center
                case .right: return .trailing
                }
            }
        #endif
        return self.paragraphAlignment
    }
}
