//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabContentBuilder.swift
//
//  The result builder a tab view's tabs are written in, and the view a tab
//  view holds them in.
//
//  Created by Wade Tregaskis
//  License: MIT

// SwiftUI's builder spells out every arity to ten; so do these, and the
// longest signatures have ten parameters by design.
// swiftlint:disable function_parameter_count

/// A result builder that constructs tabs for a ``TabView``.
///
/// Don't use this type directly; the `content` parameter of the ``TabView``
/// initializers is annotated with it, and so are ``TabSection``'s, ``Group``'s
/// and ``ForEach``'s when they hold tabs. An `if` and an `if`/`else` compose
/// tabs; a `for` loop does not, exactly as in SwiftUI — ``ForEach`` builds
/// tabs from a collection.
@MainActor
@resultBuilder
public struct TabContentBuilder<TabValue: Hashable> {
    /// The tabs a tab view holds, as a view: what ``TabView``'s `Content` is.
    ///
    /// You don't create this; a tab view's initializer does, and draws the
    /// tabs it holds. Drawn on its own it draws nothing.
    public struct Content<C: TabContent>: View {
        /// The tabs.
        let content: C

        init(_ content: C) {
            self.content = content
        }

        /// Nothing: the tab view holding this draws its tabs.
        public var body: some View {
            EmptyView()
        }
    }

    /// Passes a single expression of tab content through unmodified.
    public static func buildExpression(_ content: some TabContent<TabValue>) -> some TabContent<TabValue> {
        content
    }

    /// Passes a single block of tab content through unmodified.
    public static func buildBlock(_ content: some TabContent<TabValue>) -> some TabContent<TabValue> {
        content
    }

    /// Produces optional tab content for an `if` with no `else`.
    public static func buildIf(_ content: (some TabContent<TabValue>)?) -> (some TabContent<TabValue>)? {
        content
    }

    /// Produces tab content for the `if` branch of an `if`/`else`.
    public static func buildEither<T: TabContent, F: TabContent>(first: T) -> _ConditionalContent<T, F>
    where TabValue == T.TabValue, T.TabValue == F.TabValue {
        .trueContent(first)
    }

    /// Produces tab content for the `else` branch of an `if`/`else`.
    public static func buildEither<T: TabContent, F: TabContent>(second: F) -> _ConditionalContent<T, F>
    where TabValue == T.TabValue, T.TabValue == F.TabValue {
        .falseContent(second)
    }

    /// Erases tab content inside an `if #available(…)`.
    public static func buildLimitedAvailability<T: TabContent>(_ content: T) -> AnyTabContent<T.TabValue> {
        AnyTabContent(content)
    }
}

// MARK: - Blocks of two to ten

/// Several tabs written one after another in a builder: they hand their tabs
/// over in order.
struct _TupleTabContent<TabValue: Hashable>: TabContent, _TabContentPrimitive {
    /// Appends every member's tabs, captured where their types were known.
    let appendMembers: @MainActor (inout _TabList) -> Void

    var body: _TupleTabContent<TabValue> {
        return self  // swiftlint:disable:this implicit_return
    }

    func appendTabs(to tabs: inout _TabList) {
        appendMembers(&tabs)
    }
}

extension TabContentBuilder {
    /// Combines two pieces of tab content.
    public static func buildBlock<C0: TabContent, C1: TabContent>(
        _ c0: C0, _ c1: C1
    ) -> some TabContent<TabValue>
    where TabValue == C0.TabValue, C0.TabValue == C1.TabValue {
        _TupleTabContent<TabValue> { tabs in
            appendTabs(c0, to: &tabs)
            appendTabs(c1, to: &tabs)
        }
    }

