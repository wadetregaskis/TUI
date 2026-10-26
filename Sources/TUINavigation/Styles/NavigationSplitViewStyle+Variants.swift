//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationSplitViewStyle+Variants.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

/// What a ``NavigationSplitView``'s body is: the columns, drawn through the
/// style in the environment.
struct _NavigationSplitViewStyleHost<Columns: View>: View {
    let columns: Columns

    @Environment(\.navigationSplitViewStyle) private var style

    var body: some View {
        if let customBody {
            customBody
        } else {
            columns
        }
    }

    /// A custom style's body around the columns, or `nil` under a built-in
    /// style, whose body is the columns themselves.
    private var customBody: AnyView? {
        let style: any NavigationSplitViewStyle = style
        guard !(style is any BuiltInNavigationSplitViewStyle) else { return nil }
        return Self.body(of: style, around: AnyView(columns))
    }

    /// `style`'s body around the columns.
    @MainActor
    private static func body<S: NavigationSplitViewStyle>(of style: S, around columns: AnyView) -> AnyView {
        AnyView(style.makeBody(configuration: NavigationSplitViewStyleConfiguration(columns: columns)))
    }
}

// MARK: - BalancedNavigationSplitViewStyle

/// A navigation split style that reduces the size of the detail content to
/// make room when showing the leading column or columns.
///
/// This style distributes space so the sidebar and detail are *comparable* in
/// width (the detail shrinks to make room for the leading columns), rather than
/// favouring the detail. The leading columns therefore take a larger share than
/// under ``AutomaticNavigationSplitViewStyle``.
///
/// Use the ``NavigationSplitViewStyle/balanced`` static property to access
/// this style.
///
/// `Equatable` on the same terms as ``AutomaticNavigationSplitViewStyle``.
public struct BalancedNavigationSplitViewStyle: NavigationSplitViewStyle, Equatable {
    /// Creates a balanced navigation split view style.
    public init() {}

    public var sidebarProportion: Double { 0.42 }

    public var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) {
        (0.30, 0.30, 0.40)
    }
}

// MARK: - ProminentDetailNavigationSplitViewStyle

/// A navigation split style that attempts to maintain the size of the detail
/// content when hiding or showing the leading columns.
///
/// This style gives more space to the detail column, making leading columns
/// narrower.
///
/// Use the ``NavigationSplitViewStyle/prominentDetail`` static property to
/// access this style.
///
/// `Equatable` on the same terms as ``AutomaticNavigationSplitViewStyle``.
public struct ProminentDetailNavigationSplitViewStyle: NavigationSplitViewStyle, Equatable {
    /// Creates a prominent detail navigation split view style.
    public init() {}

    public var sidebarProportion: Double { 0.22 }

    public var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) {
        (0.18, 0.18, 0.64)
    }
}

// MARK: - SizeToFitFromLeftNavigationSplitViewStyle

/// A navigation split style that sizes columns to fit their content, biased to
/// the left, rather than by fixed proportion.
///
/// A column whose content is naturally narrow — it hugs its width, e.g. a
/// sidebar of short labels — is given just that width. The width-flexible
/// columns (Lists, filling VStacks) split the remaining space, with the
/// rightmost column absorbing the remainder. When the terminal is too narrow,
/// columns shrink and their content truncates, honouring each column's minimum.
///
/// Use the ``NavigationSplitViewStyle/sizeToFitFromLeft`` static property to
/// access this style.
///
/// `Equatable` on the same terms as ``AutomaticNavigationSplitViewStyle``, and
/// this is the one that earns the per-type comparison: its proportions are that
/// style's exactly, so only the type tells them apart — see
/// ``NavigationSplitViewStyle``.
public struct SizeToFitFromLeftNavigationSplitViewStyle: NavigationSplitViewStyle, Equatable {
    /// Creates a size-to-fit-from-left navigation split view style.
    public init() {}

    public var sizesToFit: Bool { true }

    // Proportional fallbacks (used only if a caller reads them directly); the
    // real sizing is content-driven when `sizesToFit` is honoured.
    public var sidebarProportion: Double { 0.33 }

    public var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) {
        (0.25, 0.25, 0.50)
    }
}

extension BalancedNavigationSplitViewStyle: BuiltInNavigationSplitViewStyle {
    /// The columns, laid out by this style's proportions.
    @MainActor
    public func makeBody(configuration: Configuration) -> some View {
        configuration.columns(styledBy: self)
    }
}

extension ProminentDetailNavigationSplitViewStyle: BuiltInNavigationSplitViewStyle {
    /// The columns, laid out by this style's proportions.
    @MainActor
    public func makeBody(configuration: Configuration) -> some View {
        configuration.columns(styledBy: self)
    }
}

extension SizeToFitFromLeftNavigationSplitViewStyle: BuiltInNavigationSplitViewStyle {
    /// The columns, each sized to fit its content from the left.
    @MainActor
    public func makeBody(configuration: Configuration) -> some View {
        configuration.columns(styledBy: self)
    }
}

// MARK: - Style Static Properties

extension NavigationSplitViewStyle where Self == SizeToFitFromLeftNavigationSplitViewStyle {
    /// A navigation split style that sizes columns to fit their content from the
    /// left: naturally-narrow columns hug their width, flexible columns share
    /// the rest.
    public static var sizeToFitFromLeft: Self {
        Self()
    }
}

extension NavigationSplitViewStyle where Self == AutomaticNavigationSplitViewStyle {
    /// A navigation split style that resolves its appearance automatically
    /// based on the current context.
    public static var automatic: Self {
        Self()
    }
}

extension NavigationSplitViewStyle where Self == BalancedNavigationSplitViewStyle {
    /// A navigation split style that reduces the size of the detail content
    /// to make room when showing the leading column or columns.
    public static var balanced: Self {
        Self()
    }
}

extension NavigationSplitViewStyle where Self == ProminentDetailNavigationSplitViewStyle {
    /// A navigation split style that attempts to maintain the size of the
    /// detail content when hiding or showing the leading columns.
    public static var prominentDetail: Self {
        Self()
    }
}

// MARK: - View Extension

extension View {
    /// Sets the style for navigation split views within this view.
    ///
    /// Use this modifier to specify how columns in a ``NavigationSplitView``
    /// should be sized and displayed.
    ///
    /// ```swift
    /// NavigationSplitView {
    ///     SidebarView()
    /// } detail: {
    ///     DetailView()
    /// }
    /// .navigationSplitViewStyle(.prominentDetail)
    /// ```
    ///
    /// ## Available Styles
    ///
    /// - ``NavigationSplitViewStyle/automatic``: Resolves based on context.
    /// - ``BalancedNavigationSplitViewStyle/balanced``: Columns share space proportionally.
    /// - ``ProminentDetailNavigationSplitViewStyle/prominentDetail``: Detail gets more space.
    ///
    /// - Parameter style: The navigation split view style to apply.
    /// - Returns: A view with the specified navigation split view style.
    public func navigationSplitViewStyle<S: NavigationSplitViewStyle>(_ style: S) -> some View {
        environment(\.navigationSplitViewStyle, style)
    }
}

// MARK: - Environment without reflection

extension _NavigationSplitViewStyleHost: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _style.resolveEnvironment(environment)
    }
}
