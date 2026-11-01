//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarContentBuilder.swift
//
//  The result builder a `.toolbar { … }`'s items are written in.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// SwiftUI's builder spells out every arity to ten; so does this one, and the
// longest signatures have ten parameters by design.
// swiftlint:disable function_parameter_count

/// Constructs a toolbar item set from multi-expression closures — mirrors
/// SwiftUI's `ToolbarContentBuilder`.
///
/// You don't use this type directly; `toolbar(content:)`'s
/// `content` parameter is annotated with it, and so is a
/// ``ToolbarContent/body-swift.property``. An `if` and an `if`/`else` compose
/// items, as in SwiftUI.
@MainActor
@resultBuilder
public struct ToolbarContentBuilder {
    /// Passes a single expression of toolbar content through unmodified.
    public static func buildExpression<Content: ToolbarContent>(_ content: Content) -> Content {
        content
    }

    /// Passes a single block of toolbar content through unmodified.
    ///
    /// Typed as the content itself rather than SwiftUI's `some ToolbarContent`,
    /// as ``ViewBuilder``'s is, so a primitive item's `body: Never` — whose
    /// `fatalError()` this builder transforms like any other body — type-checks.
    public static func buildBlock<Content: ToolbarContent>(_ content: Content) -> Content {
        content
    }

    /// Produces optional toolbar content for an `if` with no `else`.
    public static func buildIf<Content: ToolbarContent>(_ content: Content?) -> Content? {
        content
    }

    /// Produces toolbar content for the `if` branch of an `if`/`else`.
    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .trueContent(first)
    }

    /// Produces toolbar content for the `else` branch of an `if`/`else`.
    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .falseContent(second)
    }

    /// Erases toolbar content inside an `if #available(…)`.
    public static func buildLimitedAvailability(_ content: any ToolbarContent) -> some ToolbarContent {
        _AnyToolbarContent(content)
    }
}

// MARK: - Blocks of two to ten

extension ToolbarContentBuilder {
    /// Combines two pieces of toolbar content.
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent>(
        _ c0: C0, _ c1: C1
    ) -> some ToolbarContent {
        _TupleToolbarContent(c0, c1)
    }

    /// Combines three pieces of toolbar content.
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent>(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> some ToolbarContent {
        _TupleToolbarContent(c0, c1, c2)
    }

    /// Combines four pieces of toolbar content.
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> some ToolbarContent {
        _TupleToolbarContent(c0, c1, c2, c3)
    }

    /// Combines five pieces of toolbar content.
    public static func buildBlock<
        C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> some ToolbarContent {
        _TupleToolbarContent(c0, c1, c2, c3, c4)
    }

    /// Combines six pieces of toolbar content.
    public static func buildBlock<
        C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent,
        C5: ToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5
    ) -> some ToolbarContent {
        _TupleToolbarContent(c0, c1, c2, c3, c4, c5)
    }

    /// Combines seven pieces of toolbar content.
    public static func buildBlock<
        C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent,
        C5: ToolbarContent, C6: ToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6
    ) -> some ToolbarContent {
        _TupleToolbarContent(c0, c1, c2, c3, c4, c5, c6)
    }

    /// Combines eight pieces of toolbar content.
    public static func buildBlock<
        C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent,
        C5: ToolbarContent, C6: ToolbarContent, C7: ToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7
    ) -> some ToolbarContent {
        _TupleToolbarContent(c0, c1, c2, c3, c4, c5, c6, c7)
    }

    /// Combines nine pieces of toolbar content.
    public static func buildBlock<
        C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent,
        C5: ToolbarContent, C6: ToolbarContent, C7: ToolbarContent, C8: ToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8
    ) -> some ToolbarContent {
        _TupleToolbarContent(c0, c1, c2, c3, c4, c5, c6, c7, c8)
    }

    /// Combines ten pieces of toolbar content.
    public static func buildBlock<
        C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent,
        C5: ToolbarContent, C6: ToolbarContent, C7: ToolbarContent, C8: ToolbarContent, C9: ToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9
    ) -> some ToolbarContent {
        _TupleToolbarContent(c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)
    }
}

// swiftlint:enable function_parameter_count
