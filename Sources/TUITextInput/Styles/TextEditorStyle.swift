//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorStyle.swift
//
//  SwiftUI's text editor styles: `.automatic`, the editor on its field
//  surface, and `.plain`, its text on whatever is behind it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The properties of a text editor.
///
/// SwiftUI's configuration has no public members, and neither has this one: a
/// custom style draws what its body returns in the editor's place.
public struct TextEditorStyleConfiguration {}

/// A specification for the appearance and interaction of a text editor.
public protocol TextEditorStyle: Sendable {
    /// A view that represents the body of a text editor.
    associatedtype Body: View

    /// Creates a view that represents the body of a text editor.
    ///
    /// - Parameter configuration: The properties of the text editor.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a text editor.
    typealias Configuration = TextEditorStyleConfiguration
}

extension TextEditorStyle {
    /// This style's body, type-erased — opening the existential the
    /// environment holds.
    @MainActor
    func makeAnyBody(configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default text editor style: the editor on the palette's field surface,
/// so it reads as a place to type.
public struct AutomaticTextEditorStyle: TextEditorStyle, Equatable {
    /// Creates the automatic text editor style.
    public init() {}

    /// Drawn by the editor itself; a built-in style's body is never asked for.
    public func makeBody(configuration: Configuration) -> some View {
        EmptyView()
    }
}

/// A text editor style with no decoration: the text on whatever is behind the
/// editor, with no field surface of its own.
public struct PlainTextEditorStyle: TextEditorStyle, Equatable {
    /// Creates the plain text editor style.
    public init() {}

    /// Drawn by the editor itself; a built-in style's body is never asked for.
    public func makeBody(configuration: Configuration) -> some View {
        EmptyView()
    }
}

extension TextEditorStyle where Self == AutomaticTextEditorStyle {
    /// The default text editor style.
    public static var automatic: AutomaticTextEditorStyle { AutomaticTextEditorStyle() }
}

extension TextEditorStyle where Self == PlainTextEditorStyle {
    /// A text editor style with no decoration.
    public static var plain: PlainTextEditorStyle { PlainTextEditorStyle() }
}

private struct TextEditorStyleKey: EnvironmentKey {
    static let defaultValue: any TextEditorStyle = AutomaticTextEditorStyle()
}

extension EnvironmentValues {
    /// The style text editors in this environment draw with.
    var textEditorStyle: any TextEditorStyle {
        get { self[TextEditorStyleKey.self] }
        set { self[TextEditorStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for text editors within this view.
    ///
    /// - Parameter style: The style to apply.
    /// - Returns: A view whose text editors use `style`.
    nonisolated public func textEditorStyle<S: TextEditorStyle>(_ style: S) -> some View {
        environment(\.textEditorStyle, style)
    }
}
