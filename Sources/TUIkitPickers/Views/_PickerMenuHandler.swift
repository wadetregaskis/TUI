//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _PickerMenuHandler.swift
//
//  The focus and keyboard half of a menu-style `Picker`, split from the
//  rendering half so each stays readable: `_PickerMenuCore` draws the collapsed
//  control and the open drop-down, and this decides what the keys do.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

/// The focus and keyboard handler for a menu-style ``Picker``.
///
/// Persisted across renders via `StateStorage` so the open/closed state and
/// the highlighted option survive re-rendering. While closed, Enter, Space,
/// or Down opens the drop-down; while open, the arrow keys move the
/// highlight, Enter or Space commits it, and Escape closes without changing
/// the selection. A typed character, while open, moves the highlight to the
/// option it starts.
final class _PickerMenuHandler: PersistedFocusable {
    var focusID: String

    /// ``PersistedFocusable``: answers to `focusID` from now on.
    func repoint(focusID: String) { self.focusID = focusID }

    var selection: Binding<AnyHashable>
    var itemValues: [AnyHashable]
    var canBeFocused: Bool

    /// Whether the drop-down list is currently expanded — drawn, which is what
    /// the dispatcher takes it to mean: never left `true` with no options,
    /// which the render closes (`_PickerMenuCore.resolveHandler`).
    var isOpen: Bool = false

    /// The highlighted option while the drop-down is open, and every gesture
    /// that moves it — shared with the pop-up `Menu` and the combo box, so all
    /// three answer the same key with the same movement. See
    /// ``MenuHighlight/pickerDropDown()`` for why this one wraps and the others
    /// do not.
    let highlight = MenuHighlight.pickerDropDown()

    /// The highlighted option's index. Never `nil` in a drop-down: the list is
    /// all there is, so something is always current.
    var highlightedIndex: Int {
        get { highlight.ordinal ?? 0 }
        set { highlight.move(to: newValue) }
    }

    /// How many options a Shift-accelerated Up/Down jumps in the open drop-down.
    /// Synced from `environment.shiftStepMultiplier` during render (default 5);
    /// a plain arrow moves one. See ``View/shiftStepMultiplier(_:)``.
    var shiftStepMultiplier: Int = 5

    /// Each option's text as drawn, by option ordinal, synced by the render:
    /// what a typed prefix finds an option by (``TypeSelectBuffer/title(ofDrawn:)``).
    var optionTexts: [String] = []

    /// What has been typed to find an option, while the drop-down is open.
    private var typeSelected = TypeSelectBuffer()

    /// The drop-down's vertical scroll, when the option list is taller than the
    /// menu can show. `extent` = option count, `viewportHeight` = visible rows,
    /// `scrollOffset` = first visible option. Drives the menu's scrollbar (the
    /// shared ``ScrollbarRenderer`` machinery) and its wheel.
    let menuScroll = ScrollAxis()

    init(
        focusID: String,
        selection: Binding<AnyHashable>,
        itemValues: [AnyHashable],
        canBeFocused: Bool
    ) {
        self.focusID = focusID
        self.selection = selection
        self.itemValues = itemValues
        self.canBeFocused = canBeFocused
        highlight.adopt(count: itemValues.count)
        highlight.move(to: itemValues.firstIndex(of: selection.wrappedValue) ?? 0)
    }

    func onFocusLost() {
        // Closing on focus loss keeps the drop-down from lingering over
        // unrelated content once the user tabs away.
        isOpen = false
        if let index = itemValues.firstIndex(of: selection.wrappedValue) {
            highlight.move(to: index)
        }
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard !itemValues.isEmpty else { return false }
        highlight.adopt(count: itemValues.count)

        guard isOpen else {
            // Closed: only Enter/Space (or a click) open the drop-down —
            // matching SwiftUI. Tab and the arrow keys must fall through to
            // focus navigation.
            guard event.key == .enter || event.key == .space else { return false }
            highlight.move(to: itemValues.firstIndex(of: selection.wrappedValue) ?? 0)
            isOpen = true
            return true
        }

        // The arrows and the jump keys, through the walk every menu in TUIkit
        // shares — Home/End/Page and Shift-accelerated Up/Down included, with a
        // page being a page of the SCROLLING drop-down rather than of the whole
        // option list.
        if highlight.handle(
            event, multiplier: shiftStepMultiplier,
            pageSize: max(1, menuScroll.viewportHeight))
        {
            return true
        }

        switch event.key {
        case .enter, .space:
            selection.wrappedValue = itemValues[highlightedIndex]
            isOpen = false
            return true
        case .escape:
            isOpen = false
            return true
        case .tab:
            // Close, but let the focus system move on to the next view.
            isOpen = false
            return false
        default:
            // A typed character moves the highlight to the option it starts
            // (type select), as an open macOS pop-up button's menu does; no
            // bare-key binding hears it (`TypeSelectingFocusHandler`).
            if typeSelected.take(event),
                let match = TypeSelectBuffer.match(
                    typeSelected.prefix, count: itemValues.count, current: highlight.ordinal,
                    text: { optionTexts.indices.contains($0) ? optionTexts[$0] : nil })
            {
                highlight.move(to: match)
            }
            // While open the picker is modal: swallow everything else.
            return true
        }
    }
}

extension _PickerMenuHandler: TypeSelectingFocusHandler {
    /// Only while open: a closed picker takes no characters, so a bare-key
    /// binding still has them then.
    var takesTypedCharacters: Bool { isOpen }
}
