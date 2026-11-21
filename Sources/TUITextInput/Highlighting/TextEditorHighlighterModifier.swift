//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlighterModifier.swift
//
//  `.textEditorHighlighter(_:style:)`: a highlighter given to the editors
//  below, through the environment, and what an editor needs of it to start
//  it, whatever its tokens' type (the highlighting design's §8.1, lane H6′).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

@_spi(TextEditorHighlighting)
extension View {
    /// TUI-specific. Highlights the text of the ``TextEditor``s in this view
    /// with `highlighter`, each token drawn in the attributes `style` gives
    /// it: over the text, never written into it, under the app's marks
    /// (`textEditorMarks(_:in:)`), the selection and the find bar's matches.
    ///
    /// `style` is asked once for each distinct token, on the main actor, and
    /// the attributes it gives are drawn as an attributed editor draws its
    /// own: colours, bold, faint and italic, underline and strikethrough. A
    /// palette change draws them again without asking. It is the `style` the
    /// highlighter started with that is asked: the editor keeps a highlighter
    /// running across its body's evaluations (``TextEditorHighlighter``).
    ///
    /// ```swift
    /// @_spi(TextEditorHighlighting) import TUITextInput
    ///
    /// TextEditor(text: $source)
    ///     .textEditorHighlighter(MyTreeSitterHighlighter(language: .json)) { token in
    ///         theme.attributes(for: token)
    ///     }
    /// ```
    ///
    /// SwiftUI has no highlighting for its text editor; this is TUI's own.
    /// It is SPI, outside the API stability policy, until it is made public
    /// (``TextEditorHighlighter`` says when): it may change in any release,
    /// minor ones included.
    ///
    /// - Parameters:
    ///   - highlighter: What styles the text, in a task of its own.
    ///   - maximumLineLength: The longest line styled, in UTF-8 bytes; a
    ///     longer one is drawn unstyled (B-ATTRED-15).
    ///   - style: A token's attributes.
    nonisolated public func textEditorHighlighter<Highlighter: TextEditorHighlighter>(
        _ highlighter: Highlighter, maximumLineLength: Int = 20_000,
        style: @escaping @MainActor (Highlighter.Token) -> AttributeContainer
    ) -> some View {
        environment(
            \.textEditorHighlighting,
            EditorHighlighting(highlighter, maximumLineLength: maximumLineLength, style: style))
    }
}

// MARK: - The environment's value

private struct TextEditorHighlightingKey: EnvironmentKey {
    static var defaultValue: EditorHighlighting? { nil }
}

extension EnvironmentValues {
    /// The highlighter the editors below draw with, or `nil` for none.
    var textEditorHighlighting: EditorHighlighting? {
        get { self[TextEditorHighlightingKey.self] }
        set { self[TextEditorHighlightingKey.self] = newValue }
    }
}

/// A highlighter as an editor starts it, whatever its tokens' type: which one
/// it is, and how to make its session and its work.
struct EditorHighlighting {
    let key: EditorHighlighterKey
    let maximumLineLength: Int
    /// The session over a text of so many lines, which asks for frames
    /// through the closure given, and the highlighter's work on it.
    let start: (_ text: String, _ lineCount: Int, _ requestFrame: @escaping @Sendable () -> Void) -> Started

    /// A highlighter started: its session, the work to run, and each style
    /// index's attributes.
    struct Started {
        let feed: any EditorHighlightFeed
        let work: @Sendable () async -> Void
        let style: @MainActor (UInt16) -> AttributeContainer
    }

    init<Highlighter: TextEditorHighlighter>(
        _ highlighter: Highlighter, maximumLineLength: Int,
        style: @escaping @MainActor (Highlighter.Token) -> AttributeContainer
    ) {
        key = EditorHighlighterKey(highlighter)
        self.maximumLineLength = maximumLineLength
        start = { text, lineCount, requestFrame in
            let session = TextEditorHighlightSession<Highlighter.Token>(
                text: text, lineCount: lineCount, maximumLineLength: maximumLineLength, requestFrame: requestFrame)
            return Started(
                feed: session, work: { await session.run(highlighter) },
                style: { index in
                    guard let token = session.token(index) else { return AttributeContainer() }
                    return style(token)
                })
        }
    }
}

/// Which highlighter a value is (B-ATTRED-25): two of one type are one,
/// unless the type is `Equatable` and they are unequal, as `.task(id:)`
/// restarts only for a new id. Otherwise each body evaluation, which makes
/// the value anew, would start highlighting again.
struct EditorHighlighterKey {
    let type: ObjectIdentifier
    let value: (any Equatable)?

    init<Highlighter: TextEditorHighlighter>(_ highlighter: Highlighter) {
        type = ObjectIdentifier(Highlighter.self)
        value = highlighter as? any Equatable
    }

    /// Whether `other` is the same highlighter.
    func isSame(as other: Self) -> Bool {
        guard type == other.type else { return false }
        guard let value, let otherValue = other.value else { return true }
        return Self.equal(value, otherValue)
    }

    private static func equal<Value: Equatable>(_ value: Value, _ other: any Equatable) -> Bool {
        (other as? Value) == value
    }
}
