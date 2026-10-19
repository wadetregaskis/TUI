//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarPullDown.swift
//
//  A pull-down in a toolbar: a button that opens a menu hung beneath it — the
//  title's menu, and a labelled group collapsed to its label.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Pull-Down

/// StateStorage property indices of ``_ToolbarPullDown``: outside the type,
/// which is generic and so cannot hold a static stored property. The label and
/// the items render at child identities of their own, so the pull-down's slots
/// never meet theirs.
private enum StateIndex {
    static let state = 0
}

/// Child-identity indices of ``_ToolbarPullDown``, so the trigger's `@State`
/// and focus slots never collide with the items'.
private enum ChildIndex {
    static let trigger = 0
    static let items = 1
}

/// A button showing `label` and the drop-down caret that, pressed, opens
/// `items` as a menu hung beneath it.
///
/// The toolbar's own pull-down, because a toolbar's module cannot see
/// TUIkitMenus' `Menu` (a leaf no other module depends on; see the module
/// split plan, revision 4): it is that menu's default style, built on the same
/// shared pieces — the menu presentation `.contextMenu` and `Menu` share
/// (`presentMenuPopover`), its state box (``ContextMenuState``), and the
/// press-opens gesture (`Button.menuTrigger(_:)`) — so it opens, moves and
/// closes exactly as a `Menu` does: Return, Space or a click opens it, the
/// arrows walk its rows, Escape or a click outside closes it, and a press held
/// and dragged down chooses on release.
struct _ToolbarPullDown<Label: View, Items: View>: View, Renderable, Layoutable {
    /// What the button shows, before the caret.
    let label: Label

    /// The menu's items: `Button`s, `Toggle`s and `Divider`s.
    let items: Items

    /// Whether the button is drawn plain — the label and caret alone, as a
    /// title reads — rather than in the button style in force, as a `Menu`'s
    /// is.
    var isPlain = false

    var body: Never { fatalError("_ToolbarPullDown renders via Renderable") }

    /// The menu floats over the page: the footprint is the button, open or
    /// closed.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            trigger(state(in: context), focusManager: nil, onOpen: nil), proposal: proposal,
            context: triggerContext(context))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let state = state(in: context)
        let sectionID = "toolbar-menu-\(context.identity.path)"
        // Keep the box alive across the run loop's per-frame StateStorage GC.
        if !context.isMeasuring { context.stateStorage?.markActive(context.identity) }
        var buffer = TUIkitView.renderToBuffer(
            trigger(
                state, focusManager: context.environment.focusManager, onOpen: context.environment.menuOpenAction),
            context: triggerContext(context))
        guard state.isOpen, !context.isMeasuring else {
            // A menu just dismissed takes its section down, so the focus goes
            // back to the page rather than being stranded.
            if !context.isMeasuring { context.environment.focusManager?.deactivateSection(id: sectionID) }
            return buffer
        }
        presentMenuPopover(
            items: items, over: &buffer, controller: state.controller, sectionID: sectionID,
            itemsIndex: ChildIndex.items,
            anchor: MenuAnchor(x: 0, y: buffer.height, controlHeight: buffer.height),
            dismiss: { state.close() }, context: context)
        return buffer
    }

    /// The button: the label and the caret every TUIkit drop-down draws.
    @ViewBuilder
    private func trigger(
        _ state: ContextMenuState, focusManager: FocusManager?, onOpen: MenuOpenAction?
    ) -> some View {
        if isPlain {
            button(state, focusManager: focusManager, onOpen: onOpen).buttonStyle(.plain)
        } else {
            button(state, focusManager: focusManager, onOpen: onOpen)
        }
    }

    /// The button, in whatever style it is given.
    private func button(
        _ state: ContextMenuState, focusManager: FocusManager?, onOpen: MenuOpenAction?
    ) -> some View {
        // Weak: the action is registered with the focus manager, so a strong
        // capture would be a cycle.
        Button { [weak focusManager] in
            state.isOpen.toggle()
            if state.isOpen {
                // Opened from the keyboard, the first row is highlighted; by the
                // pointer, nothing is chosen yet.
                state.controller.opened(withSelection: focusManager?.lastInputSource != .pointer)
                onOpen?()
            }
        } label: {
            HStack(spacing: 1) {
                label
                Text(state.isOpen ? DropdownMenu.openCaret : DropdownMenu.closedCaret)
            }
        }
        .menuTrigger(state.openedPopup)
    }

    private func triggerContext(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(erasedType: Label.self, index: ChildIndex.trigger)
    }

    /// The persisted open state, or a throwaway one outside a running app (no
    /// StateStorage: the menu then never opens).
    private func state(in context: RenderContext) -> ContextMenuState {
        guard let stateStorage = context.stateStorage else { return ContextMenuState() }
        let box: StateBox<ContextMenuState> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.state),
            default: ContextMenuState())
        return box.value
    }
}
