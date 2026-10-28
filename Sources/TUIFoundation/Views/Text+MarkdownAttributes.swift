//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+MarkdownAttributes.swift
//
//  The keys a `^[text](key: value, …)` in a `Text`'s key can style its text
//  with: one for each thing a `Text` modifier can do to a run of text, so all
//  of it is reachable from the key alone.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Text {
    /// This text with the inline Markdown `attributes` applied, each key as
    /// the `Text` modifier it names applies it.
    ///
    /// The keys, which SwiftUI's `Text` does not read — Foundation's parse
    /// keeps them for an attribute scope that declares them, and SwiftUI's
    /// declares none of these — are TUI's own (Deliberate deviations T3):
    ///
    /// | Key | Value | As |
    /// |---|---|---|
    /// | `foregroundColor` | a colour | ``foregroundStyle(_:)`` |
    /// | `backgroundColor` | a colour | an `AttributedString`'s `backgroundColor` |
    /// | `underlineStyle` | `true`, `false` or a pattern | ``underline(_:pattern:color:)`` |
    /// | `underlineColor` | a colour | its `color:` |
    /// | `strikethroughStyle` | `true`, `false` or a pattern | ``strikethrough(_:pattern:color:)`` |
    /// | `strikethroughColor` | a colour | its `color:` |
    /// | `font` | a ``Font/TextStyle`` name | ``font(_:)`` |
    /// | `fontWeight` | a ``FontWeight`` name | ``fontWeight(_:)`` |
    /// | `dim` | `true` or `false` | ``dim(_:)`` |
    /// | `blink` | `true` | ``blink()`` |
    /// | `inverse` | `true` | ``inverted()`` |
    /// | `textScale` | `secondary` or `default` | ``textScale(_:isEnabled:)`` |
    ///
    /// A colour is a name ``Color/named(_:)`` knows — `red`, `accentColor`,
    /// `palette.info`, `#f80` — and a pattern one of ``LineStyle/Pattern``'s:
    /// `solid`, `dot`, `dash`, `dashDot`, `dashDotDot`, `double`, `curly`. A
    /// colour alone for a line draws one, as `.underline(color: .red)` does.
    /// Any value may be quoted; `true` and `false` must not be, as in
    /// Foundation's decoding of a `Bool`.
    ///
    /// The first value of a key that reads is the one that holds, and an
    /// inner bracket's before an outer one's (``InlineMarkdown/Span/attributes``).
    /// A key TUI does not know — `inflect` — and a value it cannot read are
    /// passed over, and the text drawn as if they were not there.
    func applyingMarkdownAttributes(_ attributes: [InlineMarkdown.Attribute]) -> Text {
        var read = MarkdownAttributes()
        for attribute in attributes {
            read.read(attribute)
        }
        return read.applied(to: self)
    }
}

/// What one span's Markdown attributes say: for each key, the first value
/// that reads.
///
/// Gathered before any is applied, so the order they were written in does not
/// matter where their modifiers would interfere — a line's colour read before
/// its pattern would otherwise be cleared by it.
private struct MarkdownAttributes {
    typealias Value = InlineMarkdown.Attribute.Value

    var foregroundColor: Color?
    var backgroundColor: Color?
    var underline: Line?
    var strikethrough: Line?
    var font: Font?
    var fontWeight: FontWeight?
    var dim: Bool?
    var blink: Bool?
    var inverse: Bool?
    var textScale: Text.Scale?

    /// What a line's two keys say, each `nil` where its key did not.
    struct Line {
        var isActive: Bool?
        var pattern: Text.LineStyle.Pattern?
        var color: Color?
    }

