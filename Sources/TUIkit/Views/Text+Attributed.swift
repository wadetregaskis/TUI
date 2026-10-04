//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+Attributed.swift
//
//  `Text(AttributedString)`: an attributed string's runs as a `Text`'s runs,
//  each with the attributes a terminal cell can carry.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Text {
    /// Creates a text view that displays styled attributed content — mirrors
    /// SwiftUI's `init(_:)` for an `AttributedString`.
    ///
    /// ```swift
    /// var content = AttributedString("Blue text")
    /// content.foregroundColor = .blue
    /// Text(content)
    /// ```
    ///
    /// Each run of the string becomes a run of this text, drawn with the
    /// attributes of ``Foundation/AttributeScopes/SwiftUIAttributes``:
    /// foreground and background colour, semantic font, and a single underline
    /// or strikethrough. Where Foundation has `inlinePresentationIntent` (on
    /// Apple platforms), its strong emphasis draws bold, its emphasis italic and
    /// its strikethrough struck through, so a string parsed from Markdown there
    /// draws as it does in SwiftUI; its code spans are already monospaced.
    /// Every other attribute is ignored, as SwiftUI ignores them.
    ///
    /// The string's attributes take precedence over the text's modifiers, which
    /// is SwiftUI's rule: in
    ///
    /// ```swift
    /// Text(content).foregroundStyle(.red)
    /// ```
    ///
    /// the runs that state a colour keep it and the rest are red. A modifier
    /// combines with the attributes it does not contradict — `.italic()` on a
    /// bold run makes it bold italic — and cannot take back one the string
    /// states: `.bold(false)` leaves a bold run bold. The result is one text,
    /// as a concatenation is: it wraps, truncates and measures as a whole.
    ///
    /// - Parameter attributedContent: An attributed string to style and
    ///   display, in accordance with its attributes.
    ///
    /// - Note: `@_disfavoredOverload`, as SwiftUI declares it: an
    ///   `AttributedString` is expressible by a string literal too, so without
    ///   it `Text("")` would be ambiguous between this and
    ///   ``init(_:)-(LocalizedStringKey)`` — and a literal must stay a key.
    @_disfavoredOverload
    public init(_ attributedContent: AttributedString) {
        self.init(verbatim: String(attributedContent.characters))
        let runs = Self.runs(of: attributedContent)
        // A string with nothing to say about its one run is a plain text, and
        // takes a plain text's path: no runs at all.
        if runs.count > 1 || runs.first.map({ $0.style != TextStyle() }) == true {
            self.runs = runs
        }
    }

    /// The runs of `string`, neighbours drawn alike merged into one.
    static func runs(of string: AttributedString) -> [Run] {
        var result: [Run] = []
        for run in string.runs {
            let text = String(string[run.range].characters)
            guard !text.isEmpty else { continue }
            let style = Self.style(of: run)
            if let last = result.last, last.style == style, last.live == nil {
                result[result.count - 1] = Run(text: last.text + text, style: style)
            } else {
                result.append(Run(text: text, style: style))
            }
        }
        return result
    }

    /// What `run` states, as a run's own style: only what it states, so the
    /// text's modifiers and the environment fill in the rest.
    private static func style(of run: AttributedString.Runs.Run) -> TextStyle {
        var style = TextStyle()
        if let color = run.foregroundColor {
            style.foregroundColor = color
        }
        if let color = run.backgroundColor {
            style.backgroundColor = color
        }
        if let font = run.font {
            style.font = .some(font)
        }
        if run.underlineStyle != nil {
            style.isUnderlined = true
        }
        if run.strikethroughStyle != nil {
            style.isStrikethrough = true
        }
        // `InlinePresentationIntent` is Darwin Foundation's: swift-foundation
        // has neither it nor the Markdown initializer that sets it (checked on
        // the 6.3.3 static Linux SDK), so on Linux there is nothing to read.
        #if canImport(Darwin)
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { style.isBold = true }
                if intent.contains(.emphasized) { style.isItalic = true }
                if intent.contains(.strikethrough) { style.isStrikethrough = true }
            }
        #endif
        return style
    }
}
