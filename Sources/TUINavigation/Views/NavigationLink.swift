//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationLink.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - NavigationLink

/// A control that pushes a screen onto the enclosing ``NavigationStack``.
/// Matches SwiftUI's type of the same name.
///
/// There are two ways to say what to show, and they are the two SwiftUI offers.
/// Push a **value**, and let a `.navigationDestination(for:)` somewhere in the
/// stack decide what it looks like:
///
/// ```swift
/// NavigationLink("Bread", value: Recipe.bread)
/// ```
///
/// …or push a **view** directly, when the screen is one specific thing and
/// there is no data to route on:
///
/// ```swift
/// NavigationLink("Settings") { SettingsView() }
/// ```
///
/// A link renders as a `Button`, so it is a Tab stop, it activates with
/// Return/Space, and a click works — everything a `Button` does, including
/// `.buttonStyle(_:)`. A link with a `nil` value is disabled, as in SwiftUI.
///
/// ## In a List
///
/// A list row reaches its link through the list, as SwiftUI's does. Without a
/// selection the row keeps the button, and Return or Space on the row's cursor
/// follows the link without a Tab to it first:
///
/// ```swift
/// List(recipes) { recipe in
///     NavigationLink(recipe.name, value: recipe)
/// }
/// ```
///
/// In a list with a selection, a link's value is its row's value for the
/// selection, unless a `.tag(_:)` outside the link says otherwise, and the
/// element's `id` need not be of that type at all. A row the list can select
/// draws the link as just its label, with no Tab stop of its own, and choosing
/// the row selects it. That is the whole of a sidebar:
///
/// ```swift
/// NavigationSplitView {
///     List(categories, selection: $category) { category in
///         NavigationLink(category.name, value: category)
///     }
/// } content: { … } detail: { … }
/// ```
///
/// In a ``NavigationStack``, choosing the row follows its link as well as
/// selecting it, as SwiftUI's does. A row the list cannot select, whose link's
/// value and element's `id` are both of other types, keeps the button.
///
/// > Note: A view destination needs a path that can hold the link's own token,
///   so it works in `NavigationStack { … }` and with a ``NavigationPath``
///   binding. A *typed* path binding (`NavigationStack(path: $recipes)`) can by
///   definition only carry `Recipe`s — use `NavigationLink(value:)` with one.
nonisolated public struct NavigationLink<Label: View, Destination: View>: View {

    /// What this link pushes.
    enum Target {
        /// A value, routed through `.navigationDestination(for:)`. `nil`
        /// disables the link.
        case value(AnyHashable?)
        /// A view, registered with the stack under this link's identity.
        case view(Destination)
    }

    let target: Target
    let label: Label

    @MainActor public var body: some View {
        _NavigationLinkCore(target: target, label: label)
    }

    /// Static witness: a link to a value can name its list row, so a list reads
    /// it (``TagCarrying``), as it reads a `.tag(_:)`, and builds the row to ask.
    @MainActor public static var _providesContainerValues: Bool { Destination.self == Never.self }
}

@MainActor extension NavigationLink: TagCarrying {
    package var carriedTag: (value: AnyHashable, includeOptional: Bool)? {
        guard case .value(let value?) = target else { return nil }
        return (value, true)
    }
}

// MARK: - Value destinations

extension NavigationLink where Destination == Never {

    /// Creates a link that pushes `value` onto the stack's path.
    ///
    /// - Parameters:
    ///   - value: The value to push. `nil` disables the link.
    ///   - label: The link's visible content.
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) {
        self.target = .value(value.map { AnyHashable($0) })
        self.label = label()
    }

    /// Creates a link with a localized label that pushes `value` onto the path.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the link's title.
    ///   - value: The value to push. `nil` disables the link.
    public init<P: Hashable>(_ titleKey: LocalizedStringKey, value: P?) where Label == Text {
        self.target = .value(value.map { AnyHashable($0) })
        self.label = Text(titleKey)
    }

    /// Creates a link with a text label, shown as written, that pushes `value`.
    ///
    /// - Parameters:
    ///   - title: The link's title.
    ///   - value: The value to push. `nil` disables the link.
    @_disfavoredOverload
    public init<S: StringProtocol, P: Hashable>(_ title: S, value: P?) where Label == Text {
        self.target = .value(value.map { AnyHashable($0) })
        self.label = Text(String(title))
    }
}

