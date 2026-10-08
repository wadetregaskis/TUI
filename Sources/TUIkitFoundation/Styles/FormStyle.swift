//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - FormStyle

/// The appearance and layout of a ``Form``.
///
/// Set it with the ``View/formStyle(_:)`` modifier:
///
/// ```swift
/// Form {
///     LabeledContent("Name") { TextField("", text: $name) }
///     Toggle("Notifications", isOn: $notify)
/// }
/// .formStyle(.grouped)
/// ```
///
/// ## Built-in styles
///
/// | Style | Description |
/// |-------|-------------|
/// | ``automatic`` | Platform default — **columns** in TUIkit, the classic macOS form. |
/// | ``columns`` | Labels right-aligned to a shared pillar, controls left-aligned after it. |
/// | ``grouped`` | Each ``Section`` drawn as a bordered group with its title. |
///
/// ## Custom styles
///
/// Conform to `FormStyle` and implement ``makeBody(configuration:)``, laying out
/// `configuration.content` however you like.
///
/// ## Styles and the render cache
///
/// ``TUIkit/View/formStyle(_:)`` puts the style into the environment, and the
/// render cache keeps memoized subtrees honest by comparing each injected value
/// with the one applied there last frame. A value it cannot compare may have
/// changed under a buffer it is about to serve with nothing able to notice, so
/// every memo below one declines to cache at all — not the form alone, but
/// everything under the modifier, which for a form is usually a whole settings
/// panel.
///
/// All three built-in styles are therefore `Equatable`. None of them holds
/// anything, and they are pure markers: ``Form`` reads the style's TYPE and
/// nothing else, picking the grouped layout for ``GroupedFormStyle`` and the
/// columns layout for the other two. So `==` within a type is vacuously true and
/// two instances of one really do lay out the same form. Between types it is the
/// downcast in the comparison that answers, and a swap from grouped to columns
/// takes away the border the sections were drawn in.
///
/// The comparison is blunter than the presentation, and deliberately so.
/// ``AutomaticFormStyle`` and ``ColumnsFormStyle`` lay out identically —
/// `automatic` resolves to columns here — but a swap between them still compares
/// unequal and clears. That costs a redraw the frame did not need; the error runs
/// toward invalidating, never toward serving a stale buffer.
///
/// A custom style need not conform. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's form styles declare no such conformance, and this is one of
///   the places a terminal renderer has to differ. SwiftUI diffs the view graph
///   the compiler builds for it and never has to ask whether an environment
///   value changed; TUIkit re-runs `body` and compares values, so here the
///   question must be answerable.
public protocol FormStyle: Sendable {
    /// A view representing the form's body.
    associatedtype Body: View = EmptyView

    /// Creates a view that represents the body of a form.
    ///
    /// - Parameter configuration: The form's content.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a form.
    typealias Configuration = FormStyleConfiguration
}

/// The properties of a form, passed to a ``FormStyle``.
///
/// You don't create this — TUIkit builds one per ``Form`` and hands it to the
/// active style's ``FormStyle/makeBody(configuration:)``. Mirrors SwiftUI's
/// `FormStyleConfiguration`.
public struct FormStyleConfiguration {
    /// A type-erased content of a form.
    public typealias Content = AnyView

    /// A view that is the content of the form.
    public let content: Content
}
