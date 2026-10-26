//  🖥️ TUI — A Terminal UI framework for Swift
//  RowContextMenuHost.swift
//
//  The one menu a `List` or `Table` opens on its rows — the selection menu of
//  `contextMenu(forSelectionType:menu:primaryAction:)`, or a `TableRow`'s own
//  `contextMenu(menuItems:)` — with what it acts on resolved when it opens.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - State

/// What a row menu was opened on.
package enum RowMenuTarget {
    /// The selection menu, for these rows' ids — none for empty space.
    case selection([AnyHashable])

    /// One row's own menu, by the row's id.
    case row(AnyHashable)
}

/// A list's or table's row menu: whether it is open, where, and on what.
///
/// Kept in the container's state storage, a class changed in place and
/// written back through its box when it opens — the write that drops a memo
/// holding the closed container, as ``ContextMenuState``'s is for
/// `.contextMenu`, whose presentation this shares.
@MainActor
package final class RowMenuState {
    /// Open, anchor, the menu's highlight: the context menu's own state.
    package let menu = ContextMenuState()

    /// What the open menu acts on.
    package var target: RowMenuTarget { get { _target } set { _target = newValue } }

    /// ``target``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _target: RowMenuTarget = .selection([])
}

// MARK: - The host

/// Opening, drawing and closing a row menu — one host for `List` and `Table`,
/// so the two resolve a press, anchor a menu and give the keyboard back
/// identically.
@MainActor
package enum RowContextMenuHost {
    /// Whether `event` is a secondary click: the right button, or Ctrl with the
    /// left where a terminal keeps the right button for itself — the
    /// `.contextMenu` rule.
    package static func isSecondary(_ event: MouseEvent) -> Bool {
        event.button == .right || (event.button == .left && event.ctrl)
    }

    /// The selection menu around a container whose rows are identified by
    /// `ID`, when it is that container's: SwiftUI's never activates on a
    /// container whose selection type is not the one it names.
    package static func selectionMenu<ID>(
        in environment: EnvironmentValues, rowsIdentifiedBy type: ID.Type
    ) -> SelectionContextMenu? {
        guard let reference = environment.selectionContextMenu, reference.menu.isFor(type)
        else { return nil }
        return reference.menu
    }

    /// The row menu's state, at the container's identity and `propertyIndex`.
    package static func stateBox(_ context: RenderContext, propertyIndex: Int) -> StateBox<RowMenuState>? {
        context.stateStorage?.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: propertyIndex),
            default: RowMenuState())
    }

    /// Hands a container's rows the environment they render under while a
    /// selection menu is around the container: a list inside a row does not
    /// take the outer menu for its own, and — when the container takes it
    /// (``selectionMenu(in:rowsIdentifiedBy:)``, and `takesMenu`) — the menu
    /// answers every secondary click on the rows, so a `.contextMenu` inside a
    /// row adds none of its own. A menu the container does not take, one for
    /// another item type or around a list with no selection binding, never
    /// activates, and leaves the rows' own menus be. Written only where a menu
    /// is present, so a container without one pays one read.
    package static func yieldSecondaryClicks<ID>(
        in environment: inout EnvironmentValues, rowsIdentifiedBy type: ID.Type, takesMenu: Bool = true
    ) {
        guard let reference = environment.selectionContextMenu else { return }
        environment.selectionContextMenu = nil
        if takesMenu, reference.menu.isFor(type) { environment.rowsYieldSecondaryClick = true }
    }

    /// What Return and a double-click do to a row: the selection menu's
    /// primary action, on the rows the menu's rule gives for the activated
    /// row. `nil` when there is none, which leaves Return to select.
    ///
    /// The action is read when a row is activated, not when this is built:
    /// the menu is the modifier's state, refreshed by every body, and the
    /// closure it holds then is the latest one.
    package static func activation<ID: Hashable>(
        for handler: ItemListHandler<ID>, selection: SelectionContextMenu?
    ) -> ((ID) -> Void)? {
        guard let selection, selection.primaryAction != nil else { return nil }
        return { [weak handler] id in
            guard let handler else { return }
            let index =
                handler.id(at: handler.focusedIndex) == id ? handler.focusedIndex : handler.index(of: id)
            selection.primaryAction?(targets(ofRow: index, in: handler))
        }
    }

    /// The rule a selection menu and a primary action act by, for a press on
    /// (or the cursor's being on) the row at `index`: the whole selection when
    /// that row is in it, the row alone when it is not, and nothing for no
    /// row. Measured on macOS for the menu; the primary action follows the
    /// same rule, so Return on a row the selection does not include acts on
    /// the row the cursor marks.
    package static func targets<ID: Hashable>(
        ofRow index: Int?, in handler: ItemListHandler<ID>
    ) -> [AnyHashable] {
        guard let index, let id = handler.id(at: index) else { return [] }
        guard handler.isSelected(at: index) else { return [AnyHashable(id)] }
        switch handler.selectionMode {
        case .single:
            return [AnyHashable(id)]
        case .multi:
            return (handler.multiSelection?.wrappedValue ?? [id]).map { AnyHashable($0) }
        }
    }

    /// A container's row menu as its mouse handler reaches it: built once a
    /// frame, for a container that has a menu to open.
    package struct PointerMenu {
        /// Opens the menu on a row — or on none — at a press's cell,
        /// answering whether one opened.
        let open: @MainActor (_ row: Int?, _ x: Int, _ y: Int) -> Bool

        /// Whether the menu is open.
        package let isOpen: @MainActor () -> Bool

        /// The columns the rows occupy: a press on the border opens nothing.
        package let contentColumns: Range<Int>

        /// The lines the rows occupy: a press on a table's column header opens
        /// nothing — measured on macOS 15.8, SwiftUI's header takes no menu of
        /// the table's, and a right-click there goes on to a menu around the
        /// table. Every line, for a list, which has no header.
        package var contentLines: Range<Int>

        /// What a press that opened the menu does besides: focus the container.
        package let opened: @MainActor () -> Void

        /// The memberwise initializer, written out: a synthesized one is
        /// internal, and a table in TUITables makes these (module split,
        /// step C2).
        package init(
            open: @escaping @MainActor (_ row: Int?, _ x: Int, _ y: Int) -> Bool,
            isOpen: @escaping @MainActor () -> Bool, contentColumns: Range<Int>,
            contentLines: Range<Int> = 0..<Int.max, opened: @escaping @MainActor () -> Void
        ) {
            self.open = open
            self.isOpen = isOpen
            self.contentColumns = contentColumns
            self.contentLines = contentLines
            self.opened = opened
        }
    }

    /// The events a container's mouse handler answers before its own clicks:
    /// the wheel, which scrolls; and a secondary click, which opens its menu.
    ///
    /// - Parameters:
    ///   - event: The event.
    ///   - wheel: The container's wheel handling, answering whether it took
    ///     the event.
    ///   - menu: The container's row menu, or `nil` when it has none.
    ///   - row: The row under the event, asked only for a press that opens.
    /// - Returns: `true` when the event is spent — scrolled, or a press that
    ///   opened a menu; `false` for a right press with nothing to open, which
    ///   then goes on to a menu around the container; `nil` for an event the
    ///   container's own handling answers — any other, and a Ctrl-click with
    ///   nothing to open, which is still a click.
    package static func preflight(
        _ event: MouseEvent, wheel: (MouseEvent) -> Bool, menu: PointerMenu?, row: () -> Int?
    ) -> Bool? {
        if wheel(event) { return true }
        // The drags and the release of a gesture whose press opened a pop-up —
        // this container's menu or another's — never get here. Drawn, the
        // pop-up's backdrop covers the screen and takes them; not drawn —
        // before a render pass has begun since it opened, or once its opener
        // says it is closed — the dispatcher spends them
        // (``MouseEventDispatcher/pressOpenedPopup(_:)``), the quick click and
        // the slow one alike. That leaves no gap only because every opener's
        // "open" means drawn: a `Picker` with no options was open and drew
        // nothing, the dispatcher took it for on screen, and its gesture went
        // live onto these rows.
        guard let menu, isSecondary(event) else { return nil }
        if event.phase == .pressed, menu.contentColumns.contains(event.x),
            menu.contentLines.contains(event.y), menu.open(row(), event.x, event.y)
        {
            menu.opened()
            return true
        }
        if event.button == .right { return event.phase != .pressed && menu.isOpen() }
        return menu.isOpen() ? true : nil
    }

    /// Opens the menu at a secondary press, at the press's cell.
    ///
    /// The rest of the gesture belongs to the menu, as `.contextMenu`'s does:
    /// press, drag down the rows, release on one to run it. A gesture that
    /// moves and lets go before a frame has drawn the menu closes it, as it
    /// would have closed the drawn menu wherever it let go
    /// (``MouseEventDispatcher/pressOpenedPopup(_:)``).
    package static func openByPointer(
        _ stateBox: StateBox<RowMenuState>, target: RowMenuTarget, x: Int, y: Int,
        dispatcher: MouseEventDispatcher, onOpen: MenuOpenAction?
    ) {
        let state = stateBox.value
        state.target = target
        state.menu.anchorX = x
        state.menu.anchorY = y
        state.menu.isOpen = true
        state.menu.openedByKeyboard = false
        state.menu.controller.opened(withSelection: false)
        stateBox.value = state
        onOpen?()
        dispatcher.handOffGesture()
        dispatcher.pressOpenedPopup(state.menu.openedPopup)
    }

    /// Opens the menu from the keyboard: on its first item, anchored under the
    /// cursor row when it is drawn (see ``present(items:over:stateBox:sectionID:keyboardAnchor:context:)``).
    package static func openByKeyboard(
        _ stateBox: StateBox<RowMenuState>, target: RowMenuTarget, onOpen: MenuOpenAction?
    ) {
        let state = stateBox.value
        state.target = target
        state.menu.isOpen = true
        state.menu.openedByKeyboard = true
        state.menu.controller.opened(withSelection: true)
        stateBox.value = state
        onOpen?()
    }

    /// Draws the open menu over the container, or tears down the section a
    /// just-closed one left — call on every render pass of the container.
    ///
    /// - Parameters:
    ///   - items: The menu's items for the target it was opened on, or `nil`
    ///     when there are none — a menu that builds nothing, a row that has
    ///     gone, a selection type that does not match. The menu then closes
    ///     without having been shown: SwiftUI's "return nothing to deactivate
    ///     the menu".
    ///   - buffer: The container, already rendered.
    ///   - keyboardAnchor: Where a menu opened from the keyboard hangs: under
    ///     the cursor row's lines (`x`, the row's top `y`, its `height`), or
    ///     `nil` when the row is not drawn, which hangs it under the container.
    package static func present(
        items: @autoclosure () -> AnyView?, over buffer: inout FrameBuffer,
        stateBox: StateBox<RowMenuState>, sectionID: String,
        keyboardAnchor: (x: Int, y: Int, height: Int)?, context: RenderContext
    ) {
        guard !context.isMeasuring else { return }
        let state = stateBox.value
        guard state.menu.isOpen else {
            // The first closed frame after a menu tears its section down, so
            // the page's focus is restored rather than left on a section that
            // has gone — a side effect no memo replays, and only that frame
            // has one.
            if state.menu.needsSectionTeardown {
                context.environment.volatileReadTracker?.recordRenderSideEffect()
                context.environment.focusManager?.deactivateSection(id: sectionID)
                state.menu.needsSectionTeardown = false
            }
            return
        }
        let dismiss = { state.menu.close() }
        guard let menuItems = items(), drawsAnything(menuItems, context: context) else {
            dismiss()
            return
        }
        state.menu.needsSectionTeardown = true
        let anchor: MenuAnchor
        if state.menu.openedByKeyboard {
            anchor =
                keyboardAnchor.map { MenuAnchor(x: $0.x, y: $0.y + $0.height, controlHeight: $0.height) }
                ?? MenuAnchor(
                    x: 0, y: buffer.height, controlHeight: buffer.height, centredWithin: buffer.width)
        } else {
            anchor = MenuAnchor(x: state.menu.anchorX, y: state.menu.anchorY, controlHeight: 0)
        }
        presentMenuPopover(
            items: _RowMenuItems(items: menuItems), over: &buffer,
            controller: state.menu.controller, sectionID: sectionID, itemsIndex: 0, anchor: anchor,
            dismiss: dismiss, context: context)
        ContextMenuPresentation.attachKeyboardCloser(
            state: state.menu, sectionID: sectionID, context: context)
    }

    /// Whether `items` draws anything at all — a menu closure that returned
    /// nothing for this set is an empty view, and an empty menu must not take
    /// the keyboard with nothing on screen to give it back.
    private static func drawsAnything(_ items: AnyView, context: RenderContext) -> Bool {
        var probe = context
        probe.isMeasuring = true
        let size = measureChild(
            _RowMenuItems(items: items), proposal: ProposedSize(width: nil, height: nil),
            context: probe)
        return size.width > 0 && size.height > 0
    }
}

/// A row menu's items, under a type of their own so their identity cannot
/// meet any of the container's rows.
private struct _RowMenuItems: View {
    let items: AnyView

    var body: some View { items }
}
