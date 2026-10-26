//  🖥️ TUI — A Terminal UI framework for Swift
//  _ListCore+RowMenu.swift
//
//  A `List`'s half of the row menu: the selection menu of an enclosing
//  `contextMenu(forSelectionType:menu:primaryAction:)`, opened on a secondary
//  click or Shift+F10 through the host `Table` shares.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

extension _ListCore {
    /// The selection menu around this list, when it is this list's — never for
    /// a list with no selection binding. Measured on macOS 15.8: SwiftUI's
    /// such list opens no selection menu on a right-click, on a row or off
    /// one, and runs no primary action on a double-click, whatever type the
    /// menu names. (A table with no binding does take both; that is the
    /// table's, measured too.) It is also what keeps the menu honest here: a
    /// list without a binding knows its rows by `Int` — their ids where those
    /// are `Int`, their positions where they are not — so a menu naming the
    /// rows' own id type (a `UUID`, say) never matched, and one naming `Int`
    /// was handed positions as though they were ids.
    func selectionMenu(_ environment: EnvironmentValues) -> SelectionContextMenu? {
        guard hasSelectionBinding else { return nil }
        return RowContextMenuHost.selectionMenu(in: environment, rowsIdentifiedBy: SelectionValue.self)
    }

    /// Whether the list was given a selection binding, of either kind.
    private var hasSelectionBinding: Bool { singleSelection != nil || multiSelection != nil }

    /// The rows' environment under a selection menu — see
    /// ``RowContextMenuHost/yieldSecondaryClicks(in:rowsIdentifiedBy:takesMenu:)``:
    /// they yield their secondary clicks only to a menu this list takes.
    func yieldRowSecondaryClicks(in environment: inout EnvironmentValues) {
        RowContextMenuHost.yieldSecondaryClicks(
            in: &environment, rowsIdentifiedBy: SelectionValue.self, takesMenu: hasSelectionBinding)
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
            isOpen: { box.value.menu.isOpen }, contentColumns: contentColumns, opened: opened)
    }

    /// Draws the open selection menu over the list — anchored at the press,
    /// or under the cursor row when the keyboard opened it — or tears down the
    /// section a closed one left.
    ///
    /// - Parameter cursorRow: Where the cursor row is drawn in the list's
    ///   buffer — its top line and height — or `nil` when it is not. Asked
    ///   only of an open menu the keyboard opened, which is the one it hangs:
    ///   it walks the drawn rows, and every list renders through here.
    func presentRowMenu(
        over buffer: inout FrameBuffer, cursorRow: () -> (y: Int, height: Int)?, context: RenderContext
    ) {
        guard !context.isMeasuring, let selection = selectionMenu(context.environment),
            let box = rowMenuBox(context)
        else { return }
        let style = context.environment.listStyle
        // Where a row's own content starts — the column the container's mouse
        // handler measures a grab from too.
        let rowLeft = (style.showsBorder ? 1 : 0) + style.rowPadding.leading + 1
        let menu = box.value.menu
        let anchor =
            menu.isOpen && menu.openedByKeyboard
            ? cursorRow().map { (x: rowLeft, y: $0.y, height: max(1, $0.height)) } : nil
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
