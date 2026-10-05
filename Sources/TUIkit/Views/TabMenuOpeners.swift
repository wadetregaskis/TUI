//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabMenuOpeners.swift
//
//  Where Shift+F10 finds a tab's context menu: the openers the strip and the
//  sidebar file their tabs' menus in, and the sidebar's key over its list.
//  Split out of `TabContentInteractions.swift`, which had passed the
//  file-length guideline.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

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

    /// Made by the strip's handler, which is not on the main actor.
    nonisolated init() {}

    /// Forgets every opener, before a render files this frame's.
    func beginFrame() {
        openers.removeAll(keepingCapacity: true)
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
/// command is heard.
///
/// It keeps the sidebar's ``_TabMenuOpeners`` and hands them to the rows'
/// hosts through the environment, starting them afresh on every render. A
/// render-time keeper rather than the list's `@State`, because the rows are
/// built before anything renders and a `@State` initial value is built on
/// every evaluation of the body that makes the list.
///
/// A sidebar none of whose tabs carries a context menu has nothing for the key
/// to open, and pays for none of it: no box, no environment write, no
/// handler. The content renders at the same identity either way.
struct _TabSidebarMenuKeys<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let selection: Binding<AnyHashable>
    /// Whether any of the sidebar's tabs carries a context menu.
    let hasMenus: Bool

    private typealias StateIndex = TabSidebarMenuKeysStateIndex

    var body: Never { fatalError("_TabSidebarMenuKeys renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context.withChildIdentity(type: Content.self, index: 0))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var contentContext = context.withChildIdentity(type: Content.self, index: 0)
        guard hasMenus, !context.isMeasuring, let storage = context.stateStorage else {
            return TUIkit.renderToBuffer(content, context: contentContext)
        }
        // A manual box, which nothing else hydrates: marked, or the end of
        // the pass would hand the next frame a new, empty one.
        storage.markActive(context.identity)
        let openers = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.openers),
            default: _TabMenuOpeners()
        ).value
        openers.beginFrame()
        contentContext.environment.tabMenuOpeners = openers
        let selection = self.selection
        let keyed = FocusPathModifier(content: content, stage: .command) { _ in
            { event in
                guard event.key == .f10, event.shift else { return false }
                return openers.open(selection.wrappedValue)
            }
        }
        return TUIkit.renderToBuffer(keyed, context: contentContext)
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
