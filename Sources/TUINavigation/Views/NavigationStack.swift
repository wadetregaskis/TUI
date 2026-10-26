//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationStack.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - NavigationStack

/// A view that displays a root view and lets you push additional views over it.
/// Matches SwiftUI's type of the same name.
///
/// ```swift
/// NavigationStack {
///     List(recipes) { recipe in
///         NavigationLink(recipe.name, value: recipe)
///     }
///     .navigationTitle("Recipes")
///     .navigationDestination(for: Recipe.self) { recipe in
///         RecipeView(recipe: recipe)
///             .navigationTitle(recipe.name)
///     }
/// }
/// ```
///
/// The stack shows its root until something is pushed; from then on it shows
/// the top of the path, under a navigation bar carrying the trail of
/// ``navigationTitle(_:)-(LocalizedStringKey)``s that got you there:
///
/// ```
///   Planets  ›  Mars  ›  Deimos  ›  Copernicus Rim
/// ```
///
/// Every crumb but the last is a `Button` — a Tab stop, and clicking or
/// activating one pops straight back to that depth rather than one screen at a
/// time. **Escape** and `@Environment(\.dismiss)` still pop one, from anywhere
/// in the pushed screen.
///
/// The trail gives way as the terminal narrows: first its middle is elided
/// (`Planets  ›  …  ›  Copernicus Rim`), keeping the two ends that orient you;
/// then, when even that will not fit, the bar falls back to a single **‹ Back**
/// button and the truncated title. The bar's height never changes through any of
/// this — see `ChromeStyle.barHeight(contentRows:)`.
///
/// ## Where the path lives
///
/// With no `path` argument the stack keeps the path itself, which is all most
/// apps need. Bind one when you want to read or change it — deep-linking, or
/// returning to the root from several screens down:
///
/// - `NavigationStack(path: $recipes)` — a homogeneous stack. `Data` is any
///   `RangeReplaceableCollection` of `Hashable` values.
/// - `NavigationStack(path: $path)` with a ``NavigationPath`` — a
///   heterogeneous stack, where different screens push different types.
///
/// ## TUI-specific behaviour
///
/// - The bar is exactly two rows (title row + rule) whatever the title is, so
///   the space left for content never depends on the content.
/// - The root keeps rendering while a screen is pushed — off-screen, and
///   isolated from focus and key events the way a modal's backdrop is. That is
///   what keeps the root's `@State` (a scroll position, a selection) alive to
///   come back to, and what keeps its `.navigationDestination(for:)`
///   registrations current.
/// - A screen comes and goes at once, unless it zooms
///   (`.navigationTransition(.zoom(sourceID:in:))` on the screen, with
///   ``View/matchedTransitionSource(id:in:)`` on the view it zooms from): it is
///   then revealed from its source's frame, and folded back into it when it is
///   popped (``ZoomNavigationTransition``).
public struct NavigationStack<Root: View>: View {

    /// Where the path is kept. Every case is normalised to the same pair of
    /// closures at render time, so the core has one path model to work with.
    enum PathStorage {
        /// The stack's own `@State` — `NavigationStack { … }`.
        case owned
        /// A ``NavigationPath`` binding.
        case path(Binding<NavigationPath>)
        /// A typed collection binding, erased to `AnyHashable` and back.
        case typed(read: () -> [AnyHashable], write: ([AnyHashable]) -> Void)
    }

    let root: Root
    let storage: PathStorage

    /// The destination registry and path accessors. `@State` so it is ONE
    /// object across frames: a link rendered now installs a button action that
    /// must still find this stack's path when it fires later.
    @State private var coordinator = NavigationCoordinator()

    /// The path, when the stack owns it (``PathStorage/owned``). Unused
    /// otherwise; it costs one empty array.
    @State private var ownedPath: [AnyHashable] = []

    /// Creates a navigation stack that manages its own path.
    public init(@ViewBuilder root: () -> Root) {
        self.root = root()
        self.storage = .owned
    }