    /// Combines three pieces of tab content.
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent>(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> some TabContent<TabValue>
    where TabValue == C0.TabValue, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue {
        _TupleTabContent<TabValue> { tabs in
            appendTabs(c0, to: &tabs)
            appendTabs(c1, to: &tabs)
            appendTabs(c2, to: &tabs)
        }
    }

    /// Combines four pieces of tab content.
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> some TabContent<TabValue>
    where
        TabValue == C0.TabValue, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue,
        C2.TabValue == C3.TabValue
    {
        _TupleTabContent<TabValue> { tabs in
            appendTabs(c0, to: &tabs)
            appendTabs(c1, to: &tabs)
            appendTabs(c2, to: &tabs)
            appendTabs(c3, to: &tabs)
        }
    }

    /// Combines five pieces of tab content.
    public static func buildBlock<
        C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> some TabContent<TabValue>
    where
        TabValue == C0.TabValue, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue,
        C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue
    {
        _TupleTabContent<TabValue> { tabs in
            appendTabs(c0, to: &tabs)
            appendTabs(c1, to: &tabs)
            appendTabs(c2, to: &tabs)
            appendTabs(c3, to: &tabs)
            appendTabs(c4, to: &tabs)
        }
    }

    /// Combines six pieces of tab content.
    public static func buildBlock<
        C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent,
        C5: TabContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5
    ) -> some TabContent<TabValue>
    where
        TabValue == C0.TabValue, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue,
        C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue
    {
        _TupleTabContent<TabValue> { tabs in
            appendTabs(c0, to: &tabs)
            appendTabs(c1, to: &tabs)
            appendTabs(c2, to: &tabs)
            appendTabs(c3, to: &tabs)
            appendTabs(c4, to: &tabs)
            appendTabs(c5, to: &tabs)
        }
    }

    /// Combines seven pieces of tab content.
    public static func buildBlock<
        C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent,
        C5: TabContent, C6: TabContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6
    ) -> some TabContent<TabValue>
    where
        TabValue == C0.TabValue, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue,
        C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue,
        C5.TabValue == C6.TabValue
    {
        _TupleTabContent<TabValue> { tabs in
            appendTabs(c0, to: &tabs)
            appendTabs(c1, to: &tabs)
            appendTabs(c2, to: &tabs)
            appendTabs(c3, to: &tabs)
            appendTabs(c4, to: &tabs)
            appendTabs(c5, to: &tabs)
            appendTabs(c6, to: &tabs)
        }
    }

    /// Combines eight pieces of tab content.
    public static func buildBlock<
        C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent,
        C5: TabContent, C6: TabContent, C7: TabContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7
    ) -> some TabContent<TabValue>
    where
        TabValue == C0.TabValue, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue,
        C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue,
        C5.TabValue == C6.TabValue, C6.TabValue == C7.TabValue
    {
        _TupleTabContent<TabValue> { tabs in
            appendTabs(c0, to: &tabs)
            appendTabs(c1, to: &tabs)
            appendTabs(c2, to: &tabs)
            appendTabs(c3, to: &tabs)
            appendTabs(c4, to: &tabs)
            appendTabs(c5, to: &tabs)
            appendTabs(c6, to: &tabs)
            appendTabs(c7, to: &tabs)
        }
    }

    /// Combines nine pieces of tab content.
    public static func buildBlock<
        C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent,
        C5: TabContent, C6: TabContent, C7: TabContent, C8: TabContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8
    ) -> some TabContent<TabValue>
    where
        TabValue == C0.TabValue, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue,
        C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue,
        C5.TabValue == C6.TabValue, C6.TabValue == C7.TabValue, C7.TabValue == C8.TabValue
    {
        _TupleTabContent<TabValue> { tabs in
            appendTabs(c0, to: &tabs)
            appendTabs(c1, to: &tabs)
            appendTabs(c2, to: &tabs)
            appendTabs(c3, to: &tabs)
            appendTabs(c4, to: &tabs)
            appendTabs(c5, to: &tabs)
            appendTabs(c6, to: &tabs)
            appendTabs(c7, to: &tabs)
            appendTabs(c8, to: &tabs)
        }
    }

    /// Combines ten pieces of tab content.
    public static func buildBlock<
        C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent,
        C5: TabContent, C6: TabContent, C7: TabContent, C8: TabContent, C9: TabContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8,
        _ c9: C9
    ) -> some TabContent<TabValue>
    where
        TabValue == C0.TabValue, C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue,
        C2.TabValue == C3.TabValue, C3.TabValue == C4.TabValue, C4.TabValue == C5.TabValue,
        C5.TabValue == C6.TabValue, C6.TabValue == C7.TabValue, C7.TabValue == C8.TabValue,
        C8.TabValue == C9.TabValue
    {
        _TupleTabContent<TabValue> { tabs in
            appendTabs(c0, to: &tabs)
            appendTabs(c1, to: &tabs)
            appendTabs(c2, to: &tabs)
            appendTabs(c3, to: &tabs)
            appendTabs(c4, to: &tabs)
            appendTabs(c5, to: &tabs)
            appendTabs(c6, to: &tabs)
            appendTabs(c7, to: &tabs)
            appendTabs(c8, to: &tabs)
            appendTabs(c9, to: &tabs)
        }
    }
}

// swiftlint:enable function_parameter_count
