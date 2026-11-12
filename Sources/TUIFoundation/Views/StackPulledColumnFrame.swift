//  🖥️ TUI — A Terminal UI framework for Swift
//  StackPulledColumnFrame.swift
//
//  The children of a pulled column (`StackPulledColumn.swift`) as one frame's
//  fill sees them: built and measured as the fill reaches them, the anchored
//  child's extent its last known end, and the column the engine walks
//  (`ScrollColumnFill.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - The column the engine walks

/// One pulled frame's children, as the walk (`ScrollColumnFill.swift`) sees
/// them: measured as it reaches them, a pulled child's pitch its last known
/// end where it holds the anchor, its measure's estimate elsewhere.
@MainActor
final class PulledColumnFrame {
    let children: ChildViewCollection
    let spacing: Int
    let state: StackWindowState
    let anchor: ScrollContentAnchor
    let proposal: ProposedViewSize
    let context: RenderContext

    /// Extents better known than a measure says them: the anchored child's,
    /// when it is pulled — its end, in its own lines, as it last drew.
    var knownHeights: [Int: Int] = [:]
    private var heights: [Int: Int] = [:]
    private var widths: [Int: Int] = [:]
    private var pulledRows: [Int: Bool] = [:]
    private var built: [Int: ChildView] = [:]
    private(set) var sawSpacer = false
    /// The children beside the focused control, by the edge of theirs it
    /// stands past (``ScrollContentWindow/focusBeyond``).
    var focusBeyond: [Int: VerticalEdge] = [:]
    /// The requests this frame handed its pulled children, by identity.
    var handed: [ViewIdentity: ScrollContentWindow] = [:]
    /// Whether the pulled children are asked for the rows of a stack marked
    /// with `scrollTargetLayout()`: the scroll view has a behaviour to settle
    /// on them, and the column is not marked itself.
    var asksTargetLayout = false
    /// The scroll view's `.anchorPosition` binding, which the column hands
    /// only to the child the viewport's top lies in, with the request to hold
    /// the row it names (``ScrollContentWindow/holdsDesignatedRow``).
    var heldRow: AnchorPositionBinding?
    /// Where the focus ring stood when the fill began: what the rows above the
    /// anchor, drawn after it and the rows below, file their controls at.
    var focusMark: (manager: FocusManager, mark: FocusRegistrationMark)?

    /// Draws `body`, a row above every row drawn since the fill began, its
    /// controls filed ahead of theirs in the focus ring
    /// (`FocusManager.registering(at:_:)`): so the ring runs in the rows'
    /// order, as an eager column's does, wherever the fill started.
    func drawingAbove<T>(_ body: () -> T) -> T {
        guard let focusMark else { return body() }
        return focusMark.manager.registering(at: focusMark.mark, body)
    }

    init(
        children: ChildViewCollection, spacing: Int, state: StackWindowState, anchor: ScrollContentAnchor,
        proposal: ProposedViewSize, context: RenderContext
    ) {
        self.children = children
        self.spacing = spacing
        self.state = state
        self.anchor = anchor
        self.proposal = proposal
        self.context = context
    }

    func child(at ordinal: Int) -> ChildView {
        if let child = built[ordinal] { return child }
        let child = children[ordinal]
        built[ordinal] = child
        return child
    }

    /// Row `ordinal`'s height: measured, once a frame. The measure is also
    /// what files a pulled view (`PullConsumers`), so it comes before
    /// ``isPulled(_:)`` asks.
    func height(of ordinal: Int) -> Int {
        if let known = knownHeights[ordinal] { return known }
        if let height = heights[ordinal] { return height }
        let child = child(at: ordinal)
        if child.isSpacer { sawSpacer = true }
        let size = child.measure(proposal: proposal, context: context)
        // A row only measured never renders, and nothing else marks it: kept
        // alive across the pass's prune, as the anchored walk keeps its own.
        context.renderCache?.markActive(child.identity(under: context))
        heights[ordinal] = size.height
        widths[ordinal] = size.width
        state.recordMeasuredPitch(max(1, size.height) + (ordinal < children.count - 1 ? spacing : 0))
        return size.height
    }

    func measuredWidth(of ordinal: Int) -> Int {
        _ = height(of: ordinal)
        return widths[ordinal] ?? 0
    }

    /// The lines between row `ordinal` and the next: the column's spacing,
    /// after a row that drew some, as a column charges it.
    func gap(after ordinal: Int) -> Int {
        ordinal < children.count - 1 && height(of: ordinal) > 0 ? spacing : 0
    }

    func pitch(of ordinal: Int) -> Int { height(of: ordinal) + gap(after: ordinal) }

    /// Whether a pulled view sits below row `ordinal`, so that it is handed a
    /// request rather than drawn whole.
    func isPulled(_ ordinal: Int) -> Bool {
        if let pulled = pulledRows[ordinal] { return pulled }
        _ = height(of: ordinal)
        let identity = child(at: ordinal).identity(under: context)
        let pulled = context.renderCache?.pullConsumers.holdsConsumer(below: identity) ?? false
        pulledRows[ordinal] = pulled
        return pulled
    }
}

extension PulledColumnFrame: ScrollFillColumn {
    var rowCount: Int { children.count }
    /// Up to the windowing threshold the walk measures its way across a jump
    /// too: a column of a few rows, one of them a pulled stack thousands of
    /// lines tall, prices a row at an average no row is near — three one-line
    /// headers over 800 rows put a jump of 398 lines into the second header.
    var walksJumps: Bool { children.count <= _VStackCore<EmptyView>.anchoredWindowThreshold }
    func key(at ordinal: Int) -> String? { children.key(at: ordinal) }
    func firstOrdinal(forKey key: String) -> Int? { children.firstOrdinal(forKey: key) }
    var ladder: [String: Int] { state.rowOrdinalMemo }
    var estimatedPitch: Int { state.estimatedPitch(spacing: spacing) }
}
