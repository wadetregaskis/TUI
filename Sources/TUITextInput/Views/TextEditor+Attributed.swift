//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditor+Attributed.swift
//
//  `TextEditor(text:selection:)` over an `AttributedString` (G3 L4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

extension TextEditor {
    /// Creates a text editor over an attributed string — mirrors SwiftUI's
    /// `init(text:selection:)` for an `AttributedString`.
    ///
    /// ```swift
    /// @State private var text = AttributedString("Hello")
    /// @State private var selection = AttributedTextSelection()
    ///
    /// TextEditor(text: $text, selection: $selection)
    /// Button("Bold") {
    ///     text.transformAttributes(in: &selection) { $0.font = .body.bold() }
    /// }
    /// ```
    ///
    /// The text is drawn in its attributes as a ``Text`` of it draws them:
    /// foreground and background colour, a font's tier and weight as bold or
    /// faint (semibold and heavier bold, light and lighter faint), italic,
    /// underline and strikethrough, a link in the accent and underlined. What
    /// a cell cannot show — a font's size and family, kerning, tracking, a
    /// baseline offset — is not drawn. Disabled, the editor fades its runs'
    /// colours toward the page, keeping their hue, where SwiftUI's fades
    /// nothing: a deliberate deviation the owner approved on 2026-11-19
    /// (ruling A-DISED-1; see ``TextEditor``).
    ///
    /// The editor edits the value in place, so every character it does not
    /// touch keeps its attributes. Typed text takes the attributes macOS's
    /// text system gives it: those of the character before the caret, or of a
    /// paragraph's first character at its start, or of a selection's first
    /// character typed over; or those the app gave an insertion point with
    /// ``AttributedTextSelection/init(insertionPoint:typingAttributes:)``,
    /// until the caret moves. Undo brings back the attributes with the
    /// characters. The selection is written to `selection` as it moves, and a
    /// selection the app writes moves it; an editor selects one range, so a
    /// selection of several selects its first.
    ///
    /// **What a value the app writes costs.** The editor's own edits cost
    /// nothing to recognise when the binding hands them back. A value the app
    /// writes — after recolouring the text in `onChange`, or loading another —
    /// is taken whole, as it is in a `String` editor: its characters are read
    /// and compared with the editor's, about 0.2 ns a character (0.5 ms for a
    /// 2.4 MB text of 640,000 runs, measured on macOS 15.8.3), the text is laid
    /// out afresh if they changed, and the styles of the lines on screen are
    /// read again. Foundation gives no cheaper way to learn that only the
    /// attributes changed.
    ///
    /// **Bound to a stored property of an `@Observable` model, every key pays
    /// for a comparison.** The macro's setter compares the value written with
    /// the one before (`==`, so an equal write notifies no one), and
    /// `AttributedString`'s `==` reads two values a character at a time up to
    /// where they differ: for a key, up to the edit. Typing into a 40,000-line,
    /// 3.2 MB document, that was 98.7% of the time spent (Time Profiler,
    /// 2026-11-19); the editor's own work was hidden under it. A model that
    /// holds a large text can leave the check out for that one property by
    /// writing the accessors the macro would write, less the comparison:
    ///
    /// ```swift
    /// @Observable final class Document {
    ///     var text: AttributedString {
    ///         get { access(keyPath: \.text); return storedText }
    ///         set { withMutation(keyPath: \.text) { storedText = newValue } }
    ///     }
    ///     @ObservationIgnored private var storedText = AttributedString()
    /// }
    /// ```
    ///
    /// `access(keyPath:)` and `withMutation(keyPath:_:)` are what the macro
    /// adds to the class. A write then notifies the text's observers even when
    /// it is equal to the one before; a binding through `@Bindable` writes
    /// through the same setter, so it needs nothing else.
    ///
    /// SwiftUI's is macOS 26; TUI's is on every platform TUI is, with
    /// ``AttributedTextSelection``'s approximations on macOS 15.
    ///
    /// - Parameters:
    ///   - text: The attributed text to edit.
    ///   - selection: The current selection, or `nil` to keep it to the
    ///     editor.
    public init(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>? = nil) {
        self.init(text: Self.characters(of: text))
        attributed = AttributedTextBinding(text: text, selection: selection)
    }

    /// A binding over the characters of `text`'s value: what the editor's
    /// view reads before its handler has a source (the find bar's matches).
    /// Written, the characters it changes take the attributes typing there
    /// would.
    private static func characters(of text: Binding<AttributedString>) -> Binding<String> {
        Binding(
            get: { AttributedTextSource.characters(of: text.wrappedValue) },
            set: { AttributedTextSource(AttributedTextBinding(text: text, selection: nil)).write($0) })
    }
}
