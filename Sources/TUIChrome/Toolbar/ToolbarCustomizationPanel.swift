//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarCustomizationPanel.swift
//
//  Where the person customizes a toolbar: the bar's context menu, and the
//  panel it opens, listing the toolbar's items to put in or take out and move.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - The Bar's Customization

/// A bar row of a window with a customizable toolbar: its context menu — a
/// right-click on the row, or Shift+F10 while one of its items has the focus —
/// offers Customize Toolbar… (and the label styles, where the scene bound its
/// label style), and the customization panel hangs from it while the person
/// customizes.
///
/// Pure composition: the shared context-menu and popover presentations of
/// TUIFoundation, round the row.
struct _ToolbarCustomizationHost<Content: View>: View {
    /// The bar's row.
    let content: Content

    /// The window's chrome, which holds the customizable toolbars this walk
    /// declared and which one the panel is open on.
    let chrome: WindowChromeState

    @Environment(\.toolbarLabelStyle) private var labelStyle

    var body: some View {
        let chrome = chrome
        let customizing = chrome.customizableToolbars.first { $0.id == chrome.customizingToolbarID }
        PopoverPresentationModifier(
            content: ContextMenuModifier(content: content, menuItems: menuItems, keyboardRoute: .contentStops),
            isPresented: Binding(
                get: { customizing != nil },
                set: { if !$0 { chrome.customizingToolbarID = nil } }),
            popover: customizing.map {
                _ToolbarCustomizationPanel(
                    toolbar: $0, labelStyle: labelStyle, choosesLabelStyle: chrome.choosesToolbarLabelStyle,
                    close: { chrome.customizingToolbarID = nil })
            },
            attachmentAnchor: .rect(.bounds), arrowEdge: .bottom)
    }

    /// The context menu: the label styles, where the person may choose one,
    /// and Customize Toolbar….
    @ViewBuilder private var menuItems: some View {
        let chrome = chrome
        if let choose = chrome.choosesToolbarLabelStyle {
            ForEach(_ToolbarCustomizationPanel.labelStyles.indices, id: \.self) { index in
                let (style, key) = _ToolbarCustomizationPanel.labelStyles[index]
                Toggle(
                    LocalizationService.shared.string(for: key),
                    isOn: Binding(get: { labelStyle == style }, set: { if $0 { choose(style) } }))
            }
            Divider()
        }
        Button(LocalizationService.shared.string(for: LocalizationKey.Label.customizeToolbar)) {
            chrome.beginCustomizingToolbar()
        }
    }
}

// MARK: - The Panel

/// The customization panel: each of the toolbar's customizable items, in the
/// order the bars draw them — a checkbox that puts it in the bar or takes it
/// out, and ▲ and ▼ to move it among the others in its place, its region of
/// its bar's row — then the label styles where the scene bound its label
/// style, Reset, and Done.
///
/// Every control is a `Toggle` or a `Button`, so Tab walks them, Space and
/// Return act, and a click does what the key would. An item the person may
/// not take out (`.reorderable`, `.disabled`) has its checkbox disabled, and
/// one they may not move (`.disabled`) its arrows, as has an arrow with no
/// movable item beyond it in the item's place. An item the app hid
/// (`hidden(_:)`) is listed, as SwiftUI lists it during customization, and
/// stays out of the bar whatever its checkbox says, until the app shows it.
struct _ToolbarCustomizationPanel: View {
    /// The toolbar being customized.
    let toolbar: CustomizableToolbarDeclaration

    /// The window's label style, if the scene states one.
    let labelStyle: ToolbarLabelStyle?

    /// Sets the window's label style, where the scene bound it.
    let choosesLabelStyle: (@MainActor (Any) -> Void)?

    /// Closes the panel.
    let close: () -> Void

    /// The label styles a person may choose, with their names, in macOS's
    /// order.
    static var labelStyles: [(ToolbarLabelStyle, LocalizationKey.Label)] {
        [(.titleAndIcon, .iconAndText), (.iconOnly, .iconOnly), (.titleOnly, .textOnly)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Over the items themselves, keyed by identifier: over their
            // indices, each row read its item from the captured list, and the
            // row memo, keyed by the index, served a place's last row after a
            // move — ▼ on SHARE listed PRINT twice.
            ForEach(toolbar.items, id: \.id) { item in
                row(item)
            }
            if let choose = choosesLabelStyle {
                Divider()
                HStack(spacing: 1) {
                    Text(LocalizationService.shared.string(for: LocalizationKey.Label.toolbarShow))
                    ForEach(Self.labelStyles.indices, id: \.self) { index in
                        let (style, key) = Self.labelStyles[index]
                        Toggle(
                            LocalizationService.shared.string(for: key),
                            isOn: Binding(get: { labelStyle == style }, set: { if $0 { choose(style) } }))
                    }
                }
            }
            Divider()
            HStack(spacing: 1) {
                Button(LocalizationService.shared.string(for: LocalizationKey.Button.reset)) { toolbar.reset() }
                Spacer(minLength: 1)
                Button(LocalizationService.shared.string(for: LocalizationKey.Button.done)) { close() }
            }
        }
    }

    /// One item: its checkbox, labelled with the item as the bar draws it —
    /// inert here — and its arrows.
    private func row(_ item: CustomizableToolbarDeclaration.Item) -> some View {
        let toolbar = toolbar
        return HStack(spacing: 1) {
            Toggle(isOn: Binding(get: { item.isShown }, set: { toolbar.setShown(item.id, $0) })) {
                item.view.disabled(true)
            }
            .disabled(!item.isRemovable)
            Button("▲") { toolbar.move(item.id, -1) }
                .disabled(!item.canMoveEarlier)
            Button("▼") { toolbar.move(item.id, 1) }
                .disabled(!item.canMoveLater)
        }
    }
}
