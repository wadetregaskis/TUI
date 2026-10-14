//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewSidebar.swift
//
//  The sidebar a `.sidebarAdaptable` tab view lists its tabs in, the views it
//  takes above and below them, and the environment values that say where a
//  tab view's tabs are.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitLists
import TUIkitView

// MARK: - The sidebar layout

/// A `.sidebarAdaptable` tab view: a sidebar listing the tabs beside the
/// selected tab's content, with a rule between them.
///
/// Composed rather than drawn: the sidebar is a `List` — its sections under
/// their headers, a tab's badge at its row's trailing edge, a disabled tab
/// stepped over — and the content is the tab view's own core, told by the
/// style to draw no strip. The sidebar hugs its widest row.
///
/// In a horizontally compact size class there is no sidebar: the core draws
/// the strip's tabs as a strip over the content, as a sidebar-adaptable tab
/// view shows a tab bar on iPhone (decisions B3). The core keeps its place in
/// either, so the selected tab's content keeps its state when the class
/// changes.
struct _TabSidebarLayout: View {
    /// The tabs the sidebar lists, in order.
    let tabs: [_RawTab]

    /// The tabs a strip shows, in a compact size class: every tab not placed
    /// only in a sidebar.
    let stripTabs: [_RawTab]

    /// The selected tab's value.
    let selection: Binding<AnyHashable>

    @Environment(\.tabViewSidebarAccessories) private var accessories

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let compact = horizontalSizeClass == .compact
        HStack(alignment: .top, spacing: 0) {
            if !compact {
                VStack(alignment: .leading, spacing: 0) {
                    if let header = accessories.header { header }
                    _TabSidebarList(tabs: tabs, selection: selection)
                    if let footer = accessories.footer { footer }
                    if let bottomBar = accessories.bottomBar { bottomBar }
                }
                .fixedSize(horizontal: true, vertical: false)
                Divider()
            }
            _TabViewCore(selection: selection, tabs: compact ? stripTabs : tabs)
        }
    }
}

/// The sidebar's list of tabs: a section per run of tabs, under the header of
/// the ``TabSection`` they were declared in (none for tabs outside one).
private struct _TabSidebarList: View {
    let tabs: [_RawTab]
    let selection: Binding<AnyHashable>

    /// The tab view's spring loading behavior, which a tab without one of its
    /// own follows.
    @Environment(\.springLoadingBehavior) private var springLoading

    /// The tabs, in runs of consecutive tabs of one section — or of none —
    /// each the list's section, with that section's header and actions: each
    /// section's, and each stretch between sections. A run's rows are its
    /// tabs' places in ``tabs``.
    private var runs: [_SidebarSection] {
        var runs: [_SidebarSection] = []
        // The section the last run's tabs were declared in, `nil` for none.
        var runSection: Int?
        for index in tabs.indices {
            let section = tabs[index].section
            if !runs.isEmpty, runSection == section?.ordinal {
                runs[runs.count - 1].rows.append(index)
            } else {
                runs.append(
                    _SidebarSection(
                        id: runs.count, header: section?.header, actions: section?.actions, rows: [index]))
            }
            runSection = section?.ordinal
        }
        return runs
    }

    /// The row the selection names, by its place in ``tabs``.
    private var rowSelection: Binding<Int?> {
        let tabs = self.tabs
        let selection = self.selection
        return Binding(
            get: { tabs.firstIndex { $0.value == selection.wrappedValue } },
            set: { index in
                guard let index, tabs.indices.contains(index), !tabs[index].isDisabled else { return }
                selection.wrappedValue = tabs[index].value
            })
    }

    var body: some View {
        // Shift+F10 opens the selected tab's context menu while the list has
        // the focus.
        _TabSidebarMenuKeys(
            content: list, selection: selection, hasMenus: tabs.contains { $0.interactions.contextMenu != nil })
    }

    /// The sidebar list, which TUIkitLists builds: a `.sidebar` `List` of the
    /// runs, each a section under its header with its actions
    /// (`_SidebarSectionList`, which says why it is built there).
    private var list: some View {
        _SidebarSectionList(sections: runs, selection: rowSelection) { index in
            row(index)
        }
        // A tab's title is chrome, not text to select. Under an enabled scope
        // around the tab view, the list kept a press on one for a selection
        // (`PressRole.rows`): a click selected no tab, and a draggable tab
        // could not be dragged by its title. Here a press is the list's, as
        // a press on a strip's chip is the strip's.
        .textSelection(.disabled)
    }

