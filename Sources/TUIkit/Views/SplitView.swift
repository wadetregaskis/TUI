//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitView.swift
//
//  SwiftUI's HSplitView and VSplitView: children in a row (or a column) with a
//  divider between each pair, which the user drags — or moves with the arrow
//  keys — to resize the two panes either side of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

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
/// it a cell, five with Shift; a mouse drags it. A pane is never narrower than
/// one cell, and the sizes the user chose are kept until the children change.
public struct HSplitView<Content: View>: View {
    let content: Content

    /// Creates a horizontal split view of the given children.
    ///
    /// - Parameter content: The panes, left to right.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        _SplitViewCore(axis: .horizontal, content: content)
    }
}

/// A layout container that arranges its children in a vertical line and allows
/// the user to resize them using dividers placed between them.
///
/// The vertical twin of ``HSplitView``: Up and Down move a divider.
public struct VSplitView<Content: View>: View {
    let content: Content

    /// Creates a vertical split view of the given children.
    ///
    /// - Parameter content: The panes, top to bottom.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        _SplitViewCore(axis: .vertical, content: content)
    }
}

// MARK: - State

/// The panes' sizes along the split axis, shared between frames and the
/// divider handlers that change them.
final class SplitPaneSizes {
    var sizes: [Int] = []
}

/// One divider: the focus stop and drag target between pane `index` and the
/// one after it.
final class _SplitPaneDividerHandler: PersistedFocusable {
    var focusID: String
    var canBeFocused = true
    let axis: Axis
    let index: Int
    let panes: SplitPaneSizes

    /// The sizes when the current drag began, which every drag event moves the
    /// divider relative to; `nil` when no drag is under way.
    var dragStart: [Int]?

    init(focusID: String, axis: Axis, index: Int, panes: SplitPaneSizes) {
        self.focusID = focusID
        self.axis = axis
        self.index = index
        self.panes = panes
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        let step = event.shift ? 5 : 1
        switch (axis, event.key) {
        case (.horizontal, .left), (.vertical, .up): move(by: -step)
        case (.horizontal, .right), (.vertical, .down): move(by: step)
        default: return false
        }
        return true
    }

    /// Moves the divider `delta` cells from where it is — or from where it was
    /// when `base` was taken — between its two panes, each kept at least a
    /// cell; the panes elsewhere do not change.
    func move(by delta: Int, from base: [Int]? = nil) {
        var sizes = base ?? panes.sizes
        guard index + 1 < sizes.count else { return }
        let pair = sizes[index] + sizes[index + 1]
        guard pair >= 2 else { return }
        sizes[index] = min(max(1, sizes[index] + delta), pair - 1)
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
        panes.sizes = resolvedSizes(panes.sizes, children: children, total: total, across: across, context: context)

        let palette = context.environment.palette
        var result = FrameBuffer(emptyWithWidth: width, height: height)
        var offset = 0
        for (index, child) in children.enumerated() {
            let size = panes.sizes[index]
            let buffer = child.render(
                width: axis == .horizontal ? size : across, height: axis == .horizontal ? across : size,
                context: context)
            result.compositeCarryingClaimsOverNothing(with: buffer, at: position(offset), palette: palette)
            offset += size
            guard index + 1 < children.count else { break }
            let divider = dividerBuffer(index: index, panes: panes, length: across, context: context)
            result.compositeCarryingClaimsOverNothing(with: divider, at: position(offset), palette: palette)
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
    /// changed size; otherwise a fresh start — a child that sizes to its
    /// content at its natural extent, the filling children sharing the rest,
    /// or the last child taking it when none fills.
    private func resolvedSizes(
        _ stored: [Int], children: [ChildView], total: Int, across: Int, context: RenderContext
    ) -> [Int] {
        let count = children.count
        let available = max(count, total - (count - 1))
        if stored.count == count, stored.allSatisfy({ $0 >= 1 }) {
            let storedTotal = stored.reduce(0, +)
            guard storedTotal != available else { return stored }
            return Self.rescaled(stored, to: available)
        }
        let proposal =
            axis == .horizontal
            ? ProposedSize(width: nil, height: across) : ProposedSize(width: across, height: nil)
        let natural = children.map { $0.measure(proposal: proposal, context: context) }
        let fills = natural.map { axis == .horizontal ? $0.isWidthFlexible : $0.isHeightFlexible }
        var sizes = zip(natural, fills).map { size, fills in fills ? 0 : max(1, extent(of: size)) }
        let fixed = sizes.reduce(0, +)
        let flexibleIndices = fills.indices.filter { fills[$0] }
        if fixed > available || flexibleIndices.isEmpty {
            // Too little room for the natural sizes, or nothing to take the
            // rest: an even split, the remainder to the last pane.
            return Self.evenly(available, among: count)
        }
        let shares = Self.evenly(available - fixed, among: flexibleIndices.count)
        for (share, index) in zip(shares, flexibleIndices) { sizes[index] = share }
        return sizes.map { max(1, $0) }
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
    private func dividerBuffer(
        index: Int, panes: SplitPaneSizes, length: Int, context: RenderContext
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
        FocusRegistration.register(context: context, handler: handler, focusID: focusID)
        let isFocused = context.indicatesFocus(FocusRegistration.isFocused(context: context, focusID: focusID))

        let palette = context.environment.palette
        let glyph = axis == .horizontal ? "│" : "─"
        let painted = ANSIRenderer.colorize(
            glyph, foreground: (isFocused ? palette.accent : palette.border).opaqueSpelling)
        var buffer =
            axis == .horizontal
            ? FrameBuffer(lines: Array(repeating: painted, count: length))
            : FrameBuffer(lines: [String(repeating: painted, count: length)])

        if context.environment.isEnabled, !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        {
            let focusManager = context.environment.focusManager
            let axis = self.axis
            let handlerID = dispatcher.register(in: context) { event in
                guard event.button == .left else { return false }
                switch event.phase {
                case .pressed:
                    focusManager?.focus(id: focusID)
                    handler.dragStart = handler.panes.sizes
                    return true
                case .dragged, .released:
                    // Localised to the press, so the coordinate along the
                    // split is the signed distance moved.
                    if let start = handler.dragStart {
                        handler.move(by: axis == .horizontal ? event.x : event.y, from: start)
                    }
                    if event.phase == .released { handler.dragStart = nil }
                    return true
                default:
                    return false
                }
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                    handlerID: handlerID, focusID: focusID))
        }
        return buffer
    }
}
