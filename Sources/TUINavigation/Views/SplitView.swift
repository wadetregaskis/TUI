//  🖥️ TUI — A Terminal UI framework for Swift
//  SplitView.swift
//
//  SwiftUI's HSplitView and VSplitView: children in a row (or a column) with a
//  divider between each pair, which the user drags — or moves with the arrow
//  keys — to resize the two panes either side of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - Public views

/// A layout container that arranges its children in a horizontal line and
/// allows the user to resize them using dividers placed between them.
///
/// ```swift
/// HSplitView {
///     FileList()
///     Editor()
/// }
/// ```
///
/// A child that sizes to its content starts at its natural width and children
/// that fill share the rest. Each divider is a focus stop: Left and Right move
/// it a cell, five with Shift, and Home and End take it as far to the start or
/// the end as the panes' bounds allow, as a `NavigationSplitView`'s divider's do;
/// a mouse drags it. A pane is never narrower than
/// one cell, and the sizes the user chose are kept until the children change.
///
/// A pane's frame bounds it, as in SwiftUI: a pane written
/// `.frame(minWidth: 20, idealWidth: 30, maxWidth: .fixed(50))` starts 30 cells wide,
/// and the divider stops where it would take that pane — or the one on its
/// other side — below its minimum or past its maximum. The frame must be the
/// pane's own, outside anything that moves or resizes it (`.padding`, another
/// `.frame`); environment, event and lifecycle modifiers outside it are seen
/// through. A `.frame(width:)` pins the pane. When the split has too little
/// room for every pane's minimum, or more than every pane's maximum, the
/// panes give way from the last.
nonisolated public struct HSplitView<Content: View>: View {
    let content: Content

    /// Creates a horizontal split view of the given children.
    ///
    /// - Parameter content: The panes, left to right.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @MainActor public var body: some View {
        _SplitViewCore(axis: .horizontal, content: content)
    }
}

/// A layout container that arranges its children in a vertical line and allows
/// the user to resize them using dividers placed between them.
///
/// The vertical twin of ``HSplitView``: Up and Down move a divider, and a
/// pane's `.frame(minHeight:idealHeight:maxHeight:)` bounds it.
nonisolated public struct VSplitView<Content: View>: View {
    let content: Content

    /// Creates a vertical split view of the given children.
    ///
    /// - Parameter content: The panes, top to bottom.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @MainActor public var body: some View {
        _SplitViewCore(axis: .vertical, content: content)
    }
}

// MARK: - State

/// The panes' sizes along the split axis, shared between frames and the
/// divider handlers that change them.
final class SplitPaneSizes {
    var sizes: [Int] = []

    /// Each pane's bounds, as the last frame found them — read by the divider
    /// handlers, which move at event time, outside any render.
    var bounds: [SplitPaneBounds] = []
}

/// How far a pane may shrink and grow along its split's axis, and where it
/// starts: what a frame on the pane states (``SplitPaneBoundsProviding``).
struct SplitPaneBounds: Equatable {
    /// The fewest cells the pane takes — never fewer than one.
    var minimum = 1

    /// Where the pane starts, when a frame named it.
    var ideal: Int?

    /// The most cells the pane takes; `Int.max` for no limit.
    var maximum = Int.max

    /// A pane with nothing stated: anything from one cell up.
    static let free = Self()

    /// `size` held inside the bounds.
    func clamp(_ size: Int) -> Int {
        Swift.min(Swift.max(size, minimum), maximum)
    }
}

/// A view that states a split pane's bounds — a frame.
@MainActor
protocol SplitPaneBoundsProviding {
    /// The bounds this view states along `axis`.
    func splitPaneBounds(along axis: Axis) -> SplitPaneBounds
}

@MainActor extension FlexibleFrameView: SplitPaneBoundsProviding {
    /// The frame's minimum, ideal and maximum on the split's axis. A
    /// `maxWidth: .infinity` states no maximum, and a maximum below the
    /// minimum is the minimum, as a frame's own layout takes it.
    func splitPaneBounds(along axis: Axis) -> SplitPaneBounds {
        let (minimum, ideal, maximum) =
            axis == .horizontal ? (minWidth, idealWidth, maxWidth) : (minHeight, idealHeight, maxHeight)
        var bounds = SplitPaneBounds(ideal: ideal)
        if let minimum { bounds.minimum = Swift.max(1, minimum) }
        if case .fixed(let limit)? = maximum { bounds.maximum = Swift.max(bounds.minimum, limit) }
        return bounds
    }
}