    /// One tab's row: its label — a label view of the app's own drawn as
    /// itself — and its badge, faint and stepped over when the tab is
    /// disabled. Keyed by the tab's place, which is what the selection binds:
    /// no `.tag(_:)`, so the badge can be the row's outermost modifier, where
    /// the list reads it.
    ///
    /// A drag held still over the row selects its tab, as a pause over a
    /// strip's chip does.
    ///
    /// Its context menu, popovers, drag and drops hang from the row — the
    /// label, as the list draws it (`_TabInteractionsHost`).
    private func row(_ index: Int) -> some View {
        let tab = tabs[index]
        let badge: String? = tab.badgeSuffix.isEmpty ? nil : tab.badge?.displayText
        let selection = self.selection
        return _SpringLoadedRegion(
            content: interactive(label(of: tab), tab), isEnabled: tab.springLoads(inheriting: springLoading),
            activate: { selection.wrappedValue = tab.value }
        )
        .selectionDisabled(tab.isDisabled)
        .badge(badge)
    }

    /// `label` with the tab's interactions, where it has any.
    @ViewBuilder
    private func interactive(_ label: some View, _ tab: _RawTab) -> some View {
        if tab.interactions.isEmpty {
            label
        } else {
            // Its menu's opener goes where `_TabSidebarMenuKeys` put it.
            _TabInteractionsHost(content: label, traits: tab.interactions, value: tab.value, title: tab.title)
        }
    }

    /// A tab's label in the sidebar: the app's own label view, or the title.
    @ViewBuilder
    private func label(of tab: _RawTab) -> some View {
        if let customLabel = tab.customLabel {
            customLabel
        } else {
            Text(verbatim: tab.title)
        }
    }
}

// MARK: - Above and below the sidebar

/// The views a tab view's sidebar shows above and below its tabs.
///
/// Written straight into the environment by the modifiers that set them, as a
/// badge is, rather than through an environment modifier: a view cannot be
/// compared, and an incomparable value would turn every memo below the tab
/// view off. Only the sidebar reads them, and it draws them every frame.
struct _TabViewSidebarAccessories {
    var header: AnyView?
    var footer: AnyView?
    var bottomBar: AnyView?
}

private struct TabViewSidebarAccessoriesKey: EnvironmentKey {
    static let defaultValue = _TabViewSidebarAccessories()
}

extension EnvironmentValues {
    /// The views a `.sidebarAdaptable` tab view's sidebar shows above and below
    /// its tabs.
    var tabViewSidebarAccessories: _TabViewSidebarAccessories {
        get { self[TabViewSidebarAccessoriesKey.self] }
        set { self[TabViewSidebarAccessoriesKey.self] = newValue }
    }
}

/// Sets one of the sidebar's accessory views for `content`.
struct _TabViewSidebarAccessoryModifier<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let apply: (inout _TabViewSidebarAccessories) -> Void

    var body: Never { fatalError("_TabViewSidebarAccessoryModifier renders via Renderable") }

    private func accessorized(_ context: RenderContext) -> RenderContext {
        var context = context
        apply(&context.environment.tabViewSidebarAccessories)
        return context
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: accessorized(context))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: accessorized(context))
    }
}

extension View {
    /// Adds a custom header to the sidebar of a tab view: above the tabs.
    ///
    /// Shown only by a `.sidebarAdaptable` tab view, as in SwiftUI. It stays
    /// put above the tab list, where SwiftUI's scrolls with the tabs.
    ///
    /// - Parameter content: The header.
    public func tabViewSidebarHeader<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let header = AnyView(content())
        return _TabViewSidebarAccessoryModifier(content: self) { $0.header = header }
    }

    /// Adds a custom footer to the sidebar of a tab view: below the tabs.
    ///
    /// Shown only by a `.sidebarAdaptable` tab view, as in SwiftUI. It stays
    /// put below the tab list, where SwiftUI's scrolls with the tabs.
    ///
    /// - Parameter content: The footer.
    public func tabViewSidebarFooter<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let footer = AnyView(content())
        return _TabViewSidebarAccessoryModifier(content: self) { $0.footer = footer }
    }

    /// Adds a custom bottom bar to the sidebar of a tab view, pinned at its
    /// bottom below the footer.
    ///
    /// Shown only by a `.sidebarAdaptable` tab view, as in SwiftUI.
    ///
    /// - Parameter content: The bottom bar.
    public func tabViewSidebarBottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let bottomBar = AnyView(content())
        return _TabViewSidebarAccessoryModifier(content: self) { $0.bottomBar = bottomBar }
    }
}

