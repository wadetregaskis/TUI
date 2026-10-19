//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarContentBuilder+Customizable.swift
//
//  The toolbar content builder's customizable forms: content made only of
//  customizable toolbar content is customizable toolbar content, which
//  `toolbar(id:content:)` takes.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// SwiftUI's builder spells out every arity to ten, for customizable content
// as for any; so does this one, and the longest signatures have ten
// parameters by design.
// swiftlint:disable function_parameter_count

extension ToolbarContentBuilder {
    /// Passes customizable content through as it is.
    public static func buildExpression<Content: CustomizableToolbarContent>(_ content: Content) -> Content {
        content
    }

    /// One piece of customizable content, as it is.
    public static func buildBlock<Content: CustomizableToolbarContent>(_ content: Content) -> some CustomizableToolbarContent {
        content
    }

    /// Customizable content under an `if` with no `else`.
    public static func buildIf<Content: CustomizableToolbarContent>(_ content: Content?) -> Content? {
        content
    }

    /// The first branch of an `if`/`else` of customizable content.
    public static func buildEither<TrueContent: CustomizableToolbarContent, FalseContent: CustomizableToolbarContent>(
        first: TrueContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .trueContent(first)
    }

    /// The second branch of an `if`/`else` of customizable content.
    public static func buildEither<TrueContent: CustomizableToolbarContent, FalseContent: CustomizableToolbarContent>(
        second: FalseContent
    ) -> _ConditionalContent<TrueContent, FalseContent> {
        .falseContent(second)
    }

    /// Customizable content under `if #available`, its type erased.
    public static func buildLimitedAvailability(_ content: any CustomizableToolbarContent) -> some CustomizableToolbarContent {
        _AnyToolbarContent(content)
    }
}

// MARK: - Blocks of two to ten

extension ToolbarContentBuilder {
    /// 2 pieces of customizable content written one after another.
    public static func buildBlock<C0: CustomizableToolbarContent, C1: CustomizableToolbarContent>(
        _ c0: C0, _ c1: C1
    ) -> some CustomizableToolbarContent {
        _TupleToolbarContent { items in
            items.step(0, c0)
            items.step(1, c1)
        }
    }

    /// 3 pieces of customizable content written one after another.
    public static func buildBlock<
        C0: CustomizableToolbarContent, C1: CustomizableToolbarContent, C2: CustomizableToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> some CustomizableToolbarContent {
        _TupleToolbarContent { items in
            items.step(0, c0)
            items.step(1, c1)
            items.step(2, c2)
        }
    }

    /// 4 pieces of customizable content written one after another.
    public static func buildBlock<
        C0: CustomizableToolbarContent, C1: CustomizableToolbarContent, C2: CustomizableToolbarContent,
        C3: CustomizableToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> some CustomizableToolbarContent {
        _TupleToolbarContent { items in
            items.step(0, c0)
            items.step(1, c1)
            items.step(2, c2)
            items.step(3, c3)
        }
    }

    /// 5 pieces of customizable content written one after another.
    public static func buildBlock<
        C0: CustomizableToolbarContent, C1: CustomizableToolbarContent, C2: CustomizableToolbarContent,
        C3: CustomizableToolbarContent, C4: CustomizableToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> some CustomizableToolbarContent {
        _TupleToolbarContent { items in
            items.step(0, c0)
            items.step(1, c1)
            items.step(2, c2)
            items.step(3, c3)
            items.step(4, c4)
        }
    }

    /// 6 pieces of customizable content written one after another.
    public static func buildBlock<
        C0: CustomizableToolbarContent, C1: CustomizableToolbarContent, C2: CustomizableToolbarContent,
        C3: CustomizableToolbarContent, C4: CustomizableToolbarContent, C5: CustomizableToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5
    ) -> some CustomizableToolbarContent {
        _TupleToolbarContent { items in
            items.step(0, c0)
            items.step(1, c1)
            items.step(2, c2)
            items.step(3, c3)
            items.step(4, c4)
            items.step(5, c5)
        }
    }

    /// 7 pieces of customizable content written one after another.
    public static func buildBlock<
        C0: CustomizableToolbarContent, C1: CustomizableToolbarContent, C2: CustomizableToolbarContent,
        C3: CustomizableToolbarContent, C4: CustomizableToolbarContent, C5: CustomizableToolbarContent,
        C6: CustomizableToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6
    ) -> some CustomizableToolbarContent {
        _TupleToolbarContent { items in
            items.step(0, c0)
            items.step(1, c1)
            items.step(2, c2)
            items.step(3, c3)
            items.step(4, c4)
            items.step(5, c5)
            items.step(6, c6)
        }
    }

    /// 8 pieces of customizable content written one after another.
    public static func buildBlock<
        C0: CustomizableToolbarContent, C1: CustomizableToolbarContent, C2: CustomizableToolbarContent,
        C3: CustomizableToolbarContent, C4: CustomizableToolbarContent, C5: CustomizableToolbarContent,
        C6: CustomizableToolbarContent, C7: CustomizableToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7
    ) -> some CustomizableToolbarContent {
        _TupleToolbarContent { items in
            items.step(0, c0)
            items.step(1, c1)
            items.step(2, c2)
            items.step(3, c3)
            items.step(4, c4)
            items.step(5, c5)
            items.step(6, c6)
            items.step(7, c7)
        }
    }

    /// 9 pieces of customizable content written one after another.
    public static func buildBlock<
        C0: CustomizableToolbarContent, C1: CustomizableToolbarContent, C2: CustomizableToolbarContent,
        C3: CustomizableToolbarContent, C4: CustomizableToolbarContent, C5: CustomizableToolbarContent,
        C6: CustomizableToolbarContent, C7: CustomizableToolbarContent, C8: CustomizableToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8
    ) -> some CustomizableToolbarContent {
        _TupleToolbarContent { items in
            items.step(0, c0)
            items.step(1, c1)
            items.step(2, c2)
            items.step(3, c3)
            items.step(4, c4)
            items.step(5, c5)
            items.step(6, c6)
            items.step(7, c7)
            items.step(8, c8)
        }
    }

    /// 10 pieces of customizable content written one after another.
    public static func buildBlock<
        C0: CustomizableToolbarContent, C1: CustomizableToolbarContent, C2: CustomizableToolbarContent,
        C3: CustomizableToolbarContent, C4: CustomizableToolbarContent, C5: CustomizableToolbarContent,
        C6: CustomizableToolbarContent, C7: CustomizableToolbarContent, C8: CustomizableToolbarContent,
        C9: CustomizableToolbarContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9
    ) -> some CustomizableToolbarContent {
        _TupleToolbarContent { items in
            items.step(0, c0)
            items.step(1, c1)
            items.step(2, c2)
            items.step(3, c3)
            items.step(4, c4)
            items.step(5, c5)
            items.step(6, c6)
            items.step(7, c7)
            items.step(8, c8)
            items.step(9, c9)
        }
    }
}

// swiftlint:enable function_parameter_count
