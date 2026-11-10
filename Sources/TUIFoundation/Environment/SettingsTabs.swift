//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsTabs.swift
//
//  The tabs an app's `Settings` scene gives the settings panel: one for each
//  of a `TabView`'s tabs, which a view of a higher module offers here.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One tab of the app's own in the settings panel (TUIApp's `SettingsPanel`).
package struct SettingsTab {
    /// The tab's title in the panel's tab strip, or `nil` for the app's name.
    package let title: String?

    /// The tab's content.
    package let content: AnyView

    /// A tab titled `title`, or after the app where that is `nil`, showing
    /// `content`.
    package init(title: String?, content: AnyView) {
        self.title = title
        self.content = content
    }
}

/// A view whose content is tabs of its own — TUITabs' `TabView` — which the
/// settings panel shows as tabs of its own when it is a `Settings` scene's
/// content, rather than as one tab holding a tab view.
///
/// Here, below the module that has tab views, so the `Settings` scene can ask
/// its content without linking them.
package protocol SettingsTabsProviding {
    /// The tabs, in order, each with its content: the ones the view shows.
    @MainActor var settingsTabs: [SettingsTab] { get }
}

// MARK: - Seeing Through to the Tab View

/// The identity step under the settings panel at which the walk for a
/// `Settings` scene's tabs starts: where a view of the app's own the walk
/// reads through binds its `@State`, apart from the identities the panel
/// draws the tabs at, and the same every frame — as a form's content walk
/// has (`_FormContentWalk`).
package enum _SettingsContentWalk {}

/// The tabs `view` gives the settings panel as a `Settings` scene's content,
/// or `nil` for content that is one tab: a tab view's tabs
/// (``SettingsTabsProviding``), whether written in the scene, in the body of
/// a view of the app's own — SwiftUI's documented `Settings {
/// SettingsView() }`, whose body is the `TabView` — or under modifiers, each
/// of which is put back around each tab's content, as a modifier on a group
/// reaches each member (``ContentRewrapping``). SwiftUI's settings window
/// shows such a tab view's tabs as its own, however deep it is written.
///
/// Decided from the types first (``hasSettingsTabs(_:depth:)``), so a body
/// is evaluated only where it leads to a tab view. Then it is evaluated as a
/// render evaluates it — `@State` bound at `walk`'s identity, `@Environment`
/// resolved, observed — so a tab bound to the view's own `@State` keeps it
/// from frame to frame while the panel is up.
///
/// - Parameters:
///   - view: The scene's content.
///   - walk: Where the walk is: the panel's context, one
///     ``_SettingsContentWalk`` step in, with the scene's statements on it.
@MainActor
package func settingsTabs<V: View>(of view: V, in walk: RenderContext) -> [SettingsTab]? {
    guard hasSettingsTabs(V.self, depth: 0) else { return nil }
    // A view nested in itself through its body is read through at every
    // level, each a descent of this walk, so it stops where the stack runs
    // short, as `compositeMembers(of:context:)` stops.
    guard StackGuard.hasHeadroomUncounted() else {
        StackGuard.noteReadThroughStop()
        return nil
    }
    if let provider = view as? any SettingsTabsProviding { return provider.settingsTabs }
    if let modified = view as? any SettingsTabsModifiedContent { return modified.settingsTabs(in: walk) }
    if let wrapper = view as? any ContentRewrapping { return settingsTabs(inside: wrapper, walk) }
    guard walk.stateStorage != nil else { return nil }
    let body = evaluateCompositeBody(of: view, context: walk)
    return settingsTabs(of: body, in: walk.withChildIdentity(type: V.Body.self))
}

/// ``settingsTabs(of:in:)`` inside a wrapper that can be put back around
/// each tab's content, in the context it lays its content out in.
@MainActor
private func settingsTabs<W: ContentRewrapping>(inside wrapper: W, _ walk: RenderContext) -> [SettingsTab]? {
    settingsTabs(of: wrapper.wrappedContent, in: wrapper.wrappedContentContext(walk) ?? walk)?.map { tab in
        SettingsTab(title: tab.title, content: AnyView(wrapper.rewrapping(tab.content)))
    }
}

/// A modified view — `.padding()`, a border — whose modifier the walk puts
/// back around each tab's content (``settingsTabs(of:in:)``).
@MainActor
private protocol SettingsTabsModifiedContent {
    func settingsTabs(in walk: RenderContext) -> [SettingsTab]?
}

@MainActor extension ModifiedView: SettingsTabsModifiedContent {
    fileprivate func settingsTabs(in walk: RenderContext) -> [SettingsTab]? {
        TUIFoundation.settingsTabs(of: content, in: walk)?.map { tab in
            let modified = ModifiedView<AnyView, Modifier>(content: tab.content, modifier: modifier)
            return SettingsTab(title: tab.title, content: AnyView(modified))
        }
    }
}

/// Whether a view of type `T` leads to a tab view the walk can reach: one
/// itself, one under modifiers it can put back (``ContentRewrapping``, a
/// `ModifiedView`), or one in the body of a view of the app's own, followed
/// down the chain of `body` types. A primitive, a container and an `AnyView`
/// end it. A view nested in itself stops at `depth` 16.
@MainActor
private func hasSettingsTabs<T: View>(_ type: T.Type, depth: Int) -> Bool {
    guard depth < 16 else { return false }
    if type is any SettingsTabsProviding.Type { return true }
    if type is any ContentRewrapping.Type || type is any SettingsTabsModifiedContent.Type,
        let wrapper = type as? any SingleContentWrapper.Type
    {
        return hasSettingsTabs(wrappedBy: wrapper, depth: depth + 1)
    }
    guard T.Body.self != Never.self, !(type is any ChildViewProvider.Type), !(type is any Renderable.Type)
    else { return false }
    return hasSettingsTabs(T.Body.self, depth: depth + 1)
}

/// ``hasSettingsTabs(_:depth:)`` of what wrappers of type `W` wrap, the
/// existential opened to reach it.
@MainActor
private func hasSettingsTabs<W: SingleContentWrapper>(wrappedBy _: W.Type, depth: Int) -> Bool {
    hasSettingsTabs(W.WrappedContent.self, depth: depth)
}
