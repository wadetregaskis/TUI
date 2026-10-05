//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GroupElementsOfContent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Group(subviews:transform:)

@MainActor
extension Group {
    /// Constructs a group from the subviews of the given view.
    ///
    /// Use this initializer to build a container of your own: `transform`
    /// receives `view`'s members as a ``SubviewsCollection`` and builds the
    /// group's content from them.
    ///
    /// ```swift
    /// struct CardsView<Content: View>: View {
    ///     var content: Content
    ///
    ///     init(@ViewBuilder content: () -> Content) {
    ///         self.content = content()
    ///     }
    ///
    ///     var body: some View {
    ///         VStack {
    ///             Group(subviews: content) { subviews in
    ///                 HStack {
    ///                     if subviews.count >= 2 {
    ///                         SecondaryCard { subviews[1] }
    ///                     }
    ///                     if let first = subviews.first {
    ///                         FeatureCard { first }
    ///                     }
    ///                 }
    ///                 if subviews.count > 2 {
    ///                     Text("And \(subviews.count - 2) more")
    ///                 }
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// The members are what `view` is made of once `Group`s, `ForEach`es,
    /// conditionals and `Section`s are taken apart: `Text("a"); ForEach(0..<3)
    /// { … }` is four subviews, a `VStack` is one, and a `ForEach` row of
    /// several views is each of them. Two places differ from SwiftUI, both
    /// from how this framework resolves children everywhere: an `AnyView`
    /// around several views is one subview, not several, and so is a view of
    /// the app's own whose `body` is several.
    ///
    /// Like any `Group`, the result is transparent: inside a stack, the views
    /// `transform` builds are the stack's children.
    ///
    /// - Parameters:
    ///   - view: The view to get the subviews of.
    ///   - transform: A closure that constructs a view from the collection of
    ///     subviews.
    public init<Base: View, Result: View>(
        subviews view: Base,
        @ViewBuilder transform: @escaping (SubviewsCollection) -> Result
    ) where Content == GroupElementsOfContent<Base, Result> {
        self.content = GroupElementsOfContent(base: view, transform: transform)
    }
}

// MARK: - Group Elements Of Content

/// Transforms the subviews of a given view into a resulting content view.
///
/// You don't use this type directly: ``Group/init(subviews:transform:)``
/// creates it.
public struct GroupElementsOfContent<Subviews: View, Content: View>: View {
    /// The view whose members are handed to `transform`.
    let base: Subviews

    /// Builds the content from the members.
    let transform: (SubviewsCollection) -> Content

    public var body: some View {
        _GroupElementsCore(elements: self)
    }
}

extension GroupElementsOfContent: ChildViewProvider {
    /// The views `transform` builds, as the enclosing container's children.
    ///
    /// Two scopes, one per side, so nothing on one side can land on an
    /// identity from the other: the members resolve under a step of their own
    /// (`Subviews`, 0) and are pinned there, and the result resolves under
    /// (`Content`, 1). Without the split a result `Text` and a member `Text`
    /// both became the first `Text` here and shared one `@State` box. The
    /// result's children are pinned too, or each would take its identity from
    /// whichever container ends up drawing it.
    public func childViews(context: RenderContext) -> [ChildView] {
        let subviews = SubviewsCollection(
            members: SubviewMembers(
                resolving: base, in: context.withChildIdentity(type: Subviews.self, index: 0)))
        let result = transform(subviews)
        let resultScope = context.withChildIdentity(type: Content.self, index: 1)
        return resolveChildViews(from: result, context: resultScope).map {
            $0.pinningIdentity(to: resultScope.identity)
        }
    }

    /// Remembered for the pass: a stack measures and renders its children
    /// several times a frame, and each would otherwise resolve the members
    /// and run the transform again.
    public var childViewsAreWorthMemoising: Bool { true }
}

/// The transform's views stacked vertically, for where nothing above lays them
/// out — a `Group(subviews:)` that is a view's whole body.
private struct _GroupElementsCore<Subviews: View, Content: View>: View, Renderable, Layoutable {
    let elements: GroupElementsOfContent<Subviews, Content>

    var body: Never {
        fatalError("_GroupElementsCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureStackedVertically(
            resolveChildViews(from: elements, context: context), proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderStackedVertically(resolveChildViews(from: elements, context: context), context: context)
    }
}