extension SplitPaneBounds {
    /// The bounds a split pane's view states: those of the frame that is the
    /// pane's outermost geometry, found through the wrappers that draw their
    /// content unchanged (environment, event, focus and lifecycle modifiers),
    /// and stopping at anything else — a `.padding()` outside the frame makes
    /// the pane wider than the frame says, so its numbers no longer bound it.
    @MainActor
    static func of(_ view: any View, along axis: Axis) -> Self {
        var current = view
        while true {
            if let provider = current as? SplitPaneBoundsProviding {
                return provider.splitPaneBounds(along: axis)
            }
            guard let wrapper = current as? any DrawsContentUnchanged else { return .free }
            current = wrapper.wrappedContent
        }
    }
}

/// One divider: the focus stop and drag target between pane `index` and the
/// one after it.
final class _SplitPaneDividerHandler: PersistedFocusable {
    var focusID: String

    /// ``PersistedFocusable``: answers to `focusID` from now on.
    func repoint(focusID: String) { self.focusID = focusID }

    var canBeFocused = true
    let axis: Axis
    let index: Int
    let panes: SplitPaneSizes

    /// The pointer's gesture, from the sizes when it began.
    var drag = DividerDrag<[Int]>()

    /// Hides the pane after the divider — an inspector — or `nil` where the
    /// divider hides nothing. Rebuilt every render.
    var hide: (() -> Void)?

    /// The row of the divider's ▶, which a still click on hides the pane after
    /// it; `nil` without one.
    var arrowRow: Int?

    /// Where the pointer pressed, and whether it has moved since: a press and
    /// release on the ▶ with no movement between is a click on it.
    var press: (row: Int, moved: Bool)?

    init(focusID: String, axis: Axis, index: Int, panes: SplitPaneSizes) {
        self.focusID = focusID
        self.axis = axis
        self.index = index
        self.panes = panes
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        if let hide, event.key == .enter || event.key == .space {
            hide()
            return true
        }
        switch DividerKeyMove.of(event, along: axis) {
        case .by(let delta): move(by: delta)
        case .toStart: move(by: -DividerKeyMove.farthest)
        case .toEnd: move(by: DividerKeyMove.farthest)
        case nil: return false
        }
        return true
    }

    /// Moves the divider `delta` cells from where it is — or from where it was
    /// when `base` was taken — between its two panes, each kept at least a
    /// cell and inside its bounds; the panes elsewhere do not change. Where the
    /// two panes' bounds leave the divider nowhere to go, it stays.
    func move(by delta: Int, from base: [Int]? = nil) {
        var sizes = base ?? panes.sizes
        guard index + 1 < sizes.count else { return }
        let pair = sizes[index] + sizes[index + 1]
        guard pair >= 2 else { return }
        let bounds = panes.bounds.count == sizes.count ? panes.bounds : Array(repeating: .free, count: sizes.count)
        let (this, next) = (bounds[index], bounds[index + 1])
        let lowest = max(1, this.minimum, pair - next.maximum)
        let highest = min(pair - 1, this.maximum, pair - next.minimum)
        guard lowest <= highest else { return }
        sizes[index] = min(max(lowest, sizes[index] + delta), highest)
        sizes[index + 1] = pair - sizes[index]
        panes.sizes = sizes
    }
}

/// `StateStorage` property indices for ``_SplitViewCore``: the sizes, then a
/// focus id and a handler per divider at a base offset by its index. The core
/// renders its children at identities of their own, so its slots share an
/// identity with nothing that holds `@State`.
private enum SplitPaneStateIndex {
    static let sizes = 0
    static let dividerFocusIDBase = 1_000
    static let dividerHandlerBase = 2_000
}

// MARK: - Core

/// Lays the children along `axis` with a one-cell divider between each pair,
/// at the sizes ``SplitPaneSizes`` holds.
private struct _SplitViewCore<Content: View>: View, Renderable, Layoutable {
    let axis: Axis
    let content: Content

    var body: Never {
        fatalError("_SplitViewCore renders via Renderable")
    }

    private typealias StateIndex = SplitPaneStateIndex

    /// Fills what it is offered, as a split view in a window does; on an axis
    /// with no offer, its children's natural extent.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let children = resolveChildViews(from: content, context: context)
        let natural = children.map { $0.measure(proposal: .unspecified, context: context) }
        let along = natural.reduce(0) { $0 + extent(of: $1) } + max(0, children.count - 1)
        let across = natural.map { crossExtent(of: $0) }.max() ?? 0
        return ViewSize(
            width: proposal.width ?? (axis == .horizontal ? along : across),
            height: proposal.height ?? (axis == .horizontal ? across : along),
            isWidthFlexible: true, isHeightFlexible: true)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let children = resolveChildViews(from: content, context: context)
        guard !children.isEmpty, let stateStorage = context.stateStorage else { return FrameBuffer() }
        let width = max(0, context.availableWidth)
        let height = max(0, context.availableHeight)
        let total = axis == .horizontal ? width : height
        let across = axis == .horizontal ? height : width