    /// Creates a navigation stack backed by a ``NavigationPath``, for screens
    /// driven by values of more than one type.
    ///
    /// - Parameters:
    ///   - path: The path to read and write.
    ///   - root: The view at the bottom of the stack.
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) {
        self.root = root()
        self.storage = .path(path)
    }

    /// Creates a navigation stack backed by a collection of hashable values.
    ///
    /// - Parameters:
    ///   - path: The collection of values to show screens for.
    ///   - root: The view at the bottom of the stack.
    public init<Data>(path: Binding<Data>, @ViewBuilder root: () -> Root)
    where
        Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection,
        Data.Element: Hashable
    {
        self.root = root()
        self.storage = .typed(
            read: { path.wrappedValue.map { AnyHashable($0) } },
            // A typed path can hold only its own element type; anything else
            // on the way back in is dropped, which is the binding's contract
            // rather than a policy of ours. See ``NavigationLink``.
            write: { erased in
                path.wrappedValue = Data(erased.compactMap { $0.base as? Data.Element })
            })
    }

    public var body: some View {
        let accessors = accessors()
        return _NavigationStackCore(
            root: root,
            coordinator: coordinator,
            read: accessors.read,
            write: accessors.write)
    }

    /// The path accessors for whichever storage this stack was built with.
    private func accessors() -> (read: () -> [AnyHashable], write: ([AnyHashable]) -> Void) {
        switch storage {
        case .owned:
            let binding = $ownedPath
            return ({ binding.wrappedValue }, { binding.wrappedValue = $0 })
        case .path(let path):
            return (
                { path.wrappedValue.elements },
                { path.wrappedValue = NavigationPath(erased: $0) }
            )
        case .typed(let read, let write):
            return (read, write)
        }
    }
}

// MARK: - Core

/// Renders the root, or the top of the path over it.
///
/// A `_*Core` because two things here are procedural and cannot be composed:
/// rendering the root purely for its side effects while showing something else,
/// and reading the screen's `navigationTitle` preference back out after
/// rendering it, to draw a bar whose height was fixed before either happened.
private struct _NavigationStackCore<Root: View>: View, Renderable, Layoutable {
    let root: Root
    let coordinator: NavigationCoordinator
    let read: () -> [AnyHashable]
    let write: ([AnyHashable]) -> Void

    var body: Never {
        fatalError("_NavigationStackCore renders via Renderable")
    }

    // MARK: Measurement

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let elements = read()
        var childContext = context
        childContext.environment.navigationCoordinator = coordinator
        // The screen's `containerRelativeFrame` container: the stack, less the
        // bar a pushed screen sits under. Set, not noted, from a measure.
        childContext = childContext.publishingContainerSize(
            CellSize(
                width: max(0, proposal.width ?? context.availableWidth),
                height: max(0, (proposal.height ?? context.availableHeight) - (elements.isEmpty ? 0 : NavigationBar.height))),
            noting: false)

        guard let top = elements.last else {
            return measureChild(
                root, proposal: proposal,
                context: childContext.withChildIdentity(type: type(of: root)))
        }

        let bar = NavigationBar.height
        let inner = ProposedSize(
            width: proposal.width,
            height: proposal.height.map { max(0, $0 - bar) })
        childContext = childContext.withAvailableSize(
            width: childContext.availableWidth,
            height: max(0, childContext.availableHeight - bar))

