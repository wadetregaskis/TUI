//  🖥️ TUI — A Terminal UI framework for Swift
//  SwipeActionsModifier.swift
//
//  A list row's swipe actions: buttons a row reveals at one of its edges, from
//  the keyboard — a terminal has no swipe gesture to reveal them with.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension View {
    /// Adds custom swipe actions to a row in a list.
    ///
    /// Write it on a row of a `List`. The actions are buttons, revealed at
    /// `edge` of the row and drawn over it: a destructive one in red, the rest
    /// in their tint.
    ///
    /// ```swift
    /// List {
    ///     ForEach(messages) { message in
    ///         MessageRow(message)
    ///             .swipeActions {
    ///                 Button("Delete", role: .destructive) { delete(message) }
    ///                 Button("Flag") { flag(message) }.tint(.orange)
    ///             }
    ///             .swipeActions(edge: .leading) {
    ///                 Button("Unread") { markUnread(message) }.tint(.blue)
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// TUI-specific: a terminal reports no swipe, so the actions are revealed
    /// from the keyboard, on the list's cursor row — ⇧→ the leading edge's and
    /// ⇧← the trailing edge's, or ⌃L and ⌃T where the terminal does not report
    /// Shift on the arrows (``RowAction/revealLeadingSwipeActions`` and
    /// ``RowAction/revealTrailingSwipeActions``, rebindable through
    /// `rowShortcuts`). Revealed, the buttons hold the keyboard: ← and →, Tab
    /// and Shift-Tab move between them, Return or Space presses one, and
    /// Escape slides them away; the same chord again is the full swipe, which
    /// presses the first, where `allowsFullSwipe` is true. A click on a button
    /// presses it, and a click anywhere else slides them away.
    ///
    /// - Parameters:
    ///   - edge: The edge of the row the actions are revealed at.
    ///   - allowsFullSwipe: Whether a full swipe performs the first action.
    ///   - content: The actions, as `Button`s.
    /// - Returns: A row with swipe actions.
    public func swipeActions<T: View>(
        edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: () -> T
    ) -> some View {
        _SwipeActionsView(content: self, actions: content(), edge: edge, allowsFullSwipe: allowsFullSwipe)
    }
}

/// A row with swipe actions: reports them to its list as it renders, and
/// draws them while the list has revealed them.
///
/// - Important: Framework infrastructure. Created by
///   ``View/swipeActions(edge:allowsFullSwipe:content:)``.
public struct _SwipeActionsView<Content: View, Actions: View>: View {
    let content: Content
    let actions: Actions
    let edge: HorizontalEdge
    let allowsFullSwipe: Bool

    public var body: Never {
        fatalError("_SwipeActionsView renders via Renderable")
    }
}

