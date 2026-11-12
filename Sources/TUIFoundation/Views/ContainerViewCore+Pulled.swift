//  🖥️ TUI — A Terminal UI framework for Swift
//  ContainerViewCore+Pulled.swift
//
//  SCROLL-FIT's forward shape through a box (design B-SCROLLFIT-12): a pulled
//  view in a box's body — `GroupBox { LazyVStack }`, a `.border()`ed lazy
//  stack — is handed the scroll view's request below the box's top line, and
//  the box draws itself round the band the body answers: its top line only
//  when the band holds the body's first row, its footer and bottom line only
//  when it holds the last. So the rows of a lazy stack in a box are built only
//  while on screen, as they are in a column.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// The body is a child of the box's among two (`Content` at 0, `Footer` at
/// 1), so a lazy stack in it is pulled only because the box is a container
/// that forwards (`ScrollPlacing`).
extension _ContainerViewCore: ScrollPlacing {}

@MainActor extension _ContainerViewCore {
    /// Files this box pulled, or withdraws it, once its measure has measured
    /// the body at `body`, and answers the body's size when the box holds a
    /// pulled view: measured offered no height, so the box's height is the
    /// body's estimate whatever the space offered. A column walks across the
    /// box by that height; capped at the space, End landed inside the box.
    /// `nil` when the body holds no pulled view.
    func pulledBodySize(body: RenderContext, innerWidth: Int, context: RenderContext) -> ViewSize? {
        context.notePulledContainer(holding: { [body.identity] })
        guard context.renderCache?.pullConsumers.kind(of: context.identity) == .pullsChildren else { return nil }
        return measureChild(
            content.padding(padding), proposal: ProposedViewSize(width: innerWidth, height: nil), context: body)
    }

    /// The lines this box draws above its body: its top border, or a
    /// borderless box's title row.
    var pulledLinesAbove: Int { style.hasBorder || title != nil ? 1 : 0 }

    /// The relay that hands the body at `body` the request this box was
    /// handed, below the box's top line and above its footer and bottom line,
    /// addressed to the body; `nil` when no request reaches this box as one
    /// holding a pulled view, and the box draws its body whole.
    ///
    /// A box whose body scrolls itself (a dialog's) holds its own scroll
    /// view, at which the content is pulled afresh.
    func pulledRelay(body: RenderContext, footerHeight: Int, context: RenderContext) -> PulledChromeRelay? {
        guard !style.scrollsOverflowingBody else { return nil }
        let separator = footer != nil && footerHeight > 0 && style.showFooterSeparator ? 1 : 0
        let below = (style.hasBorder ? 1 : 0) + (footer != nil ? footerHeight + separator : 0)
        return PulledChromeRelay(
            context: context, linesAbove: pulledLinesAbove, linesBelow: { below }, addressing: body.identity)
    }

    /// The body's measured width, at most `innerWidth`: what the box is as
    /// wide as while its body draws a band, whose own width is only the rows
    /// it holds. A memo hit, the box's measure having asked the same.
    func pulledBodyWidth(_ body: RenderContext, innerWidth: Int) -> Int {
        let size = measureChild(
            content.padding(padding), proposal: ProposedViewSize(width: innerWidth, height: body.availableHeight),
            context: body)
        return min(size.width, innerWidth)
    }
}
