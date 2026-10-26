//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuSubmenus.swift
//
//  A submenu: a row of a pop-up menu that opens a menu of its own beside it.
//  SwiftUI makes one of a `Menu` written in a menu, and of a `Picker` — measured
//  on macOS 15.8, `Tools/SwiftUIProbes/Menu items and alert buttons/pickers.out`.
//
//  The row is a `Button` of the menu like any other — it claims an ordinal and
//  takes the row's look — and publishes, beside its ordinal, how to draw the
//  submenu (`MenuSubmenu`). The menu's controller keeps which submenu is open
//  (`MenuPopupController.openSubmenu`), and the menu that draws the row draws
//  the submenu over itself, as a layer of its own layer, hung beside the row:
//  so wherever the compositor puts the menu, the submenu goes with it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - What a submenu row publishes

/// How to draw the submenu a row of a pop-up menu opens — what the row
/// publishes to its menu's column, beside its ordinal.
///
/// Drawn with the context the row was drawn in, so the submenu's items see the
/// environment written round the `Menu` or `Picker` that made the row, and keep
/// their `@State` under it.
@MainActor
final class MenuSubmenu {
    /// Draws the submenu open, with `controller`'s highlight.
    let draw: (_ controller: MenuPopupController) -> FrameBuffer

    /// Renders the submenu's items, closed, for the keyboard shortcuts they
    /// register alone (``registerMenuItemShortcuts(_:context:)``).
    let registerShortcuts: () -> Void

    init(
        draw: @escaping (_ controller: MenuPopupController) -> FrameBuffer,
        registerShortcuts: @escaping () -> Void
    ) {
        self.draw = draw
        self.registerShortcuts = registerShortcuts
    }
}

// MARK: - The row

/// A row of a pop-up menu that opens a submenu of `items`, labelled `label`,
/// with the submenu caret (▸) where a row's key equivalent goes — what a `Menu`
/// or a `Picker` written in a pop-up `Menu` or a `.contextMenu` draws as.
///
/// Enabled whatever the environment says: a disabled `Menu` or `Picker` in a
/// macOS menu is a submenu of disabled items, which still opens (measured,
/// `pickers.out`). The items are drawn in the environment as it was, so they
/// are the ones disabled.
///
/// Outside a pop-up column (``EnvironmentValues/isInPopUpMenu``) this is not
/// drawn; the view that makes it draws itself instead.
package struct _MenuSubmenuRow<Label: View, Items: View>: View, Renderable, Layoutable {
    let label: Label
    let items: Items

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIMenus makes these, for a `Menu`, and TUIPickers,
    /// for a `Picker`.
    package init(label: Label, items: Items) {
        self.label = label
        self.items = items
    }

    package var body: Never {
        fatalError("_MenuSubmenuRow renders via Renderable")
    }

    package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(row, proposal: proposal, context: rowContext(context))
    }

    package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(row, context: rowContext(context))
    }

    /// The row: a button of the menu, which claims an ordinal and draws as a
    /// menu row. Its action is never run — choosing the row opens the submenu
    /// (``MenuPopupController/choose(_:byKeyboard:)``).
    private var row: Button {
        Button(action: {}, label: { label })
    }

    /// The row's context: enabled, carrying the caret, and — on a render —
    /// the submenu, which the row's button publishes with its ordinal.
    private func rowContext(_ context: RenderContext) -> RenderContext {
        var row = context.withChildIdentity(erasedType: Label.self, index: MenuSubmenuChildIndex.row)
        row.environment.isEnabled = true
        row.environment.menuRowOpensSubmenu = true
        if !context.isMeasuring {
            let items = items
            let itemsContext = Self.itemsContext(context)
            let dismiss = context.environment.dismissMenu
            row.environment.menuSubmenu = MenuSubmenu(
                draw: { controller in
                    renderMenuLevel(items, context: itemsContext, controller: controller, dismiss: { dismiss?() })
                },
                registerShortcuts: { registerMenuItemShortcuts(items, context: itemsContext) })
        }
        return row
    }

    /// The context the submenu's items are drawn in: the one this row was,
    /// one identity step in, over the whole screen, with nothing of the
    /// column it sits in — its row width, its inset, its rows' channel, its
    /// highlight — which the submenu's own column states afresh.
    private static func itemsContext(_ context: RenderContext) -> RenderContext {
        var items = context
            .withChildIdentity(erasedType: Items.self, index: MenuSubmenuChildIndex.items)
            .withAvailableWidth(context.environment.terminalWidth)
            .withAvailableHeight(context.environment.overlayContentHeight)
        items.environment.menuRowSink = nil
        items.environment.menuHighlightedOrdinal = nil
        items.environment.menuRowWidth = nil
        items.environment.menuRowInset = 0
        items.environment.menuRowOpensSubmenu = false
        items.environment.menuSubmenu = nil
        return items
    }
}

/// ``_MenuSubmenuRow``'s child-identity indices: the row's `Button`, and the
/// submenu's items. A free enum because the row is generic.
private enum MenuSubmenuChildIndex {
    static let row = 0
    static let items = 1
}