// MARK: - View destinations

extension NavigationLink {

    /// Creates a link that pushes `destination` onto the stack.
    ///
    /// - Parameters:
    ///   - destination: A view builder for the screen to show.
    ///   - label: The link's visible content.
    public init(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.target = .view(destination())
        self.label = label()
    }

    /// Creates a link with a localized label that pushes `destination`.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the link's title.
    ///   - destination: A view builder for the screen to show.
    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder destination: () -> Destination
    ) where Label == Text {
        self.target = .view(destination())
        self.label = Text(titleKey)
    }

    /// Creates a link with a text label, shown as written, pushing `destination`.
    ///
    /// - Parameters:
    ///   - title: The link's title.
    ///   - destination: A view builder for the screen to show.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        @ViewBuilder destination: () -> Destination
    ) where Label == Text {
        self.target = .view(destination())
        self.label = Text(String(title))
    }
}

// MARK: - Core

/// Renders the link as a `Button` whose action pushes onto the stack's path.
///
/// A `_*Core` rather than plain composition because the action needs two things
/// only a render context carries: the coordinator to push onto, and — for a
/// view destination — this link's own identity path to register the view under.
/// Both are captured into the closure at render time, never read from the
/// environment when the button fires, which is nil by then.
private struct _NavigationLinkCore<Label: View, Destination: View>: View, Renderable, Layoutable {
    let target: NavigationLink<Label, Destination>.Target
    let label: Label

