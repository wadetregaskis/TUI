//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AspectRatioLayout.swift
//
//  SwiftUI's `aspectRatio(_:contentMode:)` as the layout modifier it is: what
//  it offers its content, for any view, not only an image.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// Offers its content the largest size of a ratio that fits what it is offered
/// (`.fit`), or the smallest that covers it (`.fill`), and takes what the
/// content makes of that — as SwiftUI's does (measured on macOS 15.8,
/// `PROBES-1014/aspect-ratio`):
///
/// - The ratio is width over height in POINTS, as SwiftUI's is; a cell is
///   taller than it is wide (``EnvironmentValues/imageCellAspect``), so a
///   square is twice as many columns as rows at the usual aspect.
/// - With no ratio, the content's own ideal size gives it, in cells.
/// - An axis offered nothing in particular — `.fixedSize()`, a scroll view's
///   scroll axis, a natural-extent probe — is unconstrained: the ratio follows
///   from the other axis, and with neither, the content is asked for its own
///   size, the ratio unapplied.
/// - What does not take its offer keeps its size: a `Text` is offered the
///   shape and wraps to it; a `.frame(width:height:)` is what it says.
///
/// A fill larger than what it is offered is drawn in a frame of that size, so
/// it is cut to it as a frame cuts any content larger than itself, rather than
/// drawn past it: a terminal has no outside to draw into.
struct _AspectRatioView<Content: View>: View {
    let content: Content
    /// Width over height, in points, or `nil` for the content's own.
    let aspectRatio: Double?
    let contentMode: ContentMode

    var body: Never {
        fatalError("_AspectRatioView renders via Renderable")
    }
}

extension _AspectRatioView {
    /// The ratio in cells — columns over rows — or `nil` where there is none
    /// to keep.
    private func cellRatio(context: RenderContext) -> Double? {
        if let aspectRatio {
            let ratio = aspectRatio * context.environment.imageCellAspect
            return ratio.isFinite && ratio > 0 ? ratio : nil
        }
        let ideal = measureChild(content, proposal: .unspecified, context: context)
        guard ideal.width > 0, ideal.height > 0 else { return nil }
        return Double(ideal.width) / Double(ideal.height)
    }

    /// The size of `ratio` to offer the content, given `width` × `height`
    /// (either `nil` where unconstrained), or `nil` when neither axis says
    /// anything, so the content is asked for its own.
    private func target(width: Int?, height: Int?, ratio: Double) -> (width: Int, height: Int)? {
        func rows(_ columns: Int) -> Int { max(0, Int((Double(columns) / ratio).rounded())) }
        func columns(_ rows: Int) -> Int { max(0, Int((Double(rows) * ratio).rounded())) }
        let width = width.flatMap { isNaturalExtentBudget($0) ? nil : $0 }
        let height = height.flatMap { isNaturalExtentBudget($0) ? nil : $0 }
        switch (width, height) {
        case (nil, nil):
            return nil
        case (let width?, nil):
            return (width, rows(width))
        case (nil, let height?):
            return (columns(height), height)
        case (let width?, let height?):
            let byWidth = rows(width)
            switch contentMode {
            case .fit: return byWidth <= height ? (width, byWidth) : (columns(height), height)
            case .fill: return byWidth >= height ? (width, byWidth) : (columns(height), height)
            }
        }
    }
}

extension _AspectRatioView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let ratio = cellRatio(context: context),
            let target = target(width: proposal.width, height: proposal.height, ratio: ratio)
        else { return measureChild(content, proposal: proposal, context: context) }
        let child = measureChild(content, proposal: .fixed(target.width, target.height), context: context)
        // What the content makes of the shape: a flexible content takes it (its
        // measure reports only the least it needs), a fixed one keeps its own.
        var width = child.isWidthFlexible ? max(child.width, target.width) : child.width
        var height = child.isHeightFlexible ? max(child.height, target.height) : child.height
        // A fill past what was offered is cut to it, so it takes no more.
        if let offered = proposal.width, !isNaturalExtentBudget(offered) { width = min(width, offered) }
        if let offered = proposal.height, !isNaturalExtentBudget(offered) { height = min(height, offered) }
        return ViewSize.fixed(width, height)
    }
}

extension _AspectRatioView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let offered = (width: context.availableWidth, height: context.availableHeight)
        guard let ratio = cellRatio(context: context),
            let target = target(width: offered.width, height: offered.height, ratio: ratio)
        else { return TUIkitView.renderToBuffer(content, context: context) }
        guard target.width > offered.width || target.height > offered.height else {
            var shaped = context
            shaped.availableWidth = target.width
            shaped.availableHeight = target.height
            return TUIkitView.renderToBuffer(content, context: shaped)
        }
        // A fill larger than its space, centred in a frame of that space.
        return TUIkitView.renderToBuffer(
            content.frame(width: target.width, height: target.height)
                .frame(width: offered.width, height: offered.height),
            context: context)
    }
}