extension _SwipeActionsView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIView.renderToBuffer(content, context: context)
        guard !context.isMeasuring, let restrictions = context.environment.listRowEditRestrictions,
            let row = restrictions.currentRowIndex
        else { return buffer }
        guard context.environment.isEnabled else { return buffer }
        report(row: row, context: context)
        if let reveal = restrictions.swipeReveal, reveal.row == row, reveal.edge == edge {
            drawRevealed(over: &buffer, reveal: reveal, context: context)
        }
        return buffer
    }

    /// Tells the list this row has actions on its edge. Replayable, as a row
    /// menu's report is, so a row served from a memo reports again.
    private func report(row: Int, context: RenderContext) {
        let (edge, allowsFullSwipe) = (edge, allowsFullSwipe)
        SwipeActionsReporter.report(edge: edge, allowsFullSwipe: allowsFullSwipe, context: context)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(
                    kind: SwipeActionsReporter.kind, channelToken: context.environment.keyChannelToken
                ) { replay in
                    SwipeActionsReporter.report(edge: edge, allowsFullSwipe: allowsFullSwipe, context: replay)
                })
        }
    }

    /// The actions revealed: drawn over the row's `edge`, holding the keyboard
    /// as a menu does (`claimKeyboardAsMenu`), each a menu row of a sink of
    /// their own so the highlight and the full swipe can press them.
    private func drawRevealed(over buffer: inout FrameBuffer, reveal: ListRowSwipeReveal, context: RenderContext) {
        guard context.environment.mouseEventDispatcher != nil, let storage = context.stateStorage else { return }
        let strip: SwipeStrip = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: SwipeActionsStateIndex.strip),
            default: SwipeStrip()
        ).value
        let sectionID = "swipe-\(context.identity.path)"
        let hide = reveal.hide
        claimKeyboardAsMenu(sectionID: sectionID, dismiss: { hide() }, context: context)

        strip.sink.beginPass()
        var stripContext = context.withChildIdentity(erasedType: Actions.self, index: 0)
        stripContext.environment.menuRowSink = strip.sink
        stripContext.environment.menuHighlightedOrdinal = strip.highlighted
        stripContext.environment.dismissMenu = DismissMenuAction { hide() }
        stripContext.environment.activeFocusSectionID = sectionID
        // `.borderedProminent`'s look: a destructive action in red, the rest in
        // their tint, and the highlighted one breathing as a focused button does.
        stripContext.environment.buttonStyle = BorderedProminentButtonStyle().appearance
        stripContext.availableWidth = max(1, context.availableWidth)
        var drawn = TUIView.renderToBuffer(HStack(spacing: 0) { actions }, context: stripContext)
        if strip.highlighted == nil || !strip.sink.selectableOrdinals.contains(strip.highlighted!) {
            strip.highlighted = strip.sink.selectableOrdinals.first
        }
        DropdownMenu.attachDismissBackdrop(to: &drawn, context: context, onDismiss: { hide() })
        attachKeys(strip: strip, sectionID: sectionID, hide: hide, context: context)

        let rowWidth = max(buffer.width, context.availableWidth)
        buffer.overlays.append(
            OverlayLayer(
                offsetX: edge == .leading ? 0 : max(0, rowWidth - drawn.width), offsetY: 0, content: drawn,
                level: .popover, anchorHeight: 0, holdsInput: true
            ).presenting(context.identity))
    }

    /// The revealed actions' keys, in their section: ← and →, Tab and
    /// Shift-Tab move the highlight among the actions, round the ends; Return
    /// and Space press the highlighted one; Escape slides them away; the chord
    /// that revealed this edge presses the first where a full swipe is allowed,
    /// and the other edge's slides them away.
    private func attachKeys(strip: SwipeStrip, sectionID: String, hide: @escaping @MainActor () -> Void, context: RenderContext) {
        let shortcuts = context.environment.listRowEditRestrictions?.swipeKeys
        let (edge, allowsFullSwipe) = (edge, allowsFullSwipe)
        context.environment.keyEventDispatcher?.addHandler(sectionID: sectionID) { [weak strip] event in
            guard let strip, event.phase != .release else { return false }
            if let revealed = shortcuts?(event) {
                if revealed == edge, allowsFullSwipe, let first = strip.sink.selectableOrdinals.first {
                    strip.sink.activate(ordinal: first)
                }
                hide()
                return true
            }
            switch event.key {
            case .left, .right, .tab:
                let forward = event.key == .right || (event.key == .tab && !event.shift)
                strip.step(forward ? 1 : -1)
            case .enter, .space:
                if let highlighted = strip.highlighted { strip.sink.activate(ordinal: highlighted) }
                hide()
            case .escape, .up, .down:
                hide()
            default:
                return false
            }
            return true
        }
    }
}

extension _SwipeActionsView: Layoutable {
    /// Measures as its content: the actions are drawn over it.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper — read-only, as `.deleteDisabled`'s is.
extension _SwipeActionsView: SingleContentWrapper {
    public var wrappedContent: Content { content }

    public func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _SwipeActionsView: DrawsContentUnchanged {}

/// `_SwipeActionsView`'s StateStorage property indices, negative: the wrapper
/// renders its caller's content at its own identity (`StateStorage.StateKey`).
/// Outside the generic type, which can hold no static stored property.
private enum SwipeActionsStateIndex {
    static let strip = -170
}

// MARK: - The revealed strip

/// The revealed actions' rows and highlight, kept from frame to frame while
/// they are revealed.
@MainActor
private final class SwipeStrip {
    /// What each action button published as it drew: its action, by ordinal.
    let sink = MenuRowSink()

    /// The action the keyboard is on.
    var highlighted: Int?

    /// Moves the highlight `offset` actions along, round the ends.
    func step(_ offset: Int) {
        let ordinals = sink.selectableOrdinals
        guard !ordinals.isEmpty else { return }
        let index = highlighted.flatMap(ordinals.firstIndex(of:)) ?? 0
        highlighted = ordinals[((index + offset) % ordinals.count + ordinals.count) % ordinals.count]
    }
}

/// A row's swipe actions reported to its list, shared by the live render and
/// by a memo replaying it.
@MainActor
private enum SwipeActionsReporter {
    /// The journal kind of the report.
    static let kind = EffectJournal.Kind("swipeActions.listRow")

    /// Reports actions on `edge` to the list row `context` is drawing.
    static func report(edge: HorizontalEdge, allowsFullSwipe: Bool, context: RenderContext) {
        guard let restrictions = context.environment.listRowEditRestrictions,
            let row = restrictions.currentRowIndex
        else { return }
        restrictions.reportSwipeActions(row: row, edge: edge, allowsFullSwipe: allowsFullSwipe)
    }
}
