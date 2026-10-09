//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StyledContent.swift
//
//  A style configuration's content: the views a control was given, handed to
//  its style. SwiftUI gives each configuration a type of its own for it, and a
//  style writes `HStack { configuration.content }` expecting the content's
//  views to lay out side by side — which an `AnyView` would not do, being one
//  child to the stack. This type is a ``ChildViewProvider``: it hands the stack
//  the views it holds, resolved at the type they were written as.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A style configuration's content: the views a control was given, which lay
/// out as separate children of whatever stack the style puts them in — as
/// `MenuStyleConfiguration.Content` does for a menu's items.
public struct _StyledContent: View, ChildViewProvider {
    /// The content, erased, for drawing it as one view.
    let content: AnyView

    /// The content as it was written — for a control that reads structure out
    /// of what it was given, as a control group reads its label.
    package let underlying: any View

    /// The content's views, resolved at their concrete type, which an erasure
    /// would have lost.
    private let children: @MainActor (RenderContext) -> [ChildView]

    package init<V: View>(_ view: V) {
        self.content = AnyView(view)
        self.underlying = view
        self.children = { resolveChildViews(from: view, context: $0) }
    }

    public var body: some View {
        content
    }

    public func childViews(context: RenderContext) -> [ChildView] {
        children(context)
    }
}