    var body: Never {
        fatalError("_NavigationLinkCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let follow = follow(context: context, registerViewDestination: !context.isMeasuring)
        if !context.isMeasuring { Self.reportToListRow(follow, context: context) }
        if Self.drawsAsRowContent(context: context, measuring: context.isMeasuring) {
            let content = labelContent(context: context)
            return TUIView.renderToBuffer(content, context: context.withChildIdentity(type: type(of: content)))
        }
        let button = button(follow: follow, context: context)
        return TUIView.renderToBuffer(button, context: context.withChildIdentity(type: type(of: button)))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if Self.drawsAsRowContent(context: context, measuring: true) {
            let content = labelContent(context: context)
            return measureChild(content, proposal: proposal, context: context.withChildIdentity(type: type(of: content)))
        }
        // Registering a view destination is a render-pass side effect; a
        // measure only needs the button's geometry.
        let button = button(
            follow: follow(context: context, registerViewDestination: false), context: context)
        return measureChild(button, proposal: proposal, context: context.withChildIdentity(type: type(of: button)))
    }

    /// Whether this link is drawn as its label, its list row being the control:
    /// in a row its list can select, unless it is disabled, which only a button
    /// draws.
    private static func drawsAsRowContent(context: RenderContext, measuring: Bool) -> Bool {
        context.environment.isEnabled
            && context.environment.listRowEditRestrictions?.drawsLinkAsRowContent(measuring: measuring) == true
    }

    /// What following this link does, `nil` when it can do nothing: a `nil`
    /// value disables it, as in SwiftUI — there is nothing to push, and a
    /// control that looks live but does nothing is worse than one that looks
    /// unavailable — and with no stack around it there is nowhere to push to.
    private func follow(context: RenderContext, registerViewDestination: Bool) -> (@MainActor () -> Void)? {
        guard let coordinator = context.environment.navigationCoordinator else { return nil }
        switch target {
        case .value(let value):
            guard let value else { return nil }
            return { coordinator.push(value) }

        case .view(let destination):
            // The identity path is stable across frames and unique per link, so
            // it is both a good registry key and a good token: pushing it puts
            // "the screen this link owns" on the path without the link having
            // any data of its own.
            let token = NavigationViewToken(id: context.identity.path)
            if registerViewDestination {
                Self.register(destination, token: token, into: coordinator, context: context)
            }
            return { coordinator.push(AnyHashable(token)) }
        }
    }

    /// The button this link is, following it when pressed.
    private func button(follow: (@MainActor () -> Void)?, context: RenderContext) -> some View {
        Button(action: follow ?? {}) {
            labelContent(context: context)
        }
        .disabled(follow == nil)
    }

    /// The link's label, with the disclosure indicator when asked for: a
    /// terminal's chevron after it. The automatic look is macOS's, which draws
    /// none.
    private func labelContent(context: RenderContext) -> some View {
        let showsIndicator = context.environment.navigationLinkIndicatorVisibility == .visible
        return HStack(spacing: 1) {
            label
            if showsIndicator {
                Text(verbatim: "›")
            }
        }
    }

    /// What the effect journal calls a link's report to its list row.
    private static var rowReportKind: EffectJournal.Kind { EffectJournal.Kind("navigationLink.listRow") }

    /// Tells the list row this link is in, if any, what following it does, for
    /// the list to do it when the row is chosen. Replayable, so a row served
    /// from a memo reports it again.
    private static func reportToListRow(_ follow: (@MainActor () -> Void)?, context: RenderContext) {
        guard let follow, context.environment.isEnabled,
            let restrictions = context.environment.listRowEditRestrictions,
            let row = restrictions.currentRowIndex
        else { return }
        restrictions.reportRowLink(row: row, follow: follow)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let replay: @MainActor (RenderContext) -> Void = { replayed in
            let restrictions = replayed.environment.listRowEditRestrictions
            if let restrictions, let row = restrictions.currentRowIndex {
                restrictions.reportRowLink(row: row, follow: follow)
            }
        }
        journal.append(
            EffectJournal.Entry(
                kind: rowReportKind, channelToken: context.environment.keyChannelToken, apply: replay))
    }

    /// What the effect journal calls a link's registration of its view.
    private static var registrationKind: EffectJournal.Kind { EffectJournal.Kind("navigationLink") }

    /// Registers the view this link pushes, and does so again on every hit of
    /// a memo that serves the link.
    ///
    /// The coordinator keeps only the destinations registered in the stack's
    /// latest pass, or on its path (`NavigationCoordinator.endRegistrationPass`),
    /// so a link a memo served without registering would lose its view, and
    /// pushing it would show an empty screen. Declared REPLAYABLE: the memo
    /// makes the registration again from the entry below.
    ///
    /// The entry holds the coordinator, weakly, rather than looking it up
    /// from the context it is replayed against, as other entries look up their
    /// service: a memo above the stack replays where the stack has not yet put
    /// its coordinator in the environment. It is the stack's `@State`, one
    /// object for the stack's life, which is what makes holding it right.
    private static func register(
        _ destination: Destination, token: NavigationViewToken, into coordinator: NavigationCoordinator,
        context: RenderContext
    ) {
        let view = AnyView(destination)
        coordinator.register(viewDestination: view, forToken: token.id)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        // Built only while a memo records, so the live path allocates no
        // second closure.
        let replay: @MainActor (RenderContext) -> Void = { [weak coordinator] _ in
            coordinator?.register(viewDestination: view, forToken: token.id)
        }
        journal.append(
            EffectJournal.Entry(
                kind: registrationKind, channelToken: context.environment.keyChannelToken, apply: replay))
    }
}

// MARK: - The disclosure indicator

private struct NavigationLinkIndicatorVisibilityKey: EnvironmentKey {
    static let defaultValue = Visibility.automatic
}

extension EnvironmentValues {
    /// Whether navigation links show a disclosure indicator. Mirrors SwiftUI's
    /// `\.navigationLinkIndicatorVisibility`; set it with
    /// ``View/navigationLinkIndicatorVisibility(_:)``.
    ///
    /// `.automatic` draws none, as macOS does; `.visible` draws a `›` after
    /// the link's label.
    public internal(set) var navigationLinkIndicatorVisibility: Visibility {
        get { self[NavigationLinkIndicatorVisibilityKey.self] }
        set { self[NavigationLinkIndicatorVisibilityKey.self] = newValue }
    }
}

extension View {
    /// Configures whether navigation links show a disclosure indicator.
    /// Mirrors SwiftUI's `navigationLinkIndicatorVisibility(_:)`.
    ///
    /// Applied to a list or a stack, it reaches every link inside; applied to
    /// one ``NavigationLink``, just that one. `.visible` draws a `›` after the
    /// label; `.automatic` and `.hidden` draw none, the automatic look being
    /// macOS's.
    ///
    /// - Parameter visibility: Whether the indicator shows.
    nonisolated public func navigationLinkIndicatorVisibility(_ visibility: Visibility) -> some View {
        environment(\.navigationLinkIndicatorVisibility, visibility)
    }
}
