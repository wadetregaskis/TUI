//  🖥️ TUI — A Terminal UI framework for Swift
//  TextInputSuggestions+Words.swift
//
//  What a suggestion with no `textInputCompletion` fills its field with: its
//  label's words, as written.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The words a suggestion with no ``View/textInputCompletion(_:)`` fills its
/// field with: its label's words, as written — not as the menu draws them.
///
/// SwiftUI shows such a suggestion but leaves it inert; TUI makes it pickable,
/// with these words as its completion (Deliberate deviations T16, the owner's
/// ruling H39-DEFAULT (a), 2026-11-23).
///
/// A `Text` — behind any modifiers written on it, a memoised `ForEach` row, an
/// `AnyView` or a `Label`, whose title it is — gives its words straight
/// (``Text/reading(in:)``, so a key reads in the language the subtree names):
/// nothing is drawn, so no width cuts them, no line limit drops a line, and
/// neither `.textCase` nor a redaction changes them. Anything else is drawn
/// for them at its ideal width, with no line limit, case transform or
/// redaction from the subtree, and spelled as written rather than in ASCII
/// (`TUI_PLAIN_TEXT=transliterate`); its rows, joined by newlines, are the
/// words. Drawn whole, at the identity the menu draws it at, so a view of the
/// app's own keeps one `@State` for both.
///
/// The menu's rows were the completion before (hunt H-39): the label drawn at
/// the screen's width and the field's height, its first row, so a long or
/// wrapped label wrote cut text to the binding.
///
/// - Parameters:
///   - label: The suggestion as the menu draws it.
///   - context: The context the menu draws its labels in.
/// - Returns: The text picking the suggestion fills the field with.
@MainActor
func suggestionWords(of label: AnyView, in context: RenderContext) -> String {
    var current: any View = label
    var reached = context
    while true {
        if let text = current as? Text {
            return text.reading(in: reached).content
        }
        if let titled = current as? any LabelTitled {
            current = titled.labelTitle
        } else if let wrapper = current as? any SingleContentWrapper {
            // Under what the wrapper publishes to its content, as it lays the
            // content out: an `.environment(\.locale, …)` on the label names
            // the language its key reads in.
            reached = wrapper.wrappedContentContext(reached) ?? reached
            current = wrapper.wrappedContent
        } else if let row = current as? any _ValueMemoWrapping {
            // A `ForEach` row of an equatable element, memoized — as
            // `alertActions(from:in:)` looks through it to a button.
            current = row.memoizedContent
        } else if let erased = current as? AnyView {
            current = erased.erasedView
        } else if let member = current as? Subview {
            current = member.memberView
        } else {
            return drawnWords(of: label, in: context)
        }
    }
}

/// `label`'s words as drawn at its ideal size, free of what the subtree above
/// does to text: see ``suggestionWords(of:in:)``.
///
/// `context` is the menu's label context, not the one the walk reached:
/// `label` is drawn whole, its own modifiers included.
@MainActor
private func drawnWords(of label: AnyView, in context: RenderContext) -> String {
    var words = context
    words.environment.lineLimit = .unlimited
    words.environment.textCase = nil
    words.environment.redactionReasons = []
    words.textSpelling = .asWritten
    // Offered no size, a text answers within the width available, so the
    // space available is made wide too: 4096 cells, wider than any completion
    // and small enough that a view filling what it is offered draws no vast
    // buffer for its words.
    let bound = 1 << 12
    words = words.withAvailableSize(width: bound, height: bound)
    let size = label.sizeThatFits(proposal: .unspecified, context: words)
    let buffer = label.renderToBuffer(
        context: words.withAvailableSize(width: min(size.width, bound), height: min(size.height, bound)))
    return buffer.lines.map { line in
        var row = line.stripped
        while row.last == " " { row.removeLast() }
        return row
    }.joined(separator: "\n")
}
