//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - NavigationSplitViewStyle

/// A type that specifies the appearance and interaction of navigation split
/// views within a view hierarchy.
///
/// To configure the navigation split view style for a view hierarchy, use the
/// ``View/navigationSplitViewStyle(_:)`` modifier.
///
/// ## Built-in Styles
///
/// - ``AutomaticNavigationSplitViewStyle``: Resolves based on context.
/// - ``BalancedNavigationSplitViewStyle``: Columns share space proportionally.
/// - ``ProminentDetailNavigationSplitViewStyle``: Detail gets more space.
///
/// ## Styles and the render cache
///
/// ``TUIkit/View/navigationSplitViewStyle(_:)`` puts the style into the
/// environment, and the render cache keeps memoized subtrees honest by comparing
/// each injected value with the one applied there last frame. A value it cannot
/// compare may have changed under a buffer it is about to serve with nothing
/// able to notice, so every memo below one declines to cache at all — and what
/// sits below this modifier is a whole split view, all of its columns.
///
/// All four built-in styles are therefore `Equatable`. A built-in's body is its
/// columns laid out by its three read-only proportions below, which is all
/// ``NavigationSplitView`` consults under one; a custom style's
/// `makeBody(configuration:)` draws around that. None of the four holds
/// anything, so `==` within a type is vacuously true, and two instances of one
/// type really do size the columns identically — there is no state for them to
/// differ in, and the numbers they answer with depend only on the type they
/// share.
///
/// Equality is per-type, and that is load-bearing rather than incidental here.
/// ``SizeToFitFromLeftNavigationSplitViewStyle`` carries exactly
/// ``AutomaticNavigationSplitViewStyle``'s proportions and differs only in
/// ``sizesToFit``, which selects a different sizing algorithm outright. A
/// comparison written structurally across the protocol — matching the
/// proportions, or a shared `==` on an extension — would call those two equal
/// and let a split laid out one way be served where the other was asked for. The
/// per-type conformance cannot: the comparison downcasts to `Self` first, so two
/// different styles are never equal whatever they hold.
///
/// A custom style need not conform. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's navigation split view styles declare no such conformance,
///   and this is one of the places a terminal renderer has to differ. SwiftUI
///   diffs the view graph the compiler builds for it and never has to ask
///   whether an environment value changed; TUIkit re-runs `body` and compares
///   values, so here the question must be answerable.
public protocol NavigationSplitViewStyle: Sendable {
    /// A view that represents the body of a navigation split view.
    associatedtype Body: View

    /// The properties of a navigation split view instance.
    typealias Configuration = NavigationSplitViewStyleConfiguration

    /// Creates a view that represents the body of a navigation split view.
    ///
    /// SwiftUI's requirement, and the way to write a style that changes what
    /// surrounds a split rather than how its columns are sized: draw a
    /// built-in style's body and decorate it.
    ///
    /// ```swift
    /// struct FramedSplitStyle: NavigationSplitViewStyle {
    ///     func makeBody(configuration: Configuration) -> some View {
    ///         BalancedNavigationSplitViewStyle().makeBody(configuration: configuration)
    ///             .border()
    ///     }
    /// }
    /// ```
    ///
    /// A style that implements only the proportions below gets a body that
    /// lays the columns out by them.
    ///
    /// - Parameter configuration: The split view to draw.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The proportion of width allocated to the sidebar in a two-column layout.
    ///
    /// Value between 0 and 1. For example, 0.33 means sidebar gets 1/3 of width.
    var sidebarProportion: Double { get }

    /// The proportion of width allocated to each column in a three-column layout.
    ///
    /// Returns (sidebar, content, detail) proportions that sum to 1.0.
    var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) { get }

    /// When `true`, columns are sized to fit their content from the left rather
    /// than by proportion: a column whose content is naturally narrow (it hugs
    /// its width) is given just that width, and the width-flexible columns
    /// (Lists, filling VStacks) share what's left — the rightmost absorbing the
    /// remainder. Default `false` (proportional sizing).
    var sizesToFit: Bool { get }
}

