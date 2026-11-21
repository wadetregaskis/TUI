//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorMarks.swift
//
//  `TextEditorMark` and `.textEditorMarks(_:in:)`: ranges of a TextEditor's
//  text an app styles, such as a parse error, stated with the text they were
//  computed from (the highlighting design's B-ATTRED-13, lane H3 of its
//  §8.6). Public since lane H4′ (B-ATTRED-51, 52); the highlighting seam
//  beside them stays `@_spi(TextEditorHighlighting)` (A-ATTRED-10).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// TUI-specific. A range of a ``TextEditor``'s text drawn in attributes of
/// its own, over the text and never written into it: a parse error's curly
/// underline, a search result, a diagnostic.
///
/// Give marks to the editors in a view with ``View/textEditorMarks(_:in:)``,
/// with the text their ranges are of:
///
/// ```swift
/// var error = AttributeContainer()
/// error.underlineStyle = Text.LineStyle(pattern: .curly, color: .red)
///
/// TextEditor(text: $source)
///     .textEditorMarks(problems.map { TextEditorMark($0.range, attributes: error) }, in: parsed)
/// ```
///
/// SwiftUI has no marks for its text editor; this is TUI's own.
public struct TextEditorMark: Equatable, Sendable {
    /// The range marked, in the text the marks are stated with.
    public var range: Range<String.Index>
    /// What the range is drawn in: colours, bold, faint and italic,
    /// underline and strikethrough, as an attributed editor draws its own.
    /// What it leaves unset is the text's own, or its highlighting's.
    public var attributes: AttributeContainer

    /// A mark of `range` drawn in `attributes`.
    ///
    /// - Parameters:
    ///   - range: The range to mark, of the text the marks are stated with.
    ///   - attributes: What to draw the range in.
    public init(_ range: Range<String.Index>, attributes: AttributeContainer) {
        self.range = range
        self.attributes = attributes
    }
}

extension View {
    /// TUI-specific. Draws `marks`, ranges of `text`, over the text of the
    /// ``TextEditor``s in this view: over its highlighting and its own
    /// attributes, under the selection and the find bar's matches. Where two
    /// marks overlap, the later is drawn over the earlier. An editor draws
    /// the innermost `textEditorMarks` it is under, as for any environment
    /// value.
    ///
    /// `text` is the text the ranges were found in, which may be a few of the
    /// editor's edits old: an app's parse can lag the editor by a key or more.
    /// The editor carries the marks through its own edits since: text typed
    /// before a mark moves it, text typed inside it grows it, text typed at
    /// either of its ends stays outside it, and a mark whose text was deleted
    /// goes. Marks of a text the editor does not know (one it was not
    /// given, one more than a few of its edits old, or one from before an
    /// undo, a redo or a Replace All, which write the text whole) are not
    /// drawn until they are stated again, rather than drawn in the wrong
    /// place. Stating the same marks of the same text again, as
    /// each evaluation of a body does, is cheap: they are compared, not
    /// carried again.
    ///
    /// ```swift
    /// TextEditor(text: $source)
    ///     .textEditorMarks(marks, in: parsedSource)
    /// ```
    ///
    /// For an editor over an `AttributedString`, the ranges are of its
    /// characters as a `String`, `String(value.characters)`: the text a parse
    /// reads. A range of no length draws nothing; to mark a point, mark the
    /// character there.
    ///
    /// SwiftUI has no marks for its text editor; this is TUI's own.
    ///
    /// - Parameters:
    ///   - marks: The ranges to draw, and what to draw them in.
    ///   - text: The text whose ranges they are.
    /// - Returns: A view whose editors draw the marks.
    nonisolated public func textEditorMarks(_ marks: [TextEditorMark], in text: String) -> some View {
        environment(
            \.textEditorMarks,
            EditorMarkStatement(text: text, ranges: marks.map(\.range), attributes: marks.map(\.attributes)))
    }
}

// MARK: - The environment's value

private struct TextEditorMarksKey: EnvironmentKey {
    static var defaultValue: EditorMarkStatement? { nil }
}

extension EnvironmentValues {
    /// The app's marks the editors below draw, with their text, or `nil`
    /// for none.
    var textEditorMarks: EditorMarkStatement? {
        get { self[TextEditorMarksKey.self] }
        set { self[TextEditorMarksKey.self] = newValue }
    }
}