    mutating func read(_ attribute: InlineMarkdown.Attribute) {
        let value = attribute.value
        switch attribute.key {
        case "foregroundColor": foregroundColor = foregroundColor ?? Self.color(value)
        case "backgroundColor": backgroundColor = backgroundColor ?? Self.color(value)
        case "underlineStyle": Self.readStyle(value, into: &underline)
        case "underlineColor": Self.readColor(value, into: &underline)
        case "strikethroughStyle": Self.readStyle(value, into: &strikethrough)
        case "strikethroughColor": Self.readColor(value, into: &strikethrough)
        case "font": font = font ?? Self.name(value).flatMap(Self.font)
        case "fontWeight": fontWeight = fontWeight ?? Self.name(value).flatMap(Self.weight)
        case "dim": dim = dim ?? Self.bool(value)
        case "blink": blink = blink ?? Self.bool(value)
        case "inverse": inverse = inverse ?? Self.bool(value)
        case "textScale": textScale = textScale ?? Self.name(value).flatMap(Self.scale)
        default: break
        }
    }

    /// `text` with what was read applied, through the modifiers the keys
    /// name. A weight before `dim`, as `.fontWeight(.bold).dim()` reads: the
    /// weight states `dim` too, and the key that says only that should win.
    @MainActor func applied(to text: Text) -> Text {
        var text = text
        if let font { text = text.font(font) }
        if let fontWeight { text = text.fontWeight(fontWeight) }
        if let dim { text = text.dim(dim) }
        if blink == true { text = text.blink() }
        if inverse == true { text = text.inverted() }
        if let textScale { text = text.textScale(textScale) }
        if let foregroundColor { text = text.foregroundStyle(foregroundColor) }
        // `Text` has no modifier for a run's background; this is what
        // `Text(AttributedString)` does with an `AttributedString`'s.
        if let backgroundColor { text.style.backgroundColor = backgroundColor }
        if let underline {
            text = text.underline(
                underline.isActive ?? true, pattern: underline.pattern ?? .solid, color: underline.color)
        }
        if let strikethrough {
            text = text.strikethrough(
                strikethrough.isActive ?? true, pattern: strikethrough.pattern ?? .solid, color: strikethrough.color)
        }
        return text
    }

    // MARK: Values

    /// `underlineStyle`'s or `strikethroughStyle`'s value into `line`, if
    /// that key has not already said: `true`, `false`, or a pattern, which
    /// turns the line on.
    private static func readStyle(_ value: Value, into line: inout Line?) {
        guard line?.isActive == nil else { return }
        if let isActive = bool(value) {
            line = Line(isActive: isActive, pattern: line?.pattern, color: line?.color)
        } else if let pattern = name(value).flatMap(Self.pattern) {
            line = Line(isActive: true, pattern: pattern, color: line?.color)
        }
    }

    /// `underlineColor`'s or `strikethroughColor`'s value into `line`, if
    /// that key has not already said.
    private static func readColor(_ value: Value, into line: inout Line?) {
        guard line?.color == nil, let color = color(value) else { return }
        line = Line(isActive: line?.isActive, pattern: line?.pattern, color: color)
    }

    /// A name, quoted or not.
    private static func name(_ value: Value) -> String? {
        switch value {
        case .string(let name), .word(let name): name
        }
    }

    /// An unquoted `true` or `false`.
    private static func bool(_ value: Value) -> Bool? {
        guard case .word(let word) = value else { return nil }
        switch word {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func color(_ value: Value) -> Color? {
        name(value).flatMap(Color.named)
    }

    private static func pattern(_ name: String) -> Text.LineStyle.Pattern? {
        switch name {
        case "solid": .solid
        case "dot": .dot
        case "dash": .dash
        case "dashDot": .dashDot
        case "dashDotDot": .dashDotDot
        case "double": .double
        case "curly": .curly
        default: nil
        }
    }

    private static func font(_ name: String) -> Font? {
        switch name {
        case "largeTitle": .largeTitle
        case "title": .title
        case "title2": .title2
        case "title3": .title3
        case "headline": .headline
        case "subheadline": .subheadline
        case "body": .body
        case "callout": .callout
        case "footnote": .footnote
        case "caption": .caption
        case "caption2": .caption2
        default: nil
        }
    }

    private static func weight(_ name: String) -> FontWeight? {
        switch name {
        case "ultraLight": .ultraLight
        case "thin": .thin
        case "light": .light
        case "regular": .regular
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        case "black": .black
        default: nil
        }
    }

    private static func scale(_ name: String) -> Text.Scale? {
        switch name {
        case "default": .default
        case "secondary": .secondary
        default: nil
        }
    }
}
