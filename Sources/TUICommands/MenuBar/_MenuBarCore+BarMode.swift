//  🖥️ TUI — A Terminal UI framework for Swift
//  _MenuBarCore+BarMode.swift
//
//  The bar mode F10 enters: the keyboard walks the menu bar's titles with
//  every menu closed, and a title's letter opens its menu.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension _MenuBarCore {
    /// What a key does in the bar mode.
    enum BarModeAction: Equatable {
        /// Highlight this title instead.
        case highlight(Int)
        /// Open this title's menu, its first item highlighted.
        case open(Int)
        /// Leave the bar mode, every menu closed.
        case leave
    }

    /// What `event` does in the bar mode, with title `highlighted` lit among
    /// titles whose letters are `mnemonics`:
    ///
    /// - Left and Right move along the titles, wrapping round the ends.
    /// - Down, Up, Return and Space open the highlighted title's menu.
    /// - A title's letter opens its menu, with or without Option.
    /// - F10 and Escape leave, and so does any other key, which is spent on
    ///   leaving rather than reaching the page: a letter no title has is no
    ///   more meant for a text field than for the bar.
    ///
    /// This is how the text interfaces before the Mac's reached their menus —
    /// CUA's F10, Turbo Vision's, Midnight Commander's F9 — and the one route
    /// to the bar that reaches a terminal app on every host: macOS keeps its
    /// own menu-bar keys (Control-F2) for the terminal emulator's menu bar
    /// (owner, 2026-10-26, O13-KEYS).
    static func barModeAction(
        for event: KeyEvent, highlighted: Int, mnemonics: [Character?]
    ) -> BarModeAction {
        let count = mnemonics.count
        guard count > 0, !isMenuBarKey(event) else { return .leave }
        switch event.key {
        case .left: return .highlight((highlighted - 1 + count) % count)
        case .right: return .highlight((highlighted + 1) % count)
        case .down, .up, .enter, .space: return .open(highlighted)
        case .character(" ") where !event.ctrl: return .open(highlighted)
        case .character(let character) where !event.ctrl:
            let letter = Character(character.lowercased())
            return mnemonics.firstIndex(of: letter).map { .open($0) } ?? .leave
        default: return .leave
        }
    }

    /// The bar mode: the keyboard walks the titles with every menu closed,
    /// the highlighted title drawn as an open one is and every title's letter
    /// underlined (``titleRow(_:open:walking:context:)``), and holds the
    /// keyboard as an open menu does, in its section (`claimKeyboardAsMenu`):
    /// the keys go to the bar and nowhere else (``barModeAction(for:highlighted:mnemonics:)``).
    ///
    /// The pointer behind it is an open menu's: a press away from the titles
    /// leaves the mode and is spent on that, as a press outside an open menu
    /// is spent on closing it; a press on a title opens its menu, as it does
    /// with every menu closed; and the pointer passing over a title moves the
    /// highlight there.
    func walkTitles(
        _ titles: TitleRow, over buffer: inout FrameBuffer, state: MenuBarState, titleIDs: [HitTestRegion.HandlerID],
        sectionID: String, context: RenderContext
    ) {
        let leave: () -> Void = { [weak state] in state?.close() }
        claimKeyboardAsMenu(sectionID: sectionID, dismiss: leave, context: context)
        // The backdrop rides a copy of the bar's row, presented over the page as
        // an open menu is: the bar's own buffer is one row, and what it carries
        // is cut to that row when it is composited.
        var cover = FrameBuffer(lines: buffer.lines)
        DropdownMenu.attachDismissBackdrop(
            to: &cover, context: context, passThrough: barModeTracking(titleIDs, state: state, context: context),
            onDismiss: leave)
        buffer.overlays.append(
            OverlayLayer(offsetX: 0, offsetY: 0, content: cover, level: .popover, anchorHeight: 0, holdsInput: true)
                .presenting(context.identity))
        let mnemonics = titles.mnemonics
        context.environment.keyEventDispatcher?.addHandler(sectionID: sectionID) { [weak state] event in
            guard let state, let highlighted = state.highlightedTitle, event.phase != .release else { return false }
            switch Self.barModeAction(for: event, highlighted: highlighted, mnemonics: mnemonics) {
            case .highlight(let index): state.highlight(index)
            case .open(let index): state.open(index, withSelection: true)
            case .leave: state.close()
            }
            return true
        }
    }

    /// The titles under the bar mode's backdrop, found by their handlers,
    /// `ids`, at the pointer's cell: a press on one opens its menu as a press
    /// on a closed title does (``attachTitleRegions(to:_:state:context:)``),
    /// and the pointer moved onto one highlights it. Anywhere else the
    /// backdrop has the event.
    private func barModeTracking(
        _ ids: [HitTestRegion.HandlerID], state: MenuBarState, context: RenderContext
    ) -> MenuBackdropPassThrough? {
        guard !ids.isEmpty, let dispatcher = context.environment.mouseEventDispatcher else { return nil }
        return MenuBackdropPassThrough { [weak state, weak dispatcher] event in
            guard let state, let dispatcher, let highlighted = state.highlightedTitle else { return false }
            let under = dispatcher.handlerIDs(at: event.x, y: event.y)
            guard let index = ids.firstIndex(where: under.contains) else { return false }
            switch event.phase {
            case .moved, .entered:
                guard index != highlighted else { return false }
                state.highlight(index)
                return true
            case .pressed where event.button == .left:
                state.open(index, withSelection: false)
                dispatcher.handOffGesture()
                dispatcher.pressOpenedPopup(state.openedPopup)
                return true
            default:
                return false
            }
        }
    }
}
