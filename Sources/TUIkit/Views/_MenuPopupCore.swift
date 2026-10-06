//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _MenuPopupCore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The open/closed state of one pop-up ``Menu`` — a manual StateStorage box
/// (not `@State`) marked active each frame, the same pattern the context menu
/// and the Picker drop-down use.
@MainActor
final class MenuPopupState {
    /// Whether the menu is currently shown.
    var isOpen = false
    /// The open menu's highlight and its rows — see ``MenuPopupController``.
    let controller = MenuPopupController()

    /// Closes the menu — chosen from, dismissed, or let go of — dropping its
    /// highlight. Idempotent.
    func close() {
        isOpen = false
        controller.closed()
    }

    /// The menu, as the press that opens it hands it to the dispatcher for the
    /// rest of its gesture (``MouseEventDispatcher/pressOpenedPopup(_:)``).
    var openedPopup: MouseEventDispatcher.OpenedPopup {
        MouseEventDispatcher.OpenedPopup(isOpen: { self.isOpen }, close: { self.close() })
    }
}

/// The body of ``DefaultMenuStyle``: a collapsed label that opens the items as
/// a floating menu.
///
/// The label is an ordinary ``Button`` — so it takes focus, activates on Enter
/// or a click, and picks up whatever ``ButtonStyle`` is in force — and the open
/// menu is the same presentation `.contextMenu` uses, anchored directly beneath
/// it. Clicking the label while the menu is open closes it: the presentation's
/// dismiss backdrop covers the whole screen and takes that press first, which is
/// exactly the toggle behaviour a pop-up button has everywhere else.
struct _MenuPopupCore: View, Renderable, Layoutable {
    let label: MenuStyleConfiguration.Label
    let content: MenuStyleConfiguration.Content

    /// What a primary interaction does, or `nil` when every interaction opens
    /// the menu — see `trigger`.
    var primaryAction: (() -> Void)?

    /// StateStorage property indices. A free enum on the type because the
    /// state box is fetched from two different methods.
    private enum StateIndex {
        static let state = 0
    }

    /// Child-identity indices, so the trigger's `@State` and focus slots never
    /// collide with the items'.
    private enum ChildIndex {
        static let trigger = 0
        static let items = 1
    }

    var body: Never {
        fatalError("_MenuPopupCore renders via Renderable")
    }

