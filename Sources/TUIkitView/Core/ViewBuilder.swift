//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewBuilder.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

/// A result builder for View hierarchies.
///
/// The `@ViewBuilder` enables a declarative syntax similar to SwiftUI:
///
/// ```swift
/// VStack {
///     Text("Line 1")
///     Text("Line 2")
///     if showMore {
///         Text("Line 3")
///     }
/// }
/// ```
///
/// The builder supports:
/// - Single views
/// - Multiple views (unlimited, via Parameter Packs)
/// - Conditionals (`if`, `if-else`)
/// - Optional views (`if let`)
/// - Arrays of views (`for-in`)
@MainActor
@resultBuilder
public struct ViewBuilder {

    // MARK: - No View

    /// Builds an empty view from an empty closure, as SwiftUI does — rather
    /// than the zero-element ``TupleView`` the parameter-pack overload below
    /// would otherwise produce for it.
    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    // MARK: - Single View

    /// Builds a single view.
    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }

    // MARK: - Multiple Views (Parameter Pack)

    /// Builds multiple views into a TupleView using Swift Parameter Packs.
    ///
    /// This single overload replaces the previous 9 arity-specific `buildBlock`
    /// overloads (`TupleView2` through `TupleView10`), removing the 10-child limit.
    public static func buildBlock<each C: View>(
        _ content: repeat each C
    ) -> TupleView<repeat each C> {
        TupleView(repeat each content)
    }

    // MARK: - Conditionals

    /// Supports the true branch of an if-else.
    public static func buildEither<TrueContent: View, FalseContent: View>(
        first content: TrueContent
    ) -> ConditionalView<TrueContent, FalseContent> {
        .trueContent(content)
    }

    /// Supports the false branch of an if-else.
    public static func buildEither<TrueContent: View, FalseContent: View>(
        second content: FalseContent
    ) -> ConditionalView<TrueContent, FalseContent> {
        .falseContent(content)
    }

    /// Supports optional views (if let, if without else).
    public static func buildOptional<Content: View>(_ content: Content?) -> Content? {
        content
    }

    /// Supports optional views — SwiftUI's older name for ``buildOptional(_:)``,
    /// still declared there and still callable by name.
    public static func buildIf<Content: View>(_ content: Content?) -> Content? {
        content
    }

    /// Supports availability limiting.
    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> Content {
        content
    }

    // MARK: - Arrays

    /// Supports for-in loops.
    public static func buildArray<Content: View>(_ components: [Content]) -> ViewArray<Content> {
        ViewArray(components)
    }

    // MARK: - Expression

    /// Converts a single expression into a view.
    public static func buildExpression<Content: View>(_ expression: Content) -> Content {
        expression
    }

    /// Supports optional expressions.
    public static func buildExpression<Content: View>(_ expression: Content?) -> Content? {
        expression
    }
}
