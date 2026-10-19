//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WrapperGuidePropagation.swift
//
//  An explicit alignment guide travels out through `.frame`, `.border` and
//  `.offset`, each moving it by where it puts its content, as SwiftUI's does
//  (measured, `Tools/SwiftUIProbes/Alignment guides/layout1.out`, case B;
//  decisions SA-L11). `.padding`'s is beside the stacks', in
//  `StackGuidePropagation.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Frame

extension FlexibleFrameView {
    /// Its content's answer: a frame places its one view, so a guide in it
    /// is the frame's to report, moved by where the frame put it.
    public static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

extension FlexibleFrameView: AlignmentGuideQuerying {
    /// The content's guide, moved by where the frame places the content: by
    /// the content's own guide for the frame's alignment where it set one
    /// (decisions B-GUIDE-3), else by the alignment — the placement
    /// `renderToBuffer` makes, past the frame's edge where that is where it
    /// draws the content. Measured on SwiftUI: a one-cell view whose leading
    /// guide is 5 in a ten-wide frame reports 0 aligned `.leading` (it sits at
    /// −5), 9.25 `.center` and 14 `.trailing`.
    ///
    /// The frame was laid out at `dimensions`, and is taken to have been
    /// offered them: what it offers its content is worked out from them as
    /// the render works it out from its offer.
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        var contentContext = context
        let offeredNoWidth = isOfferedNoWidth(in: context)
        contentContext.availableWidth = contentTargetWidth(
            availableWidth: dimensions.width, offeredNothing: offeredNoWidth)
        if offeredNoWidth { contentContext.environment.fixedSizeWidth = false }
        if let height = contentTargetHeight(availableHeight: dimensions.height) {
            contentContext.availableHeight = height
        }
        if minWidth != nil || idealWidth != nil || maxWidth != nil { contentContext.hasExplicitWidth = true }
        if minHeight != nil || idealHeight != nil || maxHeight != nil { contentContext.hasExplicitHeight = true }
        let measured = measureChild(
            content,
            proposal: ProposedSize(width: contentContext.availableWidth, height: contentContext.availableHeight),
            context: contentContext)
        let size = (width: measured.width, height: measured.height)
        let x =
            horizontalGuidePlacement(
                of: content, size: size, alignment: alignment.horizontal, in: dimensions.width,
                context: contentContext)
            ?? alignment.horizontal.childOffset(childWidth: size.width, in: dimensions.width)
        let y =
            verticalGuidePlacement(
                of: content, size: size, alignment: alignment.vertical, in: dimensions.height,
                context: contentContext)
            ?? alignment.vertical.childOffset(childHeight: size.height, in: dimensions.height)
        return TUIkitFoundation.explicitGuide(
            of: content, query, in: ViewDimensions(width: size.width, height: size.height),
            context: contentContext
        ).map { query.translated($0, by: (x: x, y: y)) }
    }
}

// MARK: - Offset

extension OffsetView {
    /// Its content's answer: an offset moves only where its content is
    /// drawn, so the content's guides are the offset view's.
    public static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

extension OffsetView: AlignmentGuideQuerying {
    /// The content's guide, unmoved: an offset is laid out where its content
    /// is and only draws it elsewhere, so SwiftUI reports the guide from the
    /// layout's place (measured: `.offset(x: 3)` after a leading guide of 5
    /// still reports 5).
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        TUIkitFoundation.explicitGuide(of: content, query, in: dimensions, context: context)
    }
}

// MARK: - Border

extension _BorderRings: AlignmentGuideQuerying {
    /// The bordered view's guide, moved in by every ring around it: a line
    /// and the ring's padding on each side (`ring(style:colour:)`).
    ///
    /// SwiftUI strokes its border inside the view, so its guide comes out
    /// unmoved (measured: a leading guide of 5 under `.border(_:width: 2)`
    /// still reports 5); a terminal border takes cells round its content, so
    /// the guide here is moved by those cells, as by a padding.
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        explicitGuideInsideRing(rings.erasedView, query, in: dimensions, context: context)
    }
}

