//  🖥️ TUI — A Terminal UI framework for Swift
//  DepthLimit.swift
//
//  What the walk draws where views are nested too deeply for the stack, and
//  what it tells the app's developer.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What a measure or a draw does where ``StackGuard`` stops it: a size and a
/// picture that say so, and one report saying why and what to do.
///
/// Reached only past the limit: each function here is the cold half of a
/// `StackGuard.hasHeadroom()` test, so a frame that does not reach the limit
/// runs none of it.
///
/// **A measure answers the notice's size, not zero.** A measure past the limit
/// used to answer 0×0. A `VStack` holding only that child then measured 0 rows,
/// so did the `VStack` holding it, and so on to the root, which was allotted
/// no rows at all: the whole page clamped away to nothing, with the "⋯" the
/// draw substituted among it. Everything above the limit stood on a size
/// measured below it. Answering one row keeps every level above it on screen.
///
/// **What is below is kept, not dropped.** Nothing below the limit is walked, so
/// its `@State` looks gone from the tree to the end-of-pass prune. It is retained
/// instead, as a collapsed `DisclosureGroup`'s is: where the limit falls depends
/// on the thread's stack, and so can move between frames with the tree unchanged.
///
/// **Nothing kept outlives it.** A buffer or a size that holds the notice is
/// dropped at the next pass (``RenderCache/clearsAtNextPass``), so a page that
/// has become shallower is drawn afresh rather than served its old notice.
///
/// **A walk that keeps stopping stops sooner.** The stack bounds how deep a
/// descent goes, not how many there are: see `StackGuard.noteStop()`.
@MainActor
package enum DepthLimit {
    /// What is drawn in place of a view past the limit. Starts with the one
    /// glyph that still says something in a single cell.
    package static let notice = "⋯ nested too deeply to draw"

    /// ``notice``, as a row. Bound once: a tree past the limit asks for it at
    /// every place the descent stops.
    private static let noticeRow = FrameBuffer(text: notice)

    /// The size of a view a measure stopped at: what ``drawn(_:context:)`` draws.
    ///
    /// - Parameters:
    ///   - type: The view's type, for the report.
    ///   - proposal: The proposal it was measured with.
    ///   - context: The context it was measured in.
    @inline(never)
    package static func measured(_ type: Any.Type, proposal: ProposedSize, context: RenderContext) -> ViewSize {
        note(type, context: context)
        let width = min(noticeRow.width, max(0, proposal.width ?? context.availableWidth))
        let height = min(1, max(0, min(proposal.height ?? .max, context.availableHeight)))
        return .fixed(width, height)
    }

    /// What is drawn in place of a view a draw stopped at, in the space it has.
    ///
    /// - Parameters:
    ///   - type: The view's type, for the report.
    ///   - context: The context it was to draw in, at its own identity.
    @inline(never)
    package static func drawn(_ type: Any.Type, context: RenderContext) -> FrameBuffer {
        note(type, context: context)
        // Not for a measure that draws: nothing is dropped on its account.
        if !context.isMeasuring {
            context.renderCache?.drewDepthLimitNotice = true
            // The view's own `@State` is at its own identity, which a retained
            // root does not cover: only what is below it.
            context.stateStorage?.markActive(context.identity)
            context.stateStorage?.retainSubtree(context.identity)
        }
        return noticeRow.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// `frame`, with ``notice`` on it: as it is if a whole notice was drawn,
    /// otherwise on the last row of the screen.
    ///
    /// For a frame the draw stopped in (``RenderCache/drewDepthLimitNotice``)
    /// whose notice did not survive: an earlier level had already taken all the
    /// space, so the place it was drawn had none, or a view hugging a deep leaf
    /// cut it short. A frame that is cut down and says nothing is the thing this
    /// type exists to prevent, however few rows are left.
    ///
    /// - Parameters:
    ///   - frame: The frame the walk drew.
    ///   - width: The screen's width.
    ///   - height: The screen's height.
    package static func showingNotice(on frame: FrameBuffer, width: Int, height: Int) -> FrameBuffer {
        guard !frame.lines.contains(where: { $0.contains(notice) }), width > 0, height > 0 else { return frame }
        let row = noticeRow.clamped(toWidth: width, height: 1)
        return frame.composited(with: row, at: (x: 0, y: min(frame.height, height - 1)))
    }

    /// Counts the stop, tells the render cache, and tells the app's developer
    /// the first time: the guard has just counted this stop, so a count of one
    /// is the process's first. Once, rather than once a type, which is all
    /// ``SoftTrap`` would do for words that name one.
    private static func note(_ type: Any.Type, context: RenderContext) {
        StackGuard.noteStop()
        context.renderCache?.clearsAtNextPass = true
        if StackGuard.truncationCount == 1 { SoftTrap.warn(message(stoppedAt: type)) }
    }

    /// The report: what happened, why, and what to do.
    private static func message(stoppedAt type: Any.Type) -> String {
        """
        Views are nested too deeply to draw: the stack ran short at \(type), so what is below it \
        shows "\(notice)" and the rest of the page draws as usual, rather than the app crashing. \
        A view that contains itself needs a case where it stops. A tree this deep is better shown \
        a few levels at a time: a List with children, or a NavigationStack. What is below comes \
        back, with its state, when the nesting is shallower.
        """
    }
}
