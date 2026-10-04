//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Font+Resolved.swift
//
//  SwiftUI's resolved font: what a semantic font turns into in an
//  environment, which here is what the style cascade makes of it.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Font {
    /// The context a font resolves in — mirrors SwiftUI's `Font.Context`.
    ///
    /// A font is a late-binding token: `.headline` is bold by default, but a
    /// theme's `.style(.font(.headline))` can make it anything. The context is
    /// the style cascade in effect, read from
    /// ``EnvironmentValues/fontResolutionContext``.
    public struct Context: Hashable, Sendable, CustomDebugStringConvertible {
        let cascade: StyleCascade

        public var debugDescription: String {
            "Font.Context(\(cascade))"
        }
    }

    /// A font resolved in a context — mirrors SwiftUI's `Font.Resolved`.
    ///
    /// Holds what a terminal's one face can vary: weight (as bold, faint or
    /// neither) and italic. The face is always monospaced and never in small
    /// capitals. SwiftUI's point size, width, leading and `ctFont` describe
    /// metrics a cell grid does not have, so they are absent and fail to
    /// compile.
    public struct Resolved: Hashable, Sendable {
        /// Whether the font is bold.
        public let isBold: Bool

        /// Whether the font is italic.
        public let isItalic: Bool

        /// Whether the font is monospaced — always, in a terminal.
        public let isMonospaced: Bool

        /// Whether the font draws lowercase letters as small capitals — never.
        public let isLowercaseSmallCaps: Bool

        /// Whether the font draws uppercase letters as small capitals — never.
        public let isUppercaseSmallCaps: Bool

        /// Whether the font draws in small capitals — never.
        public let isSmallCaps: Bool

        /// The weight: the one the font named, else what its emphasis reads as
        /// (bold, light for faint text, or regular).
        public let weight: Font.Weight
    }

    /// Evaluates this font to a resolved font given the current context —
    /// mirrors SwiftUI's `resolve(in:)`.
    ///
    /// The attributes are the ones a ``Text`` in this font draws with: the
    /// style cascade's entries for `.all`, `.text` and this font's style, over
    /// the font's own baseline.
    ///
    /// - Parameter context: The context, from
    ///   ``EnvironmentValues/fontResolutionContext``.
    /// - Returns: The resolved font.
    public func resolve(in context: Context) -> Resolved {
        let attributes = context.cascade.resolve(for: [.all, .text, .font(textStyle)])
            .merged(over: defaultAttributes)
        let isBold = attributes.bold == true
        let isFaint = attributes.dim == true
        // The weight the font named, while the cascade left it drawn as that
        // weight draws; else what the drawing reads as.
        let named = weight.flatMap { named in
            named.styleAttributes.bold == isBold && named.styleAttributes.dim == isFaint ? named : nil
        }
        let drawn: Font.Weight = isBold ? .bold : (isFaint ? .light : .regular)
        return Resolved(
            isBold: isBold, isItalic: attributes.italic == true, isMonospaced: true,
            isLowercaseSmallCaps: false, isUppercaseSmallCaps: false, isSmallCaps: false,
            weight: named ?? drawn)
    }
}

extension EnvironmentValues {
    /// The context fonts resolve in here — mirrors SwiftUI's
    /// `fontResolutionContext`. See ``Font/resolve(in:)``.
    public var fontResolutionContext: Font.Context {
        Font.Context(cascade: styleCascade)
    }
}
