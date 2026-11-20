//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorMarks.swift
//
//  `TextEditorMark` and `.textEditorMarks(_:in:)`: ranges of a TextEditor's
//  text an app styles, such as a parse error, stated with the text they were
//  computed from (the highlighting design's B-ATTRED-13, lane H3 of its
//  §8.6). Under `@_spi(TextEditorHighlighting)` until lane H4′ makes them
//  public.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// TUI-specific. A range of a ``TextEditor``'s text drawn in attributes of
/// its own, over the text and never written into it: a parse error's curly
/// underline, a search result, a diagnostic.
///
/// Given to the editors in a view with ``View/textEditorMarks(_:in:)``,
/// with the text its range is of.
///
/// SwiftUI has nothing like it; this is TUI's own, and while it is `@_spi`,
/// it may change in any release.
@_spi(TextEditorHighlighting)
public struct TextEditorMark: Equatable, Sendable {
    /// The range marked, in the text the marks are stated with.
    public var range: Range<String.Index>
    /// What the range is drawn in: colours, bold, faint and italic,
    /// underline and strikethrough, as an attributed editor draws its own.
    public var attributes: AttributeContainer

    /// A mark of `range` drawn in `attributes`.
    public init(_ range: Range<String.Index>, attributes: AttributeContainer) {
        self.range = range
        self.attributes = attributes
    }
}

@_spi(TextEditorHighlighting)
extension View {
    /// TUI-specific. Draws `marks`, ranges of `text`, over the text of the
    /// ``TextEditor``s in this view: over its highlighting and its own
    /// attributes, under the selection and the find bar's matches. Where two
    /// marks overlap, the later is drawn over the earlier.
    ///
    /// `text` is the text the ranges were found in, which may be a few of the
    /// editor's edits old: an app's parse can lag the editor by a key or more.
    /// The editor carries the marks through its own edits since, so text
    /// typed after a mark moves it, text typed inside it grows it, and a mark
    /// whose text was deleted goes. Marks of a text the editor does not know
    /// (one it was not given, or more than a few of its edits old) are not
    /// drawn until they are stated again, rather than drawn in the wrong place.
    ///
    /// SwiftUI has nothing like it; this is TUI's own, and while it is
    /// `@_spi`, it may change in any release.
    ///
    /// - Parameters:
    ///   - marks: The ranges to draw, and what to draw them in.
    ///   - text: The text whose ranges they are.
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
