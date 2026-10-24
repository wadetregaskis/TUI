//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabBarMinimizeBehavior.swift
//
//  `tabBarMinimizeBehavior(_:)` and `TabBarMinimizeBehavior`: whether a tab
//  view's bar shrinks when it is short of room. In a terminal, a compact
//  size class an app writes is that shortage (owner, TABBARMIN, option b).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - TabBarMinimizeBehavior

/// The behavior for minimizing a tab view's bar — mirrors SwiftUI's type of
/// the same name.
///
/// macOS has one behavior, ``automatic``, which minimizes the bar when the
/// window is short of room. SwiftUI's `.onScrollDown`, `.onScrollUp` and
/// `.never` are iOS's alone, and are not offered.
///
/// In TUIkit a tab view is short of room where the app writes a horizontally
/// compact size class (`\.horizontalSizeClass`; decisions B3, B96): there a
/// `.bordered` or `.grouped` tab view draws the one-row compact strip
/// instead of its folder tabs over a box, as a `.sidebarAdaptable` one draws
/// the strip instead of its sidebar. TUIkit's size classes are `.regular`
/// unless the app writes one, so by default nothing minimizes.
public struct TabBarMinimizeBehavior: Hashable, Sendable {
    /// Which behavior this is: a name, so a second one would compare apart.
    private let name: String

    /// Minimizes the bar where the tab view is short of room: in TUIkit, in
    /// a horizontally compact size class. The default.
    public static let automatic = Self(name: "automatic")

    /// Whether a bar under this behavior minimizes in a compact size class.
    var minimizesWhenCompact: Bool { self == .automatic }
}

// MARK: - Environment

/// Environment key for the tab bar minimize behavior.
private struct TabBarMinimizeBehaviorKey: EnvironmentKey {
    static let defaultValue = TabBarMinimizeBehavior.automatic
}

extension EnvironmentValues {
    /// How the tab views here minimize their bar, set with
    /// ``View/tabBarMinimizeBehavior(_:)``. Internal, as SwiftUI publishes no
    /// such value.
    var tabBarMinimizeBehavior: TabBarMinimizeBehavior {
        get { self[TabBarMinimizeBehaviorKey.self] }
        set { self[TabBarMinimizeBehaviorKey.self] = newValue }
    }
}

extension View {
    /// Sets the behavior for tab bar minimization — mirrors SwiftUI's
    /// `tabBarMinimizeBehavior(_:)`.
    ///
    /// Under ``TabBarMinimizeBehavior/automatic``, the default and macOS's one
    /// behavior, a `.bordered` or `.grouped` tab view in a horizontally
    /// compact size class draws the compact strip, as a `.sidebarAdaptable`
    /// one does.
    ///
    /// - Parameter behavior: The behavior for tab bar minimization.
    /// - Returns: A view whose tab views minimize their bar by `behavior`.
    public func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View {
        environment(\.tabBarMinimizeBehavior, behavior)
    }
}
