//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledChromeRelay.swift
//
//  SCROLL-FIT's forward shape (design B-SCROLLFIT-12) for a container that
//  draws lines of its own above and below one child it holds a pulled view
//  in: a box's top line and footer (`ContainerViewCore+Pulled.swift`), a tab
//  view's strip, a navigation stack's bar over a pushed screen. The child is
//  handed the scroll view's request below the lines above it, and the
//  container keeps of its own lines only those the band the child answers
//  reaches: those above with the child's first row, those below with its
//  last.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// The scroll view's request relayed through a container that draws
/// `linesAbove` lines above one child and some below it, when that child
/// holds a pulled view; package-wide, for the containers outside this module.
@MainActor
package struct PulledChromeRelay {
    private let relay: ScrollWindowRelay
    private let linesAbove: Int

    /// The relay for the container at `context` around the child at
    /// `content`, or `nil` when the container draws it whole: a measure, no
    /// request reaching the container, or nothing pulled below it
    /// (``RenderContext/notePulledContainer(holding:)``, which its measure
    /// files).
    package init?(context: RenderContext, linesAbove: Int, linesBelow: () -> Int, addressing content: ViewIdentity) {
        guard !context.isMeasuring,
            context.renderCache?.pullConsumers.kind(of: context.identity) == .pullsChildren,
            let relay = ScrollWindowRelay(
                context: context, linesAbove: linesAbove, linesBelow: linesBelow, addressing: content)
        else { return nil }
        self.relay = relay
        self.linesAbove = linesAbove
    }

    /// The context the child is drawn in: the request moved below the
    /// container's lines above it.
    package func contentContext(_ context: RenderContext) -> RenderContext { relay.contentContext(context) }

    /// `whole`, the container drawn round `content` — the band the child
    /// answered — `linesAbove` lines down, cut to the lines of the container
    /// the band holds, the container's reply answered on the way.
    package func banded(_ whole: FrameBuffer, content: FrameBuffer) -> FrameBuffer {
        let placement = relay.answer(
            contentBuffer: content, linesBelow: max(0, whole.height - linesAbove - content.height))
        let top = placement.drawsAbove ? 0 : linesAbove
        let bottom = placement.drawsBelow ? whole.height : linesAbove + content.height
        return whole.lines(in: top..<bottom)
    }
}
