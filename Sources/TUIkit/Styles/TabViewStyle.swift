//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewStyle.swift
//
//  The styles a TabView draws its tabs in: a protocol with a type per style,
//  as SwiftUI's is.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - TabViewStyle

/// A specification for the appearance and interaction of a ``TabView``.
///
/// Set it with ``View/tabViewStyle(_:)``:
///
/// ```swift
/// TabView(selection: $tab) { … }
///     .tabViewStyle(.bordered)
/// ```
///
/// ## Built-in styles
///
/// | Style | Description |
/// |-------|-------------|
/// | ``automatic`` | The default: ``compact``. |
/// | ``tabBarOnly`` | A tab bar: ``compact``, as macOS draws it like the default. |
/// | ``grouped`` | A bar grouping the tabs over a box around the content: ``bordered``. |
/// | ``sidebarAdaptable`` | A sidebar listing the tabs, its sections under their headers, beside the content. |
/// | ``compact`` | **TUI-specific.** One border-free row of chips; the active one is filled. |
/// | ``bordered`` | **TUI-specific.** Box-drawn folder tabs joined to a box around the content. |
///
/// Measured on macOS 15.8: `.automatic` and `.tabBarOnly` both put a segmented
/// tab bar in the window's toolbar, and `.grouped` is an `NSTabView` — the
/// tabs in a segmented bar over a bordered box holding the content. A terminal
/// view has no toolbar to put a bar in, so the first two draw TUIkit's strip
/// above the content, and the third its folder tabs over a box.
///
/// Like TUIkit's other style protocols this one has no requirements, and the
/// framework reads a style off its type: a type of the app's own draws as
/// ``automatic``.
///
/// ## Styles and the render cache
///
/// The built-in styles are `Equatable` for the reason ``PickerStyle``'s are:
/// ``View/tabViewStyle(_:)`` puts the style in the environment, and a value the
/// render cache cannot compare turns memoization off beneath it.
///
/// - Note: `Sendable`, where SwiftUI's is main-actor isolated, as TUIkit's
///   other styles are: the environment holds the style, and an environment
///   default has to be one.
public protocol TabViewStyle: Sendable {}

/// The default tab view style: in TUIkit, ``CompactTabViewStyle``.
///
/// `Equatable` for the reason given under ``TabViewStyle``.
public struct DefaultTabViewStyle: TabViewStyle, Equatable {
    /// Creates the default tab view style.
    public init() {}
}

/// A single, border-free row of tabs: the active tab is marked by a filled
/// chip rather than box-drawing chrome. The most space-efficient style.
///
/// TUI-specific. `Equatable` for the reason given under ``TabViewStyle``.
public struct CompactTabViewStyle: TabViewStyle, Equatable {
    /// Creates a compact tab view style.
    public init() {}
}

/// A row of box-drawing-separated folder tabs joined to a box around the
/// content — more decorative, and two lines taller than ``CompactTabViewStyle``.
///
/// TUI-specific. `Equatable` for the reason given under ``TabViewStyle``.
public struct BorderedTabViewStyle: TabViewStyle, Equatable {
    /// Creates a bordered tab view style.
    public init() {}
}

/// A tab view style that displays a tab bar when possible: in TUIkit the
/// compact strip, which macOS draws this style the same as the default.
///
/// `Equatable` for the reason given under ``TabViewStyle``.
public struct TabBarOnlyTabViewStyle: TabViewStyle, Equatable {
    /// Creates a tab-bar-only tab view style.
    public init() {}
}

/// A tab view style that displays a tab bar that groups its tabs together:
/// the tabs over a box around the content, which in TUIkit is the bordered
/// folder strip (macOS draws an `NSTabView`).
///
/// `Equatable` for the reason given under ``TabViewStyle``.
public struct GroupedTabViewStyle: TabViewStyle, Equatable {
    /// Creates a grouped tab view style.
    public init() {}
}

/// A tab view style that adapts to each platform, and on macOS always shows a
/// sidebar: in TUIkit too, a sidebar listing the tabs — each section under its
/// header, each tab with its badge — beside the selected tab's content.
///
/// Measured on macOS 15.8: an `NSSplitView` whose leading pane is an outline
/// list of the tabs, a ``TabSection``'s header above its tabs and a badge at a
/// row's trailing edge. The sidebar here is a `List`: the arrow keys and a click
/// choose a tab, a disabled tab is stepped over, and the keyboard reaches the
/// content after it. ``View/tabViewSidebarHeader(content:)``,
/// ``View/tabViewSidebarFooter(content:)`` and
/// ``View/tabViewSidebarBottomBar(content:)`` add views above and below it.
///
/// `Equatable` for the reason given under ``TabViewStyle``.
public struct SidebarAdaptableTabViewStyle: TabViewStyle, Equatable {
    /// Creates a sidebar-adaptable tab view style.
    public init() {}
}

extension TabViewStyle where Self == SidebarAdaptableTabViewStyle {
    /// A tab view style that displays a sidebar of the tabs beside the content.
    public static var sidebarAdaptable: SidebarAdaptableTabViewStyle { SidebarAdaptableTabViewStyle() }
}

extension TabViewStyle where Self == TabBarOnlyTabViewStyle {
    /// A tab view style that displays a tab bar when possible.
    public static var tabBarOnly: TabBarOnlyTabViewStyle { TabBarOnlyTabViewStyle() }
}

extension TabViewStyle where Self == GroupedTabViewStyle {
    /// A tab view style that displays a tab bar that groups its tabs together.
    public static var grouped: GroupedTabViewStyle { GroupedTabViewStyle() }
}

extension TabViewStyle where Self == DefaultTabViewStyle {
    /// The default tab view style: ``TabViewStyle/compact`` in TUIkit.
    public static var automatic: DefaultTabViewStyle { DefaultTabViewStyle() }
}

extension TabViewStyle where Self == CompactTabViewStyle {
    /// A single, border-free row of tabs. TUI-specific.
    public static var compact: CompactTabViewStyle { CompactTabViewStyle() }
}

extension TabViewStyle where Self == BorderedTabViewStyle {
    /// Folder tabs joined to a box around the content. TUI-specific.
    public static var bordered: BorderedTabViewStyle { BorderedTabViewStyle() }
}

// MARK: - How a style draws

/// How a tab view draws its strip — what the core reads off a style.
enum _TabStripLook: Equatable {
    /// One border-free row of chips.
    case compact
    /// Folder tabs over a box.
    case bordered
    /// No strip: a sidebar beside the content lists the tabs.
    case sidebar
}

extension TabViewStyle {
    /// How this style draws the strip. A style of the app's own draws as the
    /// default does.
    var stripLook: _TabStripLook {
        switch self {
        case is BorderedTabViewStyle, is GroupedTabViewStyle: .bordered
        case is SidebarAdaptableTabViewStyle: .sidebar
        default: .compact
        }
    }
}

// MARK: - Environment

/// Environment key for the tab view style.
private struct TabViewStyleKey: EnvironmentKey {
    static let defaultValue: any TabViewStyle = DefaultTabViewStyle()
}

extension EnvironmentValues {
    /// The style ``TabView``s in this environment draw in. Set with
    /// ``View/tabViewStyle(_:)``.
    public var tabViewStyle: any TabViewStyle {
        get { self[TabViewStyleKey.self] }
        set { self[TabViewStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for tab views within this view.
    ///
    /// - Parameter style: The style to apply.
    public func tabViewStyle<S: TabViewStyle>(_ style: S) -> some View {
        environment(\.tabViewStyle, style)
    }
}