    /// The menu floats *over* the page, so the layout footprint is the
    /// collapsed label — open or closed.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            trigger(
                state(in: context), focusManager: context.environment.focusManager,
                // Measuring only: nothing can open, so nothing to report.
                onOpen: nil, indicator: context.environment.menuIndicatorVisibility),
            proposal: proposal, context: triggerContext(context))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let state = state(in: context)
        let sectionID = "menu-\(context.identity.path)"
        // Keep the box alive across the run loop's per-frame StateStorage GC.
        if !context.isMeasuring { context.stateStorage?.markActive(context.identity) }

        var buffer = TUIkit.renderToBuffer(
            trigger(
                state, focusManager: context.environment.focusManager,
                onOpen: context.environment.menuOpenAction,
                indicator: context.environment.menuIndicatorVisibility),
            context: triggerContext(context))
        guard state.isOpen, !context.isMeasuring else {
            // Tear down a section left over from a just-dismissed menu so the
            // page's focus is restored rather than stranded.
            if !context.isMeasuring {
                context.environment.focusManager?.deactivateSection(id: sectionID)
            }
            return buffer
        }
        // Anchored on the row below the label, like every other drop-down;
        // `presentMenuPopover` nudges it back on-screen at the edges.
        presentMenuPopover(
            items: content, over: &buffer, controller: state.controller, sectionID: sectionID,
            itemsIndex: ChildIndex.items,
            anchor: MenuAnchor(x: 0, y: buffer.height, controlHeight: buffer.height),
            dismiss: { state.close() }, context: context)
        return buffer
    }

    /// The collapsed control: the caller's label plus the closed/open caret
    /// every TUIkit drop-down uses — or, for a menu with a primary action, the
    /// two split (see `splitTrigger`).
    @ViewBuilder
    private func trigger(
        _ state: MenuPopupState, focusManager: FocusManager?, onOpen: MenuOpenAction?,
        indicator: Visibility
    ) -> some View {
        if let primaryAction {
            splitTrigger(
                state, focusManager: focusManager, onOpen: onOpen, indicator: indicator,
                primaryAction: primaryAction)
        } else {
            menuTrigger(state, focusManager: focusManager, onOpen: onOpen, indicator: indicator)
        }
    }

    /// Opens or closes the menu, as the control's own activation.
    ///
    /// A `Button` erases how it was pressed (a click and a Return both just run
    /// the action), so the focus manager is asked which device drove the event —
    /// that is what decides whether the menu opens with a row highlighted.
    private func toggleOpen(
        _ state: MenuPopupState, focusManager: FocusManager?, onOpen: MenuOpenAction?
    ) {
        state.isOpen.toggle()
        if state.isOpen {
            state.controller.opened(withSelection: focusManager?.lastInputSource != .pointer)
            onOpen?()
        }
    }

    /// A menu with a primary action: the label is a button that performs it —
    /// Return, Space or a click — and the menu opens from the caret beside it,
    /// by a click, or from the label by the Down arrow. One focus stop: the
    /// caret takes clicks and no focus, so Tab does not stop on it twice.
    ///
    /// SwiftUI's contract is one line, "the action to perform on primary
    /// interaction with the menu"; the chevron split is how macOS draws it, and
    /// the arrow key is the keyboard's way to the rest.
    private func splitTrigger(
        _ state: MenuPopupState, focusManager: FocusManager?, onOpen: MenuOpenAction?,
        indicator: Visibility, primaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: primaryAction) { label }
                .onKeyPress(.downArrow) {
                    if !state.isOpen {
                        state.isOpen = true
                        state.controller.opened(withSelection: true)
                        onOpen?()
                    }
                    return .handled
                }
            // `.menuIndicator(.hidden)` takes the caret away; the Down arrow
            // still opens the menu.
            if indicator != .hidden {
                Button {
                    toggleOpen(state, focusManager: focusManager, onOpen: onOpen)
                } label: {
                    Text(state.isOpen ? DropdownMenu.openCaret : DropdownMenu.closedCaret)
                }
                .menuTrigger(state.openedPopup)
                .focusable(false)
            }
        }
    }

    /// A menu every interaction opens: the label and caret, one button.
    private func menuTrigger(
        _ state: MenuPopupState, focusManager: FocusManager?, onOpen: MenuOpenAction?,
        indicator: Visibility
    ) -> some View {
        Button {
            toggleOpen(state, focusManager: focusManager, onOpen: onOpen)
        } label: {
            HStack(spacing: 1) {
                label
                // `.menuIndicator(.hidden)` takes the caret away; the label
                // still opens the menu.
                if indicator != .hidden {
                    Text(state.isOpen ? DropdownMenu.openCaret : DropdownMenu.closedCaret)
                }
            }
        }
        // Opens on the mouse PRESS, and hands the rest of that gesture to the
        // menu — click-and-hold, drag down the rows, release on one to choose
        // it, exactly as a Mac pull-down button behaves. A plain click still
        // works: the menu simply stays up until the next click.
        .menuTrigger(state.openedPopup)
    }

    private func triggerContext(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(
            erasedType: MenuStyleConfiguration.Label.self, index: ChildIndex.trigger)
    }

    /// The persisted open/closed state, or a throwaway one outside a running
    /// app (no StateStorage — the menu then simply never opens).
    private func state(in context: RenderContext) -> MenuPopupState {
        guard let stateStorage = context.stateStorage else { return MenuPopupState() }
        let box: StateBox<MenuPopupState> = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.state),
            default: MenuPopupState())
        return box.value
    }
}