extension NavigationSplitViewStyle {
    /// Proportional styles don't size to fit; ``SizeToFitFromLeftNavigationSplitViewStyle``
    /// overrides this.
    public var sizesToFit: Bool { false }

    /// The automatic style's, so a style written SwiftUI's way — only
    /// `makeBody(configuration:)` — compiles and sizes as the default does.
    public var sidebarProportion: Double { AutomaticNavigationSplitViewStyle().sidebarProportion }

    /// The automatic style's — see ``sidebarProportion``.
    public var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) {
        AutomaticNavigationSplitViewStyle().threeColumnProportions
    }

    /// The columns, laid out by this style's proportions.
    @MainActor
    public func makeBody(configuration: Configuration) -> some View {
        configuration.columns(styledBy: self)
    }
}

// MARK: - Configuration

/// The properties of a navigation split view instance. Mirrors SwiftUI's
/// `NavigationSplitViewStyleConfiguration`, which has no public members
/// either: a style draws it through a built-in style's
/// `makeBody(configuration:)`.
public struct NavigationSplitViewStyleConfiguration {
    /// The split's columns, which read the style they are laid out by from the
    /// environment.
    package let columns: AnyView

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and `NavigationSplitView` (TUIkitNavigation) makes these.
    package init(columns: AnyView) {
        self.columns = columns
    }

    /// The columns, laid out by `style`.
    @MainActor
    package func columns(styledBy style: some NavigationSplitViewStyle) -> some View {
        columns.environment(\.navigationSplitViewStyle, style)
    }
}

/// The styles TUIkit ships, whose bodies are their columns laid out by their
/// own proportions: a split under one draws its columns directly, with no
/// body to erase.
package protocol BuiltInNavigationSplitViewStyle {}

// MARK: - AutomaticNavigationSplitViewStyle

/// A navigation split style that resolves its appearance automatically based
/// on the current context.
///
/// In TUIkit this resolves to a sensible, detail-favoured default: the leading
/// column(s) take a modest share and the detail column gets the larger
/// remainder — wider than ``BalancedNavigationSplitViewStyle`` (which keeps the
/// columns comparable) but not as detail-dominant as
/// ``ProminentDetailNavigationSplitViewStyle``.
///
/// Use the ``NavigationSplitViewStyle/automatic`` static property to access
/// this style.
///
/// `Equatable` for the reason given under ``NavigationSplitViewStyle``: a memo
/// below a value the render cache cannot compare declines to cache.
public struct AutomaticNavigationSplitViewStyle: NavigationSplitViewStyle, Equatable {
    /// Creates an automatic navigation split view style.
    public init() {}

    public var sidebarProportion: Double { 0.33 }

    public var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) {
        (0.25, 0.25, 0.50)
    }
}

// MARK: - Built-in Style Bodies

// Each built-in's body is the columns laid out by its proportions — the same
// view the protocol's default draws, declared on the type as SwiftUI's are, so
// a custom style can draw one and decorate it.

extension AutomaticNavigationSplitViewStyle: BuiltInNavigationSplitViewStyle {
    /// The columns, laid out by this style's proportions.
    @MainActor
    public func makeBody(configuration: Configuration) -> some View {
        configuration.columns(styledBy: self)
    }
}

// MARK: - Environment Key

/// Environment key for the navigation split view style.
private struct NavigationSplitViewStyleKey: EnvironmentKey {
    static let defaultValue: any NavigationSplitViewStyle = AutomaticNavigationSplitViewStyle()
}

extension EnvironmentValues {
    /// The navigation split view style for this environment.
    ///
    /// The built-in styles are `Equatable` so that a memo below one can still
    /// store — see ``NavigationSplitViewStyle`` for why the render cache has to
    /// ask.
    public var navigationSplitViewStyle: any NavigationSplitViewStyle {
        get { self[NavigationSplitViewStyleKey.self] }
        set { self[NavigationSplitViewStyleKey.self] = newValue }
    }
}