        guard let destination = coordinator.destination(for: top) else {
            return ViewSize(
                width: proposal.width ?? 0, height: bar,
                isWidthFlexible: true, isHeightFlexible: false)
        }
        let size = measureChild(
            destination, proposal: inner,
            context: childContext.withChildIdentity(type: NavigationScreen.self))
        return ViewSize(
            width: size.width, height: size.height + bar,
            isWidthFlexible: size.isWidthFlexible, isHeightFlexible: size.isHeightFlexible)
    }

    // MARK: Rendering

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Re-point the coordinator at this frame's binding before anything in
        // the subtree can capture it. Render passes only: a measure pass would
        // install identical closures for no gain, and persistent state is not
        // a measure's to touch.
        if !context.isMeasuring {
            coordinator.read = read
            coordinator.write = write
        }

        let elements = read()
        // Where the stack is, asked only on a frame it may zoom — before
        // anything renders, for the ordinal its marker's id is.
        let ask =
            !context.isMeasuring && coordinator.zoom.needsOrigin(depth: elements.count)
            ? context.makeGeometryAsk(role: .reader) : nil
        var base = context
        base.environment.navigationCoordinator = coordinator
        // The screen's `containerRelativeFrame` container: the stack, less the
        // bar a pushed screen sits under.
        base = base.publishingContainerSize(
            CellSize(
                width: max(0, context.availableWidth),
                height: max(0, context.availableHeight - (elements.isEmpty ? 0 : NavigationBar.height))))

        // Each depth is its own focus section, so walking into a screen and
        // back restores the focus the level you left was holding — the same
        // thing a dismissed modal does. Without it the pop landed on whichever
        // control registered first, so returning from a planet always put the
        // focus back on the first planet rather than on the one you opened.
        //
        // Before anything renders: the level being returned TO registers its
        // focusables during this pass, and it must do so with the deeper
        // section already gone.
        let path = context.identity.path
        if !context.isMeasuring,
            let section = coordinator.enterSection(
                depth: elements.count, context: context,
                // Depth 0 has no section of its own: the root is the page's.
                sectionID: { depth in depth > 0 ? Self.sectionID(base: path, depth: depth) : nil })
        {
            base.environment.activeFocusSectionID = section
        }

        guard let top = elements.last else {
            let buffer = TUIView.renderToBuffer(
                root, context: base.withChildIdentity(type: type(of: root)))
            return zoomed(buffer, depth: 0, declared: nil, ask: ask, context: context)
        }

        // The root still renders — off-screen, and isolated from focus and key
        // events exactly as a modal's backdrop is. Its buffer (and with it
        // every hit-test region) is dropped, so nothing on it can be reached;
        // what survives is its `@State`, which `endRenderPass` would otherwise
        // prune the moment it stopped rendering, and its
        // `.navigationDestination(for:)` registrations, which stay current
        // because the closures are re-captured each frame.
        //
        // `withThrowawayFrameDemand` because the buffer is dropped WHOLE. A
        // root that read the pulse phase, or asked the scheduler for a
        // lattice, went on driving the loop at its own rate from behind the
        // screen covering it — the isolation above covers every channel by
        // which the invisible root could reach the USER, and left it the two
        // by which it reached the CLOCK.
        if !context.isMeasuring {
            let backdrop = base.isolatedForBackground()
            // Collect the root's title while it renders, because this is the
            // only place it is ever published — the bar draws for pushed
            // screens, so nothing else sees depth 0's name, and the crumb trail
            // would start with an anonymous "…" no matter how wide the terminal.
            let preferences = backdrop.environment.preferenceStorage
            // Declared like the screen's collection in `renderScreen`, and on
            // the LIVE tracker rather than the backdrop's throwaway: this one
            // is not a demand for a frame but a refusal to be cached, and it
            // is load-bearing. Served from a memo this whole branch is skipped,
            // the root does not render, and `endRenderPass` prunes the `@State`
            // the render exists to keep.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            preferences?.push()
            _ = backdrop.withThrowawayFrameDemand { hidden in
                TUIView.renderToBuffer(root, context: hidden.withChildIdentity(type: type(of: root)))
            }
            coordinator.recordTitle(preferences?.pop()[NavigationTitleKey.self] ?? "", atDepth: 0)
        }

        let screen = renderScreen(top: top, context: base)
        return zoomed(screen.buffer, depth: elements.count, declared: screen.zoom, ask: ask, context: context)
    }

    /// `buffer` as the zoom running or starting draws it
    /// (``NavigationCoordinator/zoomed(_:depth:declared:origin:context:)``),
    /// with the stack's marker when it asked where it is.
    private func zoomed(
        _ buffer: FrameBuffer, depth: Int, declared: MatchedGeometryKey?, ask: GeometryAsk?, context: RenderContext
    ) -> FrameBuffer {
        guard !context.isMeasuring else { return buffer }
        var drawn = coordinator.zoomed(
            buffer, depth: depth, declared: declared, origin: { ask?.observation(in: .global)?.origin },
            context: context)
        if let ask {
            ask.finishRecording(size: buffer.cellSize)
            if context.geometryCoordinator?.register(ask) == true {
                drawn.hitTestRegions.append(.geometryMarker(ask.id))
            }
        }
        return drawn
    }

    /// A focus section per stack, per depth. Structural identity, never the
    /// pushed value: two stacks on one page must not share a section, and the
    /// same value pushed twice is two different places to come back to.
    static func sectionID(base: String, depth: Int) -> String {
        "navigation-\(base)-\(depth)"
    }

    /// Renders the pushed screen with its navigation bar above it, and says
    /// which zoom it declared (``View/navigationTransition(_:)``).
    private func renderScreen(top: AnyHashable, context: RenderContext) -> (buffer: FrameBuffer, zoom: MatchedGeometryKey?) {
        let width = max(0, context.availableWidth)
        let contentHeight = max(0, context.availableHeight - NavigationBar.height)

        var screenContext = context.withAvailableSize(width: width, height: contentHeight)
        // Escape and `\.dismiss` both mean "go back" from inside a pushed
        // screen, which is what SwiftUI's dismiss does in a stack.
        let coordinator = coordinator
        screenContext.environment.dismiss = DismissAction { coordinator.pop() }

        // Where the stack's Escape handler goes: BEHIND everything the screen is
        // about to register, although whether to register it at all is only
        // known once the screen has rendered (see `NavigationBar.render`). Read now, before
        // the first of the screen's handlers lands.
        let escapeHandlerSlot = context.environment.keyEventDispatcher?.handlerCount ?? 0

        // Collect the screen's own preferences so the bar can read the title it
        // set — and only the title IT set, not one an ancestor published.
        let preferences = screenContext.environment.preferenceStorage
        // Collecting observes this pass's preferences, as `onPreferenceChange`
        // does, and is declared to any value-memoizing ancestor for the same
        // reason: a served buffer runs no collection. Render passes only, like
        // every declaration.
        if !context.isMeasuring {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            // The screen's top-bar items go in this bar, not the window's
            // (`NavigationBarItems`): inside an app, on a drawn walk.
            if context.environment.windowChrome != nil {
                coordinator.barItems.begin()
                screenContext.environment.navigationBarItems = coordinator.barItems
            }
        }
        preferences?.push()
        var content =
            coordinator.destination(for: top).map {
                TUIView.renderToBuffer(
                    $0, context: screenContext.withChildIdentity(type: NavigationScreen.self))
            } ?? FrameBuffer()
        // The screen's transition is this stack's alone: merged up, it was
        // the transition of the screen of a stack this one is in, which
        // folded that screen into this one's source when it was popped.
        var zoom: MatchedGeometryKey?
        let published = preferences?.pop { zoom = $0.removeValue(for: NavigationZoomKey.self) }
        let title = published?[NavigationTitleKey.self] ?? ""
        let subtitle = published?[NavigationSubtitleKey.self] ?? ""
        let hidesBack = published?[NavigationBackButtonHiddenKey.self] ?? false
        // `.toolbar(removing: .title)` in the screen, or on or above the stack.
        let hidesTitle =
            published?[ToolbarTitleRemovedKey.self] == true || context.environment.toolbarTitleRemoved

        content = NavigationBar.padded(content, toWidth: width, height: contentHeight)

        var buffer = NavigationBar(coordinator: coordinator).render(
            title: title, subtitle: subtitle, hidesBack: hidesBack, hidesTitle: hidesTitle, width: width,
            escapeHandlerSlot: escapeHandlerSlot,
            items: screenContext.environment.navigationBarItems, context: context)
        buffer.appendVertically(content)
        return (buffer, zoom)
    }
}

// MARK: - Identity tags

/// Identity tag for the pushed screen, so every screen in a stack shares one
/// identity slot: pushing a second screen of the same shape must not inherit
/// the first one's `@State`, and coming back must not find the screen's state
/// filed under the destination view's type.
private enum NavigationScreen {}
