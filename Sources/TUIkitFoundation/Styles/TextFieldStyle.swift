//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Text Field Style

/// A style that customises the appearance of text-entry fields — SwiftUI's
/// `TextFieldStyle`, applied with ``TUIkit/View/textFieldStyle(_:)``.
///
/// TUIkit ships the two SwiftUI names a terminal can tell apart:
/// - ``DefaultTextFieldStyle`` (`.automatic`): the field draws itself — a
///   coloured surface with half-block caps for its rounded ends, so it reads
///   as a box you can type into even when it is empty.
/// - ``PlainTextFieldStyle`` (`.plain`): no surface and no caps. The text sits
///   on whatever is behind it, which is what an editable value inline in a
///   sentence or a row wants.
///
/// ```swift
/// TextField("Name", text: $name)             // a box
/// TextField("Name", text: $name)
///     .textFieldStyle(.plain)                // just the text
/// ```
///
/// Everything else about the field is unchanged: the caret, the selection, the
/// horizontal scroll, click-to-caret, and the suggestion drop-down all behave
/// the same either way.
///
/// SwiftUI's `.roundedBorder` and `.squareBorder` frame the field in a box,
/// drawn in box-drawing characters — rounded corners (`╭╮╰╯`) or square ones
/// (`┌┐└┘`) — around the plain field. A box is a row above and below in a
/// terminal, so a bordered field is three rows tall.
///
/// A protocol rather than an enum, matching SwiftUI and ``ListStyle`` beside it,
/// so a `where Self ==` extension gives the leading-dot spelling. SwiftUI's own
/// requirement is underscored and effectively closed; this one is a plain
/// readable property, so a caller *can* conform — the styles here are simply
/// the two the framework draws.
///
/// ## Styles and the render cache
///
/// ``TUIkit/View/textFieldStyle(_:)`` puts the style into the environment, and
/// the render cache keeps memoized subtrees honest by comparing each injected
/// value with the one applied there last frame. A value it cannot compare may
/// have changed under a buffer it is about to serve with nothing able to notice,
/// so every memo below one declines to cache at all — not the fields alone, but
/// everything under the modifier.
///
/// Both built-in styles are therefore `Equatable`. Neither holds anything, so
/// `==` within a type is vacuously true and every instance of one draws a field
/// identically. Between types it is the downcast in the comparison that answers,
/// which is what a field needs in both directions at once: the caps a style does
/// or does not draw are two cells of width as well as two glyphs, so a swap
/// changes what the field measures as much as what it paints, and must read as a
/// change.
///
/// A custom style need not conform — the paragraph above says a caller can write
/// one, and that stays true. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's text field styles declare no such conformance, and this is
///   one of the places a terminal renderer has to differ. SwiftUI diffs the view
///   graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUIkit re-runs `body` and compares values, so
///   here the question must be answerable.
public protocol TextFieldStyle: Sendable {
    /// Whether the field paints its own surface: the field-background colour
    /// behind the text, and the half-block caps at either end.
    ///
    /// `false` leaves the text on whatever is behind the field — deliberately
    /// no background at all rather than the palette's, so a plain field inside
    /// a tinted container picks up that container's tint the way ordinary text
    /// does.
    var drawsFieldSurface: Bool { get }

    /// The box the field is framed in, or `nil` for none.
    var fieldBorder: BorderStyle? { get }
}

extension TextFieldStyle {
    /// A style frames its field in nothing unless it says otherwise.
    public var fieldBorder: BorderStyle? { nil }
}