/// The guide of what a border's ring `ring` holds — the next ring in, or the
/// bordered view — moved by where the ring puts it. `ring` is the value an
/// erased ring holds, a ``ContainerView`` drawn at `context`'s identity, as an
/// `AnyView` draws its content.
@MainActor
private func explicitGuideInsideRing(
    _ ring: any View, _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
) -> Double? {
    guard let holder = ring as? BorderRingQuerying else { return nil }
    return holder.contentGuide(query, in: dimensions, context: context)
}

/// A border's ring, asked for the guide of what it holds.
@MainActor
private protocol BorderRingQuerying {
    func contentGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double?
}

extension ContainerView: BorderRingQuerying where Footer == EmptyView {
    /// The content's guide, moved by the ring's line and padding, laid out
    /// where `_ContainerViewCore.renderToBuffer(context:)` lays it out: at
    /// the core's identity, then the content's, between the lines and inside
    /// the padding. A next ring in is erased, and opened here.
    fileprivate func contentGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        guard style.hasBorder, title == nil, footer == nil, !style.scrollsOverflowingBody else { return nil }
        let origin = (x: 1 + padding.leading, y: 1 + padding.top)
        let inner = ViewDimensions(
            width: max(0, dimensions.width - 2 - padding.leading - padding.trailing),
            height: max(0, dimensions.height - 2 - padding.top - padding.bottom))
        var contentContext = context.withChildIdentity(type: Body.self)
            .withChildIdentity(type: Content.self, index: 0)
        contentContext.availableWidth = inner.width
        contentContext.availableHeight = inner.height
        let guide: Double?
        if let erased = content as? AnyView {
            guide = explicitGuideInsideRing(erased.erasedView, query, in: inner, context: contentContext)
        } else {
            guide = TUIkitFoundation.explicitGuide(of: content, query, in: inner, context: contentContext)
        }
        return guide.map { query.translated($0, by: origin) }
    }
}

// MARK: - Position

extension PositionView {
    /// Its content's answer: a positioned view places its one view, so a
    /// guide in it is the positioned view's to report, moved by where it put
    /// the view.
    public static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

extension PositionView: AlignmentGuideQuerying {
    /// The content's guide, moved by where the position puts the content:
    /// its centre on the point, in the space the position view fills, as
    /// `renderToBuffer` draws it (SwiftUI: `.position(x: 3, y: 0)` puts a
    /// one-point view whose leading guide is 5 at 2.5, and reports 7.5; here
    /// the view is a whole cell at 3, and reports 8).
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        let size = measureChild(
            content, proposal: ProposedSize(width: dimensions.width, height: dimensions.height), context: context)
        return TUIkitFoundation.explicitGuide(
            of: content, query, in: ViewDimensions(width: size.width, height: size.height), context: context
        ).map { query.translated($0, by: (x: x - size.width / 2, y: y - size.height / 2)) }
    }
}

// MARK: - Overlay and Background

extension OverlayModifier {
    /// Its base's answer: an overlay is laid out at its base's size and
    /// place, so the base's guides are the overlaid view's, as SwiftUI's are.
    public static var _providesAlignmentGuide: Bool { Base._providesAlignmentGuide }
}

extension OverlayModifier: AlignmentGuideQuerying {
    /// The base's guide, unmoved: the overlay sits on its base, which is
    /// where the overlaid view is (measured: a leading guide of 5 under an
    /// overlay ten wide still reports 5).
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        TUIkitFoundation.explicitGuide(of: base, query, in: dimensions, context: context)
    }
}

extension BackgroundLayerModifier {
    /// Its base's answer, as an overlay's is.
    static var _providesAlignmentGuide: Bool { Base._providesAlignmentGuide }
}

extension BackgroundLayerModifier: AlignmentGuideQuerying {
    /// The base's guide, unmoved, as an overlay's.
    func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        TUIkitFoundation.explicitGuide(of: base, query, in: dimensions, context: context)
    }
}