// MARK: - Where the tabs are

/// A placement for tabs in a tab view.
public struct TabBarPlacement: Hashable, Sendable {
    /// Which placement this is.
    private let name: String

    /// The bar of tabs above a tab view's content: where every TUIkit tab view
    /// style but `.sidebarAdaptable` puts them, as macOS's do (measured on
    /// macOS 15.8, for `.automatic`, `.tabBarOnly` and `.grouped`).
    public static let topBar = Self(name: "topBar")

    /// Bottom bar of a tab view. No TUIkit tab view style puts its tabs there.
    public static let bottomBar = Self(name: "bottomBar")

    /// The sidebar of a tab view: a `.sidebarAdaptable` one's.
    public static let sidebar = Self(name: "sidebar")

    /// Tab view displaying as an ornament (visionOS). No TUIkit tab view style
    /// puts its tabs there.
    public static let ornament = Self(name: "ornament")

    /// Tab view displaying as an indicator that shows the position within the
    /// pages. No TUIkit tab view style puts its tabs there.
    public static let pageIndicator = Self(name: "pageIndicator")
}

/// The tab view's placement of its tabs, for its content.
private struct TabBarPlacementKey: EnvironmentKey {
    static let defaultValue: TabBarPlacement? = nil
}

/// Whether the tab view shows its sections, for its content.
private struct TabBarShowingSectionsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The current placement of the tab bar: ``TabBarPlacement/topBar``
    /// inside a tab view that draws a strip, ``TabBarPlacement/sidebar``
    /// inside a `.sidebarAdaptable` one, and `nil` outside any — what macOS
    /// 15.8 reports, as measured.
    public var tabBarPlacement: TabBarPlacement? { tabBarPlacementValue }

    /// ``tabBarPlacement``, as the tab view writes it.
    var tabBarPlacementValue: TabBarPlacement? {
        get { self[TabBarPlacementKey.self] }
        set { self[TabBarPlacementKey.self] = newValue }
    }

    /// A Boolean value that determines whether a tab view shows the expanded
    /// contents of a tab section: `true` inside a `.sidebarAdaptable` tab view,
    /// whose sidebar lists each section under its header, and `false` in a
    /// strip, which lists a section's tabs among the others (as measured on
    /// macOS 15.8).
    public var isTabBarShowingSections: Bool { tabBarShowingSections }

    /// ``isTabBarShowingSections``, as the tab view writes it.
    var tabBarShowingSections: Bool {
        get { self[TabBarShowingSectionsKey.self] }
        set { self[TabBarShowingSectionsKey.self] = newValue }
    }

    /// The placement of the tab view's bottom accessory: always `nil`, as on
    /// macOS, which has no bottom accessory to place.
    public var tabViewBottomAccessoryPlacement: TabViewBottomAccessoryPlacement? { nil }
}

/// A placement of the bottom accessory in a tab view.
///
/// The accessory is an iOS one (`tabViewBottomAccessory(content:)`, which macOS
/// does not have), so ``EnvironmentValues/tabViewBottomAccessoryPlacement`` is
/// always `nil` here, as it is on macOS.
public enum TabViewBottomAccessoryPlacement: Hashable, Sendable {
    /// The accessory is inline with the collapsed tab bar.
    case inline
    /// The accessory is expanded above the tab bar.
    case expanded
}

// MARK: - Environment without reflection

extension _TabSidebarLayout: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _accessories.resolveEnvironment(environment)
        _horizontalSizeClass.resolveEnvironment(environment)
    }
}

extension _TabSidebarList: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _springLoading.resolveEnvironment(environment)
    }
}
