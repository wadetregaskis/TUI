//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SafeAreaInsetModifier.swift
//
//  `safeAreaInset(edge:alignment:spacing:content:)` and `safeAreaBar`: a bar
//  beside a view, which is inset by the bar's extent.
//
//  What this is NOT is a safe area. In SwiftUI the inset also grows the
//  modified view's safe area, so a scroll view runs under the bar and a style
//  background extends beneath it. TUIkit has no safe area for a view to run
//  under (decisions doc B6), so the bar sits beside the content — the layout
//  SwiftUI gives every view that does not ignore the safe area, and what the
//  ported code that asks for an input bar or a side panel is asking for.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Lays `inset` beside `base` on `edge`, with `base` proposed what is left.
struct SafeAreaInsetModifier<Base: View, Inset: View>: View {
    /// The modified view.
    let base: Base

    /// The bar.
    let inset: Inset

    /// The edge the bar is anchored to.
    let edge: Edge

    /// Where the bar goes across the stacking axis: the horizontal component
    /// for a top or bottom bar, the vertical one for a leading or trailing bar.
    let alignment: Alignment

    /// Cells between the view and the bar.
    let spacing: Int

    var body: Never {
        fatalError("SafeAreaInsetModifier renders via Renderable")
    }

    /// Whether the bar stacks above or below the view, rather than beside it.
    private var stacksVertically: Bool { edge == .top || edge == .bottom }

    /// Whether the bar comes first along the stacking axis.
    private var insetLeads: Bool { edge == .top || edge == .leading }

    /// The sizes the two children get for `proposal`: the bar first, at its
    /// natural extent along the stacking axis and the full extent across it,
    /// then the view, proposed what the bar and the spacing leave.
    ///
    /// One function for both passes, so the measure and the render cannot
    /// disagree about what either child was offered.
    private func plan(_ proposal: ProposedSize, context: RenderContext)
        -> (inset: ViewSize, base: ViewSize, baseProposal: ProposedSize, gap: Int)
    {
        let insetProposal =
            stacksVertically
            ? ProposedSize(width: proposal.width, height: nil)
            : ProposedSize(width: nil, height: proposal.height)
        let insetSize = measureChild(
            inset, proposal: insetProposal, context: layerContext(context, modifierType: Self.self))
        let along = stacksVertically ? insetSize.height : insetSize.width
        // No bar, no spacing: an empty inset leaves the view where it was.
        let gap = along > 0 ? spacing : 0
        let baseProposal =
            stacksVertically
            ? ProposedSize(width: proposal.width, height: proposal.height.map { max(0, $0 - along - gap) })
            : ProposedSize(width: proposal.width.map { max(0, $0 - along - gap) }, height: proposal.height)
        let baseSize = measureChild(base, proposal: baseProposal, context: context)
        return (insetSize, baseSize, baseProposal, gap)
    }
}

extension SafeAreaInsetModifier: Layoutable {
    /// The two children's union: summed along the stacking axis, the larger of
    /// the two across it — measured in SwiftUI, a bar wider than its view
    /// makes the result the bar's width.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let (insetSize, baseSize, _, gap) = plan(proposal, context: context)
        if stacksVertically {
            return ViewSize(
                width: max(baseSize.width, insetSize.width),
                height: baseSize.height + gap + insetSize.height,
                isWidthFlexible: baseSize.isWidthFlexible || insetSize.isWidthFlexible,
                isHeightFlexible: baseSize.isHeightFlexible)
        }
        return ViewSize(
            width: baseSize.width + gap + insetSize.width,
            height: max(baseSize.height, insetSize.height),
            isWidthFlexible: baseSize.isWidthFlexible,
            isHeightFlexible: baseSize.isHeightFlexible || insetSize.isHeightFlexible)
    }
}

extension SafeAreaInsetModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let proposal = ProposedSize(
            width: max(0, context.availableWidth), height: max(0, context.availableHeight))
        let (insetSize, _, baseProposal, gap) = plan(proposal, context: context)

        // The view at the modifier's own identity, so adding a bar moves no
        // `@State`; the bar at the layer identity `.overlay` uses.
        var baseContext = context
        baseContext.availableWidth = baseProposal.width ?? context.availableWidth
        baseContext.availableHeight = baseProposal.height ?? context.availableHeight
        let baseBuffer = TUIkitView.renderToBuffer(base, context: baseContext)

        var insetContext = layerContext(context, modifierType: Self.self)
        if stacksVertically {
            insetContext.availableHeight = insetSize.height
        } else {
            insetContext.availableWidth = insetSize.width
        }
        let insetBuffer = TUIkitView.renderToBuffer(inset, context: insetContext)

        // Laid out along the stacking axis, bar first or last; across it the
        // bar by `alignment` and the view centred, as SwiftUI centres it.
        let width: Int
        let height: Int
        let basePosition: (x: Int, y: Int)
        let insetPosition: (x: Int, y: Int)
        if stacksVertically {
            width = max(baseBuffer.width, insetBuffer.width)
            height = baseBuffer.height + gap + insetBuffer.height
            let baseX = HorizontalAlignment.center.childOffset(childWidth: baseBuffer.width, in: width)
            let insetX = alignment.horizontal.childOffset(childWidth: insetBuffer.width, in: width)
            basePosition = (baseX, insetLeads ? insetBuffer.height + gap : 0)
            insetPosition = (insetX, insetLeads ? 0 : baseBuffer.height + gap)
        } else {
            width = baseBuffer.width + gap + insetBuffer.width
            height = max(baseBuffer.height, insetBuffer.height)
            let baseY = VerticalAlignment.center.childOffset(childHeight: baseBuffer.height, in: height)
            let insetY = alignment.vertical.childOffset(childHeight: insetBuffer.height, in: height)
            basePosition = (insetLeads ? insetBuffer.width + gap : 0, baseY)
            insetPosition = (insetLeads ? 0 : baseBuffer.width + gap, insetY)
        }

        let palette = context.environment.palette
        var result = FrameBuffer(emptyWithWidth: width, height: height)
        result.compositeCarryingClaimsOverNothing(with: baseBuffer, at: basePosition, palette: palette)
        result.compositeCarryingClaimsOverNothing(with: insetBuffer, at: insetPosition, palette: palette)
        return result
    }
}