// MARK: - Drawing a menu with its open submenu

/// Draws `items` as an open pop-up menu (``renderMenuPopup(_:context:controller:dismiss:)``)
/// and, where `controller` has a submenu open, that submenu beside the row
/// that opened it — a layer of the menu's buffer, so it goes wherever the menu
/// is put, its first row level with that row. A submenu that would run off the
/// right edge goes to the menu's other side, and one that would run off the
/// bottom slides up (``OverlayLayer/besideAnchorWidth``).
///
/// A submenu whose row is gone, or disabled, this frame is closed.
@MainActor
func renderMenuLevel(
    _ items: some View, context: RenderContext, controller: MenuPopupController,
    dismiss: @escaping () -> Void
) -> FrameBuffer {
    var buffer = renderMenuPopup(items, context: context, controller: controller, dismiss: dismiss)
    guard !context.isMeasuring else { return buffer }
    // The closed submenus' items' key equivalents work while this menu is up,
    // as the open one's do: rendered for their registrations alone.
    for row in controller.sink.submenuRows where row.ordinal != controller.openSubmenu?.ordinal {
        row.submenu.registerShortcuts()
    }
    guard let open = controller.openSubmenu else { return buffer }
    guard let submenu = controller.sink.submenu(at: open.ordinal),
        let line = controller.drawnLine(ofOrdinal: open.ordinal)
    else {
        controller.closeSubmenu()
        return buffer
    }
    let drawn = submenu.draw(open.controller)
    guard !drawn.isEmpty else { return buffer }
    // The submenu's top border on the line above the row, so its first row is
    // level with it; its left border against the menu's right one.
    var layer = OverlayLayer(
        offsetX: buffer.width, offsetY: line - 1, content: drawn, level: .popover, holdsInput: true)
    layer.besideAnchorWidth = buffer.width
    buffer.overlays.append(layer)
    return buffer
}

// MARK: - Key equivalents of items not drawn

/// Renders a menu's `items` — as an open menu's column renders them, with no
/// row channel — for the keyboard shortcuts they register alone: every other
/// channel thrown away, and nothing asked of the frame
/// (``RenderContext/withRegistrationOnlyChannels()``).
///
/// What makes an item's key equivalent work while the menu it is in is not
/// drawn: a closed submenu's, while the menu it opens from is up, and every
/// submenu's of a menu bar's closed menu, which the bar renders this way each
/// frame — where a `Menu` among them renders its own items so too (`_MenuPopupCore`,
/// under ``EnvironmentValues/rendersForRegistrationsOnly``), and theirs.
@MainActor
package func registerMenuItemShortcuts(_ items: some View, context: RenderContext) {
    context.withThrowawayFrameDemand { quiet in
        var unseen = quiet.withRegistrationOnlyChannels()
        // Tall enough for every row: a row a column had no room for would
        // never render, and never register its key.
        unseen.availableHeight = 4096
        unseen.hasExplicitHeight = false
        _ = TUIView.renderToBuffer(
            VStack(alignment: .leading, spacing: 0) { _MenuSectionedItems(items: items) }, context: unseen)
    }
}

// MARK: - Environment

private struct MenuRowOpensSubmenuKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MenuSubmenuKey: EnvironmentKey {
    static let defaultValue: MenuSubmenu? = nil
}

private struct RendersForRegistrationsOnlyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this view draws inside an open pop-up menu's column — a pop-up
    /// `Menu`, a `.contextMenu`, a menu bar's menu — where a `Menu` or a
    /// `Picker` is a submenu row (``_MenuSubmenuRow``). Not inside an INLINE
    /// menu, whose rows are the page's.
    package var isInPopUpMenu: Bool { menuRowSink != nil }

    /// Whether the menu row below draws the submenu caret where its key
    /// equivalent would go: set by ``_MenuSubmenuRow`` on its button, read by
    /// the menu row's style.
    var menuRowOpensSubmenu: Bool {
        get { self[MenuRowOpensSubmenuKey.self] }
        set { self[MenuRowOpensSubmenuKey.self] = newValue }
    }

    /// The submenu the button below opens, which it publishes with its
    /// ordinal: set by ``_MenuSubmenuRow`` on a render, directly on the
    /// context it hands its button, so it reaches that button and nothing
    /// else (the submenu's own items are drawn in a context without it).
    var menuSubmenu: MenuSubmenu? {
        get { self[MenuSubmenuKey.self] }
        set { self[MenuSubmenuKey.self] = newValue }
    }

    /// Whether this render is for the keyboard shortcuts it registers alone
    /// (``RenderContext/withRegistrationOnlyChannels()``): where a closed
    /// pop-up `Menu` renders its items too, so a menu bar's submenus' items,
    /// and a closed submenu's submenus', register their keys.
    package internal(set) var rendersForRegistrationsOnly: Bool {
        get { self[RendersForRegistrationsOnlyKey.self] }
        set { self[RendersForRegistrationsOnlyKey.self] = newValue }
    }
}