        let panesBox: StateBox<SplitPaneSizes> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.sizes),
            default: SplitPaneSizes())
        let panes = panesBox.value
        let axis = axis
        let bounds = children.map { SplitPaneBounds.of($0.wrappedView, along: axis) }
        panes.sizes = resolvedSizes(
            panes.sizes, children: children, bounds: bounds, total: total, across: across, context: context)
        panes.bounds = bounds

        let composite = CompositeEnvironment(context.environment)
        // The pane after the last divider's toggle, an inspector's; its panes
        // are no inspector's last pane.
        let trailingToggle = axis == .horizontal ? context.environment.trailingPaneToggle : nil
        var paneContext = context
        paneContext.environment.trailingPaneToggle = nil
        var result = FrameBuffer(emptyWithWidth: width, height: height)
        var offset = 0
        for (index, child) in children.enumerated() {
            let size = panes.sizes[index]
            let buffer = child.render(
                width: axis == .horizontal ? size : across, height: axis == .horizontal ? across : size,
                context: paneContext)
            result.compositeCarryingClaimsOverNothing(
                with: buffer, at: position(offset), in: composite)
            offset += size
            guard index + 1 < children.count else { break }
            let divider = dividerBuffer(
                index: index, panes: panes, length: across,
                hides: index == children.count - 2 ? trailingToggle : nil, context: context)
            result.compositeCarryingClaimsOverNothing(
                with: divider, at: position(offset), in: composite)
            offset += 1
        }
        return result.clamped(toWidth: width, height: height)
    }

    // MARK: Geometry

    private func extent(of size: ViewSize) -> Int { axis == .horizontal ? size.width : size.height }
    private func crossExtent(of size: ViewSize) -> Int { axis == .horizontal ? size.height : size.width }
    private func position(_ offset: Int) -> (x: Int, y: Int) { axis == .horizontal ? (offset, 0) : (0, offset) }

    /// The panes' sizes for `total` cells: the stored ones while there are as
    /// many panes as before, rescaled to the new total when the split itself
    /// changed size; otherwise a fresh start — a pane whose frame names an
    /// ideal extent at that, a child that sizes to its content at its natural
    /// extent, the filling children sharing the rest, or the last child taking
    /// it when none fills. Either way held inside the panes' bounds.
    private func resolvedSizes(
        _ stored: [Int], children: [ChildView], bounds: [SplitPaneBounds], total: Int, across: Int,
        context: RenderContext
    ) -> [Int] {
        let count = children.count
        let available = max(count, total - (count - 1))
        if stored.count == count, stored.allSatisfy({ $0 >= 1 }) {
            let storedTotal = stored.reduce(0, +)
            let sizes = storedTotal == available ? stored : Self.rescaled(stored, to: available)
            return Self.fitted(sizes, within: bounds, total: available, givingFirst: Array(sizes.indices.reversed()))
        }
        let proposal =
            axis == .horizontal
            ? ProposedSize(width: nil, height: across) : ProposedSize(width: across, height: nil)
        let natural = children.map { $0.measure(proposal: proposal, context: context) }
        // A pane that names where it starts is placed there, not shared out.
        let fills = zip(natural, bounds).map { size, pane in
            pane.ideal == nil && (axis == .horizontal ? size.isWidthFlexible : size.isHeightFlexible)
        }
        var sizes = zip(natural, bounds).enumerated().map { index, pane in
            fills[index] ? 0 : max(1, pane.1.ideal ?? extent(of: pane.0))
        }
        let fixed = sizes.reduce(0, +)
        let flexibleIndices = fills.indices.filter { fills[$0] }
        // The panes that fill give and take first, then the rest; each from
        // the last.
        let order = flexibleIndices.reversed() + fills.indices.reversed().filter { !fills[$0] }
        if fixed > available || flexibleIndices.isEmpty {
            // Too little room for the natural sizes, or nothing to take the
            // rest: an even split, the remainder to the last pane.
            return Self.fitted(Self.evenly(available, among: count), within: bounds, total: available, givingFirst: order)
        }
        let shares = Self.evenly(available - fixed, among: flexibleIndices.count)
        for (share, index) in zip(shares, flexibleIndices) { sizes[index] = share }
        return Self.fitted(sizes.map { max(1, $0) }, within: bounds, total: available, givingFirst: order)
    }

    /// `sizes` held inside their panes' `bounds`, still summing to `total`:
    /// each clamped, then the difference taken up — or given back — by the
    /// panes in `order` that have room. Where none has, the split still fills
    /// what it was offered: the panes in `order` give way, past their bounds,
    /// down to a cell each, and any room left over goes to the first of them.
    private static func fitted(
        _ sizes: [Int], within bounds: [SplitPaneBounds], total: Int, givingFirst order: [Int]
    ) -> [Int] {
        guard bounds.count == sizes.count, !bounds.allSatisfy({ $0 == .free }) else { return sizes }
        var result = zip(sizes, bounds).map { size, pane in pane.clamp(size) }
        var excess = total - result.reduce(0, +)
        for index in order where excess != 0 {
            let room = excess > 0 ? bounds[index].maximum - result[index] : bounds[index].minimum - result[index]
            let step = excess > 0 ? min(excess, room) : max(excess, room)
            result[index] += step
            excess -= step
        }
        for index in order where excess < 0 {
            let step = max(excess, 1 - result[index])
            result[index] += step
            excess -= step
        }
        if excess > 0, let first = order.first { result[first] += excess }
        return result
    }

    /// `total` in `count` near-equal whole parts, dividing last so none is lost.
    private static func evenly(_ total: Int, among count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in (index + 1) * total / count - index * total / count }
    }

    /// `sizes` scaled in proportion to sum to `total`, each at least a cell,
    /// the rounding error to the last pane.
    private static func rescaled(_ sizes: [Int], to total: Int) -> [Int] {
        let sum = max(1, sizes.reduce(0, +))
        var scaled = sizes.map { max(1, $0 * total / sum) }
        scaled[scaled.count - 1] = max(1, total - scaled.dropLast().reduce(0, +))
        return scaled
    }

    // MARK: Dividers

    /// The divider after pane `index`: a rule `length` cells long, in the
    /// border colour or the accent while it holds the focus, registered as a
    /// focus stop and a drag target.
    ///
    /// With `hides`, the toggle of the pane after it — an inspector's — the
    /// rule carries a ▶ on its middle row, as a split view's leftmost divider
    /// carries a ◀: a still click on it, or Return or Space with the divider
    /// focused, hides the pane.
    private func dividerBuffer(
        index: Int, panes: SplitPaneSizes, length: Int, hides: PanelToggle?, context: RenderContext
    ) -> FrameBuffer {
        let stateStorage = context.stateStorage!
        let focusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil, defaultPrefix: "split-divider-\(index)",
            propertyIndex: StateIndex.dividerFocusIDBase + index)
        let handlerBox: StateBox<_SplitPaneDividerHandler> = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.dividerHandlerBase + index),
            default: _SplitPaneDividerHandler(focusID: focusID, axis: axis, index: index, panes: panes))
        let handler = handlerBox.value
        handler.canBeFocused = context.environment.isEnabled
        let hideAction = hides.map { toggle in toggle.action }
        handler.hide = hideAction.map { action in { action.perform() } }
        handler.arrowRow = hides == nil || length <= 0 ? nil : length / 2
        FocusRegistration.register(context: context, handler: handler, focusID: focusID)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: focusID)
        if let hides {
            FocusRegistration.publishActivationLabel(
                hides.activationLabel(named: hides.name(in: context)), context: context, isFocused: isFocused)
        }
        let showsFocus = context.indicatesFocus(isFocused)

        let palette = context.environment.palette
        let colour = showsFocus ? palette.accent : palette.border
        var buffer =
            context.environment.splitViewDividerGrip == .hidden
            ? DividerRule.buffer(across: axis, length: length, colour: colour)
            : DividerRule.buffer(across: axis, length: length, colour: colour, gripSkipping: handler.arrowRow)
        if let hides, let row = handler.arrowRow {
            buffer.lines[row] = ANSIRenderer.colorize(hides.arrow, foreground: colour.opaqueSpelling)
        }

        if context.environment.isEnabled, !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        {
            let focusManager = context.environment.focusManager
            let axis = self.axis
            let handlerID = dispatcher.register(in: context) { event in
                if event.button == .left {
                    switch event.phase {
                    case .pressed: handler.press = (event.y, false)
                    case .dragged: if event.x != 0 { handler.press?.moved = true }
                    default: break
                    }
                }
                let took = handler.drag.handle(
                    event, along: axis,
                    press: {
                        focusManager?.focus(id: focusID)
                        return handler.panes.sizes
                    },
                    move: { delta, start in handler.move(by: delta, from: start) })
                // A still click on the ▶ hides the pane after it: pressed and
                // released on its row, the pointer never moving between.
                if event.button == .left, event.phase == .released, let press = handler.press {
                    handler.press = nil
                    if !press.moved, event.x == 0, let row = handler.arrowRow, press.row == row, event.y == row {
                        handler.hide?()
                    }
                }
                return took
            }
            // A resize arrow along the axis it moves, where TUI's controls
            // set their own shapes.
            dispatcher.fileControlPointerShape(
                axis == .horizontal ? .columnResize : .rowResize, for: handlerID, in: context)
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                    handlerID: handlerID, focusID: focusID))
        }
        return buffer
    }
}
