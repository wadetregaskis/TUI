//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+Image.swift
//
//  An image as text: what `Text(_:)` and a key's interpolation put in a line.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Text {
    /// Creates an instance that wraps an `Image`, suitable for placing in a
    /// line with other text — mirrors SwiftUI's `Text(_:)` taking an image.
    ///
    /// A system symbol is a character in a terminal, so it becomes its glyph
    /// (`SFSymbol.glyph(named:)`, what `Image(systemName:)` draws), and the
    /// text styles it as it styles any other character. A picture cannot sit
    /// in a line of text, so it becomes an empty text. Both are what
    /// interpolating the image into a key gives:
    ///
    /// ```swift
    /// Text("\(Text(Image(systemName: "star.fill"))) Favourites")
    /// ```
    ///
    /// The glyph is the symbol's own, not a ``View/symbolVariant(_:)`` cut of
    /// it: the text is made here, before any environment is known.
    ///
    /// - Parameter image: The image to wrap.
    public init(_ image: Image) {
        self.init(verbatim: image.textGlyph)
    }
}

extension Image {
    /// What this image is in a line of text: a system symbol's glyph, or
    /// nothing for a picture (or a symbol with no glyph). `Text(_:)` and a
    /// key's interpolation of an image both read it, so the two agree.
    nonisolated package var textGlyph: String {
        guard case .symbol(let name) = content else { return "" }
        return SFSymbol.glyph(named: name) ?? ""
    }
}
