//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SidebarSectionMover.swift
//
//  How a person moves a tab view sidebar's sections: from the keyboard on a
//  section's header, as a list's row is moved, or by dragging the header.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitFoundation
import TUIkitView

/// The section a ``_SidebarSectionMover`` has in hand, by id, and the order of
/// the movable sections it shows while it does.
struct _HeldSidebarSection: Equatable {
    let section: Int
    let order: [Int]
}

/// What a dragged sidebar section carries: its id among the sidebar's
/// sections (``_SidebarSection/id``), and the mover it belongs to, so a header
/// takes only its own sidebar's sections.
struct _SidebarSectionDrag {
    let section: Int
    let mover: ObjectIdentifier
}

/// Moves a ``_SidebarSectionList``'s movable sections (decisions B79): with a
/// section's header focused — its fold — the list's pick-up chord (Ctrl-R),
/// then the arrows, Home or End, then Return puts it down where it now is, and
/// Escape — or the focus leaving the header — puts it back; the list's move
/// chords (Ctrl/Option with an arrow, Option with Home or End) move it at
/// once. The pointer drags a header onto
/// another, and the section takes that one's place.
///
/// A movable section moves among the movable sections' places, as a
/// customization's section order arranges them; the sections around them keep
/// theirs. The order is the list's to write, through the closure it hands
/// over (`commit`), and is written once a move is put down: the sections show
/// a move in hand in its own order, and nothing is written until then.
///
/// One object for the list's life — its state — so the decoration the headers
/// read (``SectionHeaderDecoration``) compares equal from frame to frame. What
/// it moves and how it writes are handed over again on every evaluation of
/// the list's body.
@MainActor
final class _SidebarSectionMover: SectionHeaderDecorating {
    /// The section in hand, by id, and the order of the movable sections
    /// while it is — the list's state.
    var held: Binding<_HeldSidebarSection?> = .constant(nil)

    /// The movable sections' ids, in their order now.
    var movable: [Int] = []

    /// Writes a new order of the movable sections.
    var commit: ([Int]) -> Void = { _ in }

    /// The list's row shortcuts, which these moves answer to.
    var shortcuts = RowShortcutLookup.default

    func decorate(_ header: AnyView, section: Int) -> AnyView {
        guard movable.contains(section) else { return header }
        let handle = _SectionHeaderHandle(
            content: header, section: section, mover: self, isHeld: held.wrappedValue?.section == section)
        return AnyView(
            FocusPathModifier(content: handle, stage: .keyPress) { [weak self] _ in
                { event in self?.handle(event, section: section) ?? false }
            })
    }

    // MARK: - Keys

    /// Answers `event`, pressed with the focus on `section`'s header.
    func handle(_ event: KeyEvent, section: Int) -> Bool {
        guard event.phase != .release, movable.contains(section) else { return false }
        let bound = shortcuts.action(for: event)
        guard let hold = held.wrappedValue else {
            guard let bound else { return false }
            return handleChord(bound, section: section)
        }
        guard hold.section == section else {
            // A key on another header lets the section in hand go back.
            held.wrappedValue = nil
            return false
        }
        switch event.key {
        case .up: shift(hold, by: -1)
        case .down: shift(hold, by: 1)
        case .home: shift(hold, by: -hold.order.count)
        case .end: shift(hold, by: hold.order.count)
        default:
            guard let bound else {
                // Anything else — Tab, say — puts it back and goes on.
                held.wrappedValue = nil
                return false
            }
            heldChord(bound, hold: hold)
        }
        return true
    }

    /// A chord on a header with nothing in hand: the pick-up, or a move at
    /// once.
    private func handleChord(_ bound: (action: RowAction, accelerated: Bool), section: Int) -> Bool {
        let step = bound.accelerated ? movable.count : 1
        switch bound.action {
        case .pickUpRow:
            held.wrappedValue = _HeldSidebarSection(section: section, order: movable)
        case .moveRowUp: commit(Self.moving(section, in: movable, by: -step))
        case .moveRowDown: commit(Self.moving(section, in: movable, by: step))
        case .moveRowToTop, .moveRowPageUp: commit(Self.moving(section, in: movable, by: -movable.count))
        case .moveRowToBottom, .moveRowPageDown: commit(Self.moving(section, in: movable, by: movable.count))
        case .selectAll, .extendSelection, .placeRow, .cancelMove, .sortNextColumn, .reverseSortOrder,
            .customizeColumns:
            return false
        }
        return true
    }

    /// A chord with a section in hand.
    private func heldChord(_ bound: (action: RowAction, accelerated: Bool), hold: _HeldSidebarSection) {
        let step = bound.accelerated ? hold.order.count : 1
        switch bound.action {
        case .placeRow, .pickUpRow:
            held.wrappedValue = nil
            if hold.order != movable { commit(hold.order) }
        case .cancelMove: held.wrappedValue = nil
        case .moveRowUp: shift(hold, by: -step)
        case .moveRowDown: shift(hold, by: step)
        case .moveRowToTop, .moveRowPageUp: shift(hold, by: -hold.order.count)
        case .moveRowToBottom, .moveRowPageDown: shift(hold, by: hold.order.count)
        case .selectAll, .extendSelection, .sortNextColumn, .reverseSortOrder, .customizeColumns:
            break
        }
    }

