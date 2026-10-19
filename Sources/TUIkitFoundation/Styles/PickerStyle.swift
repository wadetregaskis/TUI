//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - PickerStyle Protocol

/// The appearance and interaction style of a ``Picker``.
///
/// To configure the style for a single `Picker` or for every picker in a
/// view hierarchy, use the ``View/pickerStyle(_:)`` modifier.
///
/// ## Built-in Styles
///
/// | Style | Description |
/// |-------|-------------|
/// | ``automatic`` | Platform default — a drop-down menu in TUIkit. |
/// | ``menu`` | A collapsed control that opens a drop-down list. |
/// | ``inline`` | The options shown inline as a selectable list. |
/// | ``radioGroup`` | The options shown as a radio-button group. |
///
/// > Note: In TUIkit ``inline`` and ``radioGroup`` render identically — an
/// > inline list of radio options — because a terminal has no distinct
/// > inline-vs-grouped presentation. The separate styles exist so source
/// > written against SwiftUI keeps compiling. ``menu`` is genuinely
/// > different: it collapses to a single line and expands on demand.
///
/// ## Styles and the render cache
///
/// ``TUIkit/View/pickerStyle(_:)`` puts the style into the environment, and the
/// render cache keeps memoized subtrees honest by comparing each injected value
/// with the one applied there last frame. A value it cannot compare may have
/// changed under a buffer it is about to serve with nothing able to notice, so
/// every memo below one declines to cache at all — not the picker alone, but
/// everything under the modifier.
///
/// All four built-in styles are therefore `Equatable`. None of them holds
/// anything, and the only thing the framework ever reads off a style is
/// `resolvesToMenu`, which is a function of the type and of nothing else — so
/// `==` within a type is vacuously true and two instances of one really do draw
/// the same picker. Between types it is the downcast in the comparison that
/// answers, and a swap across the menu/inline divide changes a picker's height
/// as well as its glyphs: one collapsed line becomes a row per option.
///
/// The comparison is blunter than the presentation, and deliberately so.
/// ``DefaultPickerStyle`` and ``MenuPickerStyle`` draw identically, as do
/// ``InlinePickerStyle`` and ``RadioGroupPickerStyle``, but a swap within either
/// pair still compares unequal and clears. That costs a redraw the frame did not
/// need; the error runs toward invalidating, never toward serving a stale
/// buffer.
///
/// A custom style need not conform. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's picker styles declare no such conformance, and this is one
///   of the places a terminal renderer has to differ. SwiftUI diffs the view
///   graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUIkit re-runs `body` and compares values, so
///   here the question must be answerable.
public protocol PickerStyle: Sendable {}

// MARK: - Built-in Picker Styles

/// The default picker style, based on the picker's context: what
/// `PickerStyle.automatic` names, as in SwiftUI.
///
/// In TUIkit the default resolves to ``MenuPickerStyle`` — a collapsed
/// control that opens a drop-down list.
///
/// `Equatable` for the reason given under ``PickerStyle``: a memo below a value
/// the render cache cannot compare declines to cache.
public struct DefaultPickerStyle: PickerStyle, Equatable {
    /// Creates a default picker style.
    public init() {}
}

// MARK: - Environment Key

/// Environment key for the picker style.
private struct PickerStyleKey: EnvironmentKey {
    static let defaultValue: any PickerStyle = DefaultPickerStyle()
}

extension EnvironmentValues {
    /// The picker style for this environment.
    ///
    /// Controls how ``Picker`` views render. Set via the
    /// ``View/pickerStyle(_:)`` modifier. Default: ``DefaultPickerStyle``.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``PickerStyle``.
    public var pickerStyle: any PickerStyle {
        get { self[PickerStyleKey.self] }
        set { self[PickerStyleKey.self] = newValue }
    }
}
