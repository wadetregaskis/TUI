//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _ListCore+RowMenu.swift
//
//  A `List`'s half of the row menu: the selection menu of an enclosing
//  `contextMenu(forSelectionType:menu:primaryAction:)`, opened on a secondary
//  click or Shift+F10 through the host `Table` shares.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension _ListCore {
    /// The selection menu around this list, when it is this list's.
    func selectionMenu(_ environment: EnvironmentValues) -> SelectionContextMenu? {
        RowContextMenuHost.selectionMenu(in: environment, rowsIdentifiedBy: SelectionValue.self)
    }

    /// The row menu's state, at this list's identity.
    func rowMenuBox(_ context: RenderContext) -> StateBox<RowMenuState>? {
        RowContextMenuHost.stateBox(context, propertyIndex: Self.rowMenuStateIndex)
    }

    /// Shift+F10's half: opens the selection menu on the cursor row. `nil`
    /// for a list without one, so the chord falls through.
    func keyboardMenuOpener(
        _ handler: ItemListHandler<SelectionValue>, context: RenderContext
    ) -> (() -> Bool)? {
        guard selectionMenu(context.environment) != nil, let box = rowMenuBox(context) else {
            return nil
        }
        let onOpen = context.environment.menuOpenAction
        return { [weak handler] in
            guard let handler else { return false }
            RowContextMenuHost.openByKeyboard(
                box,
                target: .selection(RowContextMenuHost.targets(ofRow: handler.focusedIndex, in: handler)),
                onOpen: onOpen)
            return true
        }
    }

    /// The pointer's half: opens the selection menu on a row (or on none) at a
    /// press. `nil` for a list without one.
    func pointerMenu(
        handler: ItemListHandler<SelectionValue>, context: RenderContext,
        dispatcher: MouseEventDispatcher, contentColumns: Range<Int>,
        opened: @escaping @MainActor () -> Void
    ) -> RowContextMenuHost.PointerMenu? {
        guard selectionMenu(context.environment) != nil, let box = rowMenuBox(context) else {
            return nil
        }
        let onOpen = context.environment.menuOpenAction
        return RowContextMenuHost.PointerMenu(
            open: { index, x, y in
                RowContextMenuHost.openByPointer(
                    box, target: .selection(RowContextMenuHost.targets(ofRow: index, in: handler)),
                    x: x, y: y, dispatcher: dispatcher, onOpen: onOpen)
                return true
            },
            isOpen: { box.value.menu.isOpen }, contentColumns: contentColumns, opened: opened,
            dispatcher: dispatcher)
    }

    /// Draws the open selection menu over the list — anchored at the press,
    /// or under the cursor row when the keyboard opened it — or tears down the
    /// section a closed one left.
    ///
    /// - Parameter cursorRow: Where the cursor row is drawn in the list's
    ///   buffer — its top line and height — or `nil` when it is not.
    func presentRowMenu(
        over buffer: inout FrameBuffer, cursorRow: (y: Int, height: Int)?, context: RenderContext
    ) {
        guard !context.isMeasuring, let selection = selectionMenu(context.environment),
            let box = rowMenuBox(context)
        else { return }
        let style = context.environment.listStyle
        // Where a row's own content starts — the column the container's mouse
        // handler measures a grab from too.
        let rowLeft = (style.showsBorder ? 1 : 0) + style.rowPadding.leading + 1
        let anchor = cursorRow.map { (x: rowLeft, y: $0.y, height: max(1, $0.height)) }
        let items: AnyView?
        if case .selection(let ids) = box.value.target {
            items = selection.menu(for: ids)
        } else {
            items = nil
        }
        RowContextMenuHost.present(
            items: items, over: &buffer, stateBox: box,
            sectionID: "listmenu-\(context.identity.path)", keyboardAnchor: anchor, context: context)
    }
}