    /// Puts `section` back if it is in hand: the focus has left its header,
    /// and with it the keys that would place it or put it back — as a list
    /// puts back a row in hand when it loses the focus.
    func letGo(_ section: Int) {
        guard held.wrappedValue?.section == section else { return }
        held.wrappedValue = nil
    }

    /// Moves the section in hand `offset` places in the order it shows.
    private func shift(_ hold: _HeldSidebarSection, by offset: Int) {
        held.wrappedValue = _HeldSidebarSection(
            section: hold.section, order: Self.moving(hold.section, in: hold.order, by: offset))
    }

    // MARK: - Dragging

    /// Moves `dragged` into `target`'s place, the sections between them
    /// stepping aside — the order a drag dropped on `target`'s header asks
    /// for. `false` where nothing moves.
    func drop(_ dragged: Int, onto target: Int) -> Bool {
        guard dragged != target, let from = movable.firstIndex(of: dragged), let to = movable.firstIndex(of: target)
        else { return false }
        held.wrappedValue = nil
        commit(Self.moving(dragged, in: movable, by: to - from))
        return true
    }

    /// `order` with `section` moved `offset` places, clamped to its ends.
    static func moving(_ section: Int, in order: [Int], by offset: Int) -> [Int] {
        guard let from = order.firstIndex(of: section) else { return order }
        var moved = order
        moved.remove(at: from)
        moved.insert(section, at: min(max(0, from + offset), moved.count))
        return moved
    }
}

/// A movable section's header: drawn faint while its section is in hand,
/// from the keyboard or the pointer — the look a list gives a row it is
/// moving — with a drag handle that carries the section and a drop zone that
/// takes another of its sidebar's sections.
///
/// The handle forwards a press released without moving to the header's fold
/// beneath it, so a click still folds the section. Not `.draggable(_:)`, which
/// draws the view it is carrying as blank cells: a blank header is no row to a
/// list, which closed up under the pointer as the drag began and moved the
/// headers it was aimed at.
private struct _SectionHeaderHandle: View, Renderable, Layoutable {
    let content: AnyView
    let section: Int
    let mover: _SidebarSectionMover
    let isHeld: Bool

    var body: Never { fatalError("_SectionHeaderHandle renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if isHeld, !context.isMeasuring, !Self.holdsFocus(context) {
            // The focus left the header some way other than a key on it — a
            // click elsewhere — so the section goes back. Drawn in hand this
            // once: the write asks for the frame that draws it back, and the
            // focus move cleared what contains this header, so it is drawn
            // again then rather than served.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            mover.letGo(section)
        }
        var buffer = TUIkitView.renderToBuffer(content, context: context)
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher,
            let session = context.environment.dragAndDropSession
        else { return isHeld ? Self.faint(buffer) : buffer }
        let identity = context.identity
        if isHeld || session.isDragSource(within: identity) { buffer = Self.faint(buffer) }
        let (section, mover) = (self.section, self.mover)
        let own = ObjectIdentifier(mover)
        let title = buffer.lines.first.map { $0.stripped.trimmingCharacters(in: .whitespaces) } ?? ""
        let preview = FrameBuffer(lines: [" \(title) "])
        let anchor = context.environment.dragPreviewAnchor
        _DragHandle.install(
            on: &buffer, context: context, dispatcher: dispatcher,
            onDragBegin: { _, grab in
                session.begin(
                    payload: _SidebarSectionDrag(section: section, mover: own), preview: preview,
                    grabX: grab.x, grabY: grab.y, anchor: anchor, source: identity)
            },
            onDragMove: { _ in session.dragMoved() },
            onDragEnd: { _ in _ = session.performDrop() })
        DropZone.install(
            on: &buffer, context: context,
            accepts: { ($0 as? _SidebarSectionDrag)?.mover == own },
            perform: { payload, _ in
                guard let drag = payload as? _SidebarSectionDrag else { return false }
                return mover.drop(drag.section, onto: section)
            },
            setTargeted: { _ in })
        return buffer
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    /// Whether the focus is on the header — its fold — or inside it.
    private static func holdsFocus(_ context: RenderContext) -> Bool {
        guard let focused = context.environment.focusManager?.focusedIdentity else { return false }
        return focused == context.identity || context.identity.isAncestor(of: focused)
    }

    /// `buffer` drawn faint, its regions and claims carried.
    private static func faint(_ buffer: FrameBuffer) -> FrameBuffer {
        var faint = buffer
        faint.lines = buffer.lines.map(ANSIRenderer.applyPersistentDim)
        return faint
    }
}
