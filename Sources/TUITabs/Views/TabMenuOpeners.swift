//  🖥️ TUI — A Terminal UI framework for Swift
//  TabMenuOpeners.swift
//
//  Where Shift+F10 finds a tab's context menu, and Ctrl-R and Copy its drag:
//  the openers the strip and the sidebar file their tabs' menus and drags in,
//  and the sidebar's keys over its list.
//  Split out of `TabContentInteractions.swift`, which had passed the
//  file-length guideline.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - Where Shift+F10 finds a tab's menu

/// The context menus a tab view's tabs carry, by tab value, as the keyboard
/// opens them: the selected tab's, while the strip or the sidebar holds the
/// focus.
///
/// Filed afresh every frame: the strip (``_TabViewCore``'s
/// `attachTabInteractions`) and the sidebar (``_TabSidebarMenuKeys``) start
/// each render of theirs with ``beginFrame()``, and each tab's host files its
/// opener as it draws. A tab whose menu went away — or that left — files
/// nothing, so Shift+F10 on it opens nothing and goes on, as on a tab that
/// never had a menu. Kept from frame to frame instead, its opener opened a
/// menu on a box nothing drew and said it had: the key was taken and nothing
/// appeared.
@MainActor
final class _TabMenuOpeners {
    private var openers: [AnyHashable: () -> Void] = [:]

    /// The drags the tabs carry, by tab value, as the keyboard takes them
    /// (A53-KEYBOARD-DRAG): Ctrl-R carries the selected tab's, and Copy
    /// copies its payload, while the strip or the sidebar holds the focus. A
    /// tab is no focus stop of its own — the strip or the sidebar is — as a
    /// list row is none.
    private var drags: [AnyHashable: RowDrag] = [:]

    /// The focus manager a carry moves, as of the owner's last render. Weak:
    /// the openers outlive a manager a test makes.
    private weak var focusManager: FocusManager?

    /// Made by the strip's handler, which is not on the main actor.
    nonisolated init() {}

    /// Forgets every opener and drag, before a render files this frame's.
    func beginFrame(focusManager: FocusManager?) {
        openers.removeAll(keepingCapacity: true)
        drags.removeAll(keepingCapacity: true)
        self.focusManager = focusManager
    }

    func file(_ drag: RowDrag, for value: AnyHashable) {
        drags[value] = drag
    }

    /// Whether a tab filed a drag this frame.
    var hasDrags: Bool { !drags.isEmpty }

    /// The payload of the tab `value` names, where it is dragged.
    func payload(of value: AnyHashable) -> Any? {
        drags[value]?.payload()
    }

    /// Picks up the tab `value` names as a carry from the stop that holds the
    /// focus — the strip, or the sidebar's list — and says whether it did.
    func pickUp(_ value: AnyHashable) -> Bool {
        guard let drag = drags[value], let focusManager, let origin = focusManager.currentFocusedID else {
            return false
        }
        return drag.pickUp(origin, focusManager)
    }

    func file(_ opener: @escaping () -> Void, for value: AnyHashable) {
        openers[value] = opener
    }

    /// Opens the menu of the tab `value` names, and says whether it had one.
    func open(_ value: AnyHashable) -> Bool {
        guard let opener = openers[value] else { return false }
        opener()
        return true
    }
}

// MARK: - On a sidebar's rows

/// `StateStorage` property indices for ``_TabSidebarMenuKeys``. Lifted out of
/// the generic struct because Swift does not allow static stored properties in
/// generic types. From 0: the content renders at a child identity.
private enum TabSidebarMenuKeysStateIndex {
    static let openers = 0
}

/// The sidebar's Shift+F10, over its list: opens the selected tab's context
/// menu while the list has the focus — once the list has let the key go, as a
/// command is heard. Its Ctrl-R and Copy likewise carry and copy the selected
/// tab's drag (A53-KEYBOARD-DRAG).
///
/// It keeps the sidebar's ``_TabMenuOpeners`` and hands them to the rows'
/// hosts through the environment, starting them afresh on every render. A
/// render-time keeper rather than the list's `@State`, because the rows are
/// built before anything renders and a `@State` initial value is built on
/// every evaluation of the body that makes the list.
///
/// A sidebar none of whose tabs carries a context menu or a drag has nothing
/// for the keys to do, and pays for none of it: no box, no environment write,
/// no handler. The content renders at the same identity either way.
struct _TabSidebarMenuKeys<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let selection: Binding<AnyHashable>
    /// Whether any of the sidebar's tabs carries a context menu or a drag.
    let hasMenusOrDrags: Bool

    private typealias StateIndex = TabSidebarMenuKeysStateIndex

    var body: Never { fatalError("_TabSidebarMenuKeys renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context.withChildIdentity(type: Content.self, index: 0))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var contentContext = context.withChildIdentity(type: Content.self, index: 0)
        guard hasMenusOrDrags, !context.isMeasuring, let storage = context.stateStorage else {
            return TUIView.renderToBuffer(content, context: contentContext)
        }
        // A manual box, which nothing else hydrates: marked, or the end of
        // the pass would hand the next frame a new, empty one.
        storage.markActive(context.identity)
        let openers = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.openers),
            default: _TabMenuOpeners()
        ).value
        openers.beginFrame(focusManager: context.environment.focusManager)
        contentContext.environment.tabMenuOpeners = openers
        let selection = self.selection
        // One handler for the three, so a sidebar pays for one.
        let keyed = FocusPathModifier(content: content, stage: .command) { context in
            let (copy, clipboard) = context.environment.clipboardCommand("c")
            return { event in
                if event.opensContextMenu { return openers.open(selection.wrappedValue) }
                let trigger = KeyboardShortcut.trigger(for: event)
                if trigger == DragAndDropSession.carryChord.trigger { return openers.pickUp(selection.wrappedValue) }
                guard copy != nil, trigger == copy, let value = openers.payload(of: selection.wrappedValue) else {
                    return false
                }
                clipboard.copy([value])
                return true
            }
        }
        return TUIView.renderToBuffer(keyed, context: contentContext)
    }
}

private struct TabMenuOpenersKey: EnvironmentKey {
    static let defaultValue: _TabMenuOpeners? = nil
}

extension EnvironmentValues {
    /// Where a sidebar's rows file their tabs' context menus, for its
    /// Shift+F10 (``_TabSidebarMenuKeys``).
    var tabMenuOpeners: _TabMenuOpeners? {
        get { self[TabMenuOpenersKey.self] }
        set { self[TabMenuOpenersKey.self] = newValue }
    }
}
