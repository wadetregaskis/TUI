//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AttributeScopes+SwiftUI.swift
//
//  SwiftUI's attribute scope: the attributes an `AttributedString` can carry
//  for a `Text` to draw, under SwiftUI's names, so that
//  `string.foregroundColor = .red` compiles and means what it means there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension AttributeScopes {
    /// The attribute scope SwiftUI defines — mirrors SwiftUI's
    /// `AttributeScopes.swiftUI`.
    public var swiftUI: SwiftUIAttributes.Type { SwiftUIAttributes.self }

    /// The attributes a ``Text`` draws from an `AttributedString` — mirrors
    /// SwiftUI's `AttributeScopes.SwiftUIAttributes`.
    ///
    /// ```swift
    /// var status = AttributedString("FAILED")
    /// status.foregroundColor = .red
    /// status.font = .headline
    /// Text("Build \(Text(status))")
    /// ```
    ///
    /// Each of these has a cell to go in: a foreground and a background colour,
    /// a semantic font (which a terminal draws as an intensity — see ``Font``),
    /// and a single underline or strikethrough. Foundation's own attributes come
    /// along through ``foundation``, and a `Text` draws the `link` among them.
    ///
    /// SwiftUI's sub-cell typography is not here — `kern`, `tracking`,
    /// `baselineOffset`, the paragraph's `lineHeight` and `alignment`, and the
    /// `adaptiveImageGlyph` — so setting one fails to compile instead of being
    /// dropped on the way to the screen. Nor is `accessibility`: the
    /// Accessibility framework's scope does not exist on Linux.
    ///
    /// > Important: On macOS, SwiftUI's scope of the same name is visible to
    /// > an app too, because TUIkit imports AppKit and AppKit loads SwiftUICore.
    /// > Setting an attribute picks this scope (`AttributeDynamicLookup`'s
    /// > subscripts here are more specific than SwiftUI's), but spelling the
    /// > scope's NAME in a type position — `let k: AttributeScopes.SwiftUIAttributes.FontAttribute.Type`
    /// > — is ambiguous there, and an attribute only SwiftUI has, such as
    /// > `kern`, compiles and then fails to link. Linux has neither problem.
    public struct SwiftUIAttributes: AttributeScope {
        /// A property for accessing a font attribute.
        public let font: FontAttribute

        /// A property for accessing a foreground color attribute.
        public let foregroundColor: ForegroundColorAttribute

        /// A property for accessing a background color attribute.
        public let backgroundColor: BackgroundColorAttribute

        /// A property for accessing a strikethrough style attribute.
        public let strikethroughStyle: StrikethroughStyleAttribute

        /// A property for accessing an underline style attribute.
        public let underlineStyle: UnderlineStyleAttribute

        /// A property for accessing attributes defined by the Foundation
        /// framework. Of those, a ``Text`` draws `link` (and, where
        /// Foundation has it, `inlinePresentationIntent`); see
        /// ``Text/init(_:)-(AttributedString)``.
        public let foundation: FoundationAttributes

        public typealias DecodingConfiguration = AttributeScopeCodableConfiguration
        public typealias EncodingConfiguration = AttributeScopeCodableConfiguration
    }
}

extension AttributeScopes.SwiftUIAttributes {
    /// The semantic font of a run of text.
    @frozen public enum FontAttribute: AttributedStringKey {
        public typealias Value = Font
        public static let name = "SwiftUI.Font"
    }

    /// The colour of a run of text.
    @frozen public enum ForegroundColorAttribute: AttributedStringKey {
        public typealias Value = Color
        public static let name = "SwiftUI.ForegroundColor"
    }

    /// The colour behind a run of text.
    @frozen public enum BackgroundColorAttribute: AttributedStringKey {
        public typealias Value = Color
        public static let name = "SwiftUI.BackgroundColor"
    }

    /// The line through a run of text.
    @frozen public enum StrikethroughStyleAttribute: AttributedStringKey {
        public typealias Value = Text.LineStyle
        public static let name = "SwiftUI.StrikethroughStyle"
    }

    /// The line under a run of text.
    @frozen public enum UnderlineStyleAttribute: AttributedStringKey {
        public typealias Value = Text.LineStyle
        public static let name = "SwiftUI.UnderlineStyle"
    }
}

// One subscript per attribute rather than SwiftUI's single generic one, and
// that is load-bearing on macOS: SwiftUICore declares the generic one over ITS
// scope and it is visible to an app there (see the note on the scope). Two
// generic subscripts tie, and `string.foregroundColor = .red` would be
// ambiguous; a concrete one is more specific than a generic one, so these win
// — measured against a module that imports AppKit, as TUIkit does. AppKit's own
// subscript is `@_disfavoredOverload`, which is how SwiftUI's beats it.
extension AttributeDynamicLookup {
    /// The ``AttributeScopes/SwiftUIAttributes/font`` attribute, as
    /// `string.font`.
    public subscript(
        dynamicMember keyPath: KeyPath<AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.FontAttribute>
    ) -> AttributeScopes.SwiftUIAttributes.FontAttribute {
        self[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
    }

    /// The ``AttributeScopes/SwiftUIAttributes/foregroundColor`` attribute, as
    /// `string.foregroundColor`.
    public subscript(
        dynamicMember keyPath: KeyPath<
            AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        >
    ) -> AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute {
        self[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self]
    }

    /// The ``AttributeScopes/SwiftUIAttributes/backgroundColor`` attribute, as
    /// `string.backgroundColor`.
    public subscript(
        dynamicMember keyPath: KeyPath<
            AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
        >
    ) -> AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute {
        self[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self]
    }

    /// The ``AttributeScopes/SwiftUIAttributes/strikethroughStyle`` attribute,
    /// as `string.strikethroughStyle`.
    public subscript(
        dynamicMember keyPath: KeyPath<
            AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute
        >
    ) -> AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute {
        self[AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self]
    }

    /// The ``AttributeScopes/SwiftUIAttributes/underlineStyle`` attribute, as
    /// `string.underlineStyle`.
    public subscript(
        dynamicMember keyPath: KeyPath<
            AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
        >
    ) -> AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute {
        self[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self]
    }
}