extension View {
    /// Shows the specified content above or below the modified view.
    ///
    /// ```swift
    /// MessageList()
    ///     .safeAreaInset(edge: .bottom, spacing: 0) {
    ///         ComposeBar()
    ///     }
    /// ```
    ///
    /// The view is inset by the bar's height and proposed what is left; the
    /// bar is offered the full width and placed across it by `alignment`.
    /// SwiftUI also grows the view's safe area by the bar, so a scroll view
    /// runs under it; TUIkit has no safe area, and the bar sits beside the
    /// view instead — see the compatibility notes.
    ///
    /// - Parameters:
    ///   - edge: The vertical edge to put the bar on.
    ///   - alignment: Where the bar goes across the view's width. Default
    ///     `.center`.
    ///   - spacing: Cells between the view and the bar; `nil`, the default, is
    ///     none, as SwiftUI measures it.
    ///   - content: The bar.
    /// - Returns: A view with the bar beside it.
    public func safeAreaInset<V: View>(
        edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: Int? = nil,
        @ViewBuilder content: () -> V
    ) -> some View {
        SafeAreaInsetModifier(
            base: self, inset: content(), edge: edge == .top ? .top : .bottom,
            alignment: Alignment(horizontal: alignment, vertical: .center), spacing: spacing ?? 0)
    }

    /// Shows the specified content beside the modified view.
    ///
    /// The horizontal twin of ``safeAreaInset(edge:alignment:spacing:content:)-(VerticalEdge,_,_,_)``:
    /// the view is inset by the bar's width, and the bar is offered the full
    /// height and placed across it by `alignment`.
    ///
    /// - Parameters:
    ///   - edge: The horizontal edge to put the bar on.
    ///   - alignment: Where the bar goes across the view's height. Default
    ///     `.center`.
    ///   - spacing: Cells between the view and the bar; `nil`, the default, is
    ///     none.
    ///   - content: The bar.
    /// - Returns: A view with the bar beside it.
    public func safeAreaInset<V: View>(
        edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: Int? = nil,
        @ViewBuilder content: () -> V
    ) -> some View {
        SafeAreaInsetModifier(
            base: self, inset: content(), edge: edge == .leading ? .leading : .trailing,
            alignment: Alignment(horizontal: .center, vertical: alignment), spacing: spacing ?? 0)
    }

    /// Shows the specified content as a bar above or below the modified view.
    ///
    /// SwiftUI's `safeAreaBar` is ``safeAreaInset(edge:alignment:spacing:content:)-(VerticalEdge,_,_,_)``
    /// that also extends the scroll-edge effects of the views it insets. With
    /// no safe area for content to run under there is no edge effect to extend,
    /// so the two lay out alike.
    ///
    /// - Parameters:
    ///   - edge: The vertical edge to put the bar on.
    ///   - alignment: Where the bar goes across the view's width.
    ///   - spacing: Cells between the view and the bar; `nil` is none.
    ///   - content: The bar.
    /// - Returns: A view with the bar beside it.
    public func safeAreaBar<V: View>(
        edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: Int? = nil,
        @ViewBuilder content: () -> V
    ) -> some View {
        safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
    }

    /// Shows the specified content as a bar beside the modified view — the
    /// horizontal twin of ``safeAreaBar(edge:alignment:spacing:content:)-(VerticalEdge,_,_,_)``.
    ///
    /// - Parameters:
    ///   - edge: The horizontal edge to put the bar on.
    ///   - alignment: Where the bar goes across the view's height.
    ///   - spacing: Cells between the view and the bar; `nil` is none.
    ///   - content: The bar.
    /// - Returns: A view with the bar beside it.
    public func safeAreaBar<V: View>(
        edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: Int? = nil,
        @ViewBuilder content: () -> V
    ) -> some View {
        safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
    }
}
