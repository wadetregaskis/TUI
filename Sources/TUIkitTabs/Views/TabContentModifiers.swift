//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabContentModifiers.swift
//
//  The modifiers a tab takes: a badge, hiding, disabling, where it may
//  appear, spring loading, and a section's actions.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The modifier

/// Tab content with something said about each of its tabs: its badge, whether
/// it is hidden or disabled, where it may appear. A modifier on a `ForEach` or
/// a `TabSection` says it of every tab inside.
struct _TabTraitContent<Content: TabContent>: TabContent, _TabContentPrimitive {
    typealias TabValue = Content.TabValue

    /// The tabs the modifier is written on.
    let content: Content

    /// What the modifier says of each of them.
    let apply: @MainActor (inout _RawTab) -> Void

    var body: _TabTraitContent<Content> {
        return self  // swiftlint:disable:this implicit_return
    }

    func appendTabs(to tabs: inout _TabList) {
        tabs.modifying(apply) { TUIkitTabs.appendTabs(content, to: &$0) }
    }
}

// MARK: - Badges

extension TabContent {
    /// Generates a badge for the tab from an integer value; zero hides it.
    ///
    /// The strip draws a tab's badge after its title, in the palette's
    /// tertiary ink, as a list draws a row's.
    ///
    /// - Parameter count: An integer value to display in the badge.
    public func badge(_ count: Int) -> some TabContent<TabValue> {
        _TabTraitContent(content: self) { $0.badge = .int(count) }
    }

    /// Generates a badge for the tab from a text view; `nil` hides it.
    ///
    /// - Parameter label: The text to display in the badge.
    public func badge(_ label: Text?) -> some TabContent<TabValue> {
        _TabTraitContent(content: self) { $0.badge = .string(label?.content) }
    }

    /// Generates a badge for the tab from a localized string key.
    ///
    /// - Parameter key: The key for the badge's text — a literal is looked up,
    ///   see ``LocalizedStringKey``.
    public func badge(_ key: LocalizedStringKey) -> some TabContent<TabValue> {
        let label = key.localized
        return _TabTraitContent(content: self) { $0.badge = .string(label) }
    }

    /// Generates a badge for the tab from a string shown as written.
    ///
    /// - Parameter label: The string to display in the badge.
    @_disfavoredOverload
    public func badge<S: StringProtocol>(_ label: S) -> some TabContent<TabValue> {
        let label = String(label)
        return _TabTraitContent(content: self) { $0.badge = .string(label) }
    }
}

// MARK: - Hidden, disabled, placed

extension TabContent {
    /// Hides the tab from the tab bar and from selection.
    ///
    /// A hidden tab is not drawn and cannot be selected; a tab view whose
    /// selection names one shows its first tab, as it does for a value no tab
    /// carries.
    ///
    /// - Parameter hidden: Whether to hide the tab.
    public func hidden(_ hidden: Bool = true) -> some TabContent<TabValue> {
        _TabTraitContent(content: self) { $0.isHidden = $0.isHidden || hidden }
    }

    /// Disables the tab: it stays in the strip, drawn faint, and cannot be
    /// selected — the arrow keys step over it and a click on it does nothing.
    ///
    /// - Parameter disabled: Whether to disable the tab.
    public func disabled(_ disabled: Bool) -> some TabContent<TabValue> {
        _TabTraitContent(content: self) { $0.isDisabled = $0.isDisabled || disabled }
    }

    /// Sets where the tab may appear.
    ///
    /// A ``TabPlacement/sidebarOnly`` tab appears only in a sidebar, so the
    /// strip every TUIkit tab view style draws leaves it out, as SwiftUI's tab
    /// bar does.
    ///
    /// - Parameter placement: Where the tab may appear.
    public func tabPlacement(_ placement: TabPlacement) -> some TabContent<TabValue> {
        _TabTraitContent(content: self) { $0.placement = placement }
    }
}

// MARK: - Spring loading

extension TabContent {
    /// Sets the spring loading behavior for the tab.
    ///
    /// Spring loading refers to a view being activated during a drag and drop
    /// interaction: a drag held still over a tab — its chip in a strip, its
    /// row in a `.sidebarAdaptable` sidebar — for half a second selects it, so
    /// the drag can reach that tab's content without being let go of. A tab
    /// spring-loads unless told `.disabled`, here or by
    /// ``View/springLoadingBehavior(_:)`` on the tab view; a disabled tab never
    /// does.
    ///
    /// Unlike `disabled(_:)`, this modifier overrides the value set by an
    /// ancestor view rather than being unioned with it. For example, the tab
    /// below would allow spring loading:
    ///
    /// ```swift
    /// TabView {
    ///     Tab("Favorites", systemImage: "star") {
    ///         MyFavoritesView()
    ///     }
    ///     .springLoadingBehavior(.enabled)
    ///
    ///     ...
    /// }
    /// .springLoadingBehavior(.disabled)
    /// ```
    ///
    /// - Parameter behavior: Whether spring loading is enabled or not. If
    ///   unspecified, the default behavior is `.automatic`.
    public func springLoadingBehavior(_ behavior: SpringLoadingBehavior) -> some TabContent<TabValue> {
        // The innermost modifier wins: an enclosing one is applied after the
        // tabs inside have been given theirs, so it only fills a gap.
        _TabTraitContent(content: self) { $0.springLoading = $0.springLoading ?? behavior }
    }
}

// MARK: - Section actions

extension TabContent {
    /// Adds custom actions to a tab section.
    ///
    /// A `.sidebarAdaptable` tab view draws them in its sidebar after the
    /// section's header, as a list draws a section's actions
    /// (``View/sectionActions(content:)``): always shown, where macOS shows
    /// them under the pointer, and reached by Tab and a click. A tab strip
    /// lists a section's tabs among the others and shows no actions.
    ///
    /// Applying this modifier to a single ``Tab`` has no effect.
    ///
    /// - Parameter content: The actions to show in the section's header.
    public func sectionActions<Content: View>(@ViewBuilder content: () -> Content) -> some TabContent<TabValue> {
        let actions = AnyView(content())
        // The sections this content declares are the ones its tabs carry by
        // now: an enclosing section is written onto its tabs only after its
        // whole content is built. An inner `.sectionActions` keeps its own.
        return _TabTraitContent(content: self) { tab in
            guard tab.section != nil, tab.section?.actions == nil else { return }
            tab.section?.actions = actions
        }
    }
}

// MARK: - TabPlacement

/// A place that a tab can appear.
///
/// Not all tab view styles support all placements.
public struct TabPlacement: Hashable, Sendable {
    /// Which placement this is.
    private let name: String

    /// The default tab location.
    public static let automatic = Self(name: "automatic")

    /// The pinned tab placement location: always shown, and never moved by a
    /// customization. A terminal tab bar shows every tab it has room for, so a
    /// pinned tab is placed as an automatic one is.
    public static let pinned = Self(name: "pinned")

    /// The sidebar-only placement: the tab appears in a sidebar and not in a
    /// tab bar.
    public static let sidebarOnly = Self(name: "sidebarOnly")
}
