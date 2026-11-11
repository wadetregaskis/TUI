//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationCoordinator.swift
//
//  The rendezvous between a NavigationStack, the links inside it, and the
//  .navigationDestination modifiers that say what each pushed value shows.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - View destination token

/// The value a ``NavigationLink`` pushes when it was given a *view* to show
/// rather than a value to look up (`NavigationLink("Detail") { DetailView() }`).
///
/// The link has no data of its own to put on the path, so it pushes this token
/// and registers the view under the same id. The id is the link's own render
/// identity path, which is stable frame to frame and distinct per link — the
/// same property every default `focusID` in the framework relies on.
struct NavigationViewToken: Hashable {
    let id: String
}

// MARK: - NavigationCoordinator

/// Per-``NavigationStack`` state that has to outlive a single frame: the
/// destination registry, and the accessors for whichever path storage the
/// stack was created with.
///
/// Held by the stack in `@State` so it is one object for the stack's lifetime —
/// a `NavigationLink` rendered in frame 1 captures it, and the button action it
/// installs is still pushing onto the same path in frame 500.
///
/// `@MainActor`, unlike ``ScrollToRegistry`` which it otherwise resembles: this
/// one *builds views* (a destination is a `AnyView`-returning closure), and
/// every `View` initializer is main-actor isolated. Both of its callers — the
/// render loop and event dispatch — are already on the main actor.
@MainActor
final class NavigationCoordinator {

    /// Destination builders, keyed by the dynamic type of the value pushed.
    /// Registered by `.navigationDestination(for:)` as it renders, and never
    /// cleared: a builder must still be found on the frames where the modifier
    /// itself did not re-render.
    private var builders: [ObjectIdentifier: (AnyHashable) -> AnyView] = [:]

    /// Views pushed directly by `NavigationLink(destination:)`, keyed by the
    /// link's identity path, each with the pass that last registered it.
    /// Refreshed every pass the link renders — the stack renders its root even
    /// while a screen is pushed — and swept by ``endRegistrationPass()``.
    private var viewDestinations: [String: ViewDestination] = [:]

    /// The stack's render passes, counted by ``beginRegistrationPass()``.
    private var registrationPass: UInt64 = 0

    /// Whether a registration has added a destination since the last sweep.
    private var addedSinceSweep = false

    /// What clears the app's binding for each screen a
    /// `navigationDestination(isPresented:)` or `(item:)` pushed, keyed by
    /// that screen's token id, for as long as the token is on the path.
    ///
    /// The modifier notices a pop itself while it renders, but a pop to the
    /// root takes off the screen it is written on too, and then nothing
    /// renders it: the flag stayed true, and the next visit to that screen
    /// pushed the destination straight back on. SwiftUI sets the binding back
    /// to false whatever route the pop took, so the stack does it here, at the
    /// start of its next pass (``beginRegistrationPass()``).
    private var presentedBindings: [String: () -> Void] = [:]

    /// The screen each view destination's token was pushed over, by token id
    /// (``push(_:over:)``): what tells a destination written beside another on
    /// one screen from the screens above that screen.
    private var presentedDepths: [String: Int] = [:]

    /// A view a link registered, and the pass it was last registered in.
    private struct ViewDestination {
        let view: AnyView
        let pass: UInt64
    }

    /// How many passes may go by between sweeps when nothing has been added:
    /// how long a link that left keeps its destination at most.
    static let sweepInterval: UInt64 = 64

    /// Reads the current path. Re-installed by the stack each render pass, so
    /// it always reflects the binding the stack was given this frame.
    var read: () -> [AnyHashable] = { [] }

    /// Writes the path back. See ``read``.
    var write: ([AnyHashable]) -> Void = { _ in }

    /// The depth the last render pass drew, so a pop can be told from a push.
    ///
    /// Each depth is its own focus section, and a section only gives its
    /// remembered focus back when it is *deactivated* — so the stack has to
    /// notice that it has come back UP and say which levels it left. Nothing
    /// else in the tree knows: a frame at depth 1 looks the same whether it
    /// arrived from 0 or from 2.
    var renderedDepth = 0

    /// The title each depth showed while it was the top screen, indexed by
    /// depth (0 is the root).
    ///
    /// A breadcrumb needs the titles of screens that are NOT being rendered,
    /// and a title is a preference — published by the screen that drew it, on
    /// the frame it drew. So there is nowhere to read an ancestor's title from;
    /// it has to have been remembered when that screen was on top, which is
    /// what this does.
    ///
    /// The consequence worth knowing: a crumb shows the title its screen had
    /// when you left it. A screen whose title would have changed while it was
    /// buried shows the old one until you go back to it. For the thing a
    /// breadcrumb is for — "where am I, and how do I get back" — that is the
    /// right answer anyway, since it names the screen you would return to.
    private var titlesByDepth: [String] = []

    /// What the stack keeps to zoom a screen in and out
    /// (``ZoomNavigationTransition``, `NavigationZoom.swift`).
    var zoom = NavigationZoomState()

    /// The top-bar items the screen on top declares, which the stack's bar
    /// draws: one object for the stack's life, so the environment value that
    /// carries it is the same every frame.
    let barItems = NavigationBarItems()

    nonisolated init() {}
}

// MARK: - Path

extension NavigationCoordinator {

    /// How many screens are pushed above the root.
    var depth: Int { read().count }

    /// The value at the top of the path, or `nil` when showing the root.
    var top: AnyHashable? { read().last }

    /// Pushes a value, showing whatever destination matches its type.
    ///
    /// A typed path binding (`NavigationStack(path: $recipes)`) can only carry
    /// values of its own element type; pushing anything else onto one is
    /// dropped by the write-back, exactly as the binding's type says it must
    /// be. Use ``NavigationPath`` when the screens are driven by more than one
    /// type of value.
    func push(_ value: AnyHashable) {
        var elements = read()
        elements.append(value)
        write(elements)
    }

    /// Pushes `value`, a view destination's token, over the screen at
    /// `depth` — the root at `0` — taking off what is over that screen first,
    /// as SwiftUI does for a screen a view destination written on that screen
    /// pushes (measured,
    /// `Tools/SwiftUIProbes/Navigation path and view destinations/navpath.out`,
    /// case B): a `navigationDestination(isPresented:)` on the root, presented
    /// while values are pushed, empties the path, and Back returns to the root.
    ///
    /// Kept: the screens right over that one that destinations written beside
    /// this one pushed, so two stacked on one view still stack, each over the
    /// other (unmeasured on SwiftUI; TUI's behaviour before, kept).
    func push(_ value: AnyHashable, over depth: Int) {
        let elements = read()
        var kept = Array(elements.prefix(depth))
        for element in elements.dropFirst(depth) {
            guard let token = element.base as? NavigationViewToken, presentedDepths[token.id] == depth else { break }
            kept.append(element)
        }
        kept.append(value)
        if let token = value.base as? NavigationViewToken { presentedDepths[token.id] = depth }
        write(kept)
    }

    /// Records the title `depth` is showing, for later crumbs.
    ///
    /// Only two depths report in any one frame — the root, which renders
    /// off-screen, and whatever is on top — so everything between them is
    /// remembered from the frames when it *was* on top. That is the whole point
    /// of this table.
    ///
    /// Which is why a *changed* title from the screen on top drops the depths
    /// above it and an unchanged one does not. A change there means a different
    /// screen is at that depth, so the names below it in the trail describe
    /// screens the user never opened. An unchanged one is just a screen
    /// re-reporting itself, as the root does every frame; truncating on that
    /// would erase the middle of the trail before anything could read it.
    ///
    /// A `buried` report — the root's, drawn off-screen, or a collapsed split's
    /// column behind the one on top — cannot mean a different screen: what is
    /// at a buried depth is fixed by the path above it. So its title, changed,
    /// is replaced where it stands. Read as a different screen, a root titled
    /// "Inbox (4)" turning "Inbox (5)" dropped every depth above it, and the
    /// middle of the trail came back as "…".
    func recordTitle(_ title: String, atDepth depth: Int, buried: Bool = false) {
        if depth < titlesByDepth.count {
            guard titlesByDepth[depth] != title else { return }
            if buried {
                titlesByDepth[depth] = title
                return
            }
            titlesByDepth.removeSubrange(depth...)
        }
        while titlesByDepth.count < depth { titlesByDepth.append("") }
        titlesByDepth.append(title)
    }

    /// The remembered titles from the root up to (and including) `depth`.
    func titles(upTo depth: Int) -> [String] {
        Array(titlesByDepth.prefix(depth + 1))
    }

    /// Pops `count` screens, stopping at the root.
    func pop(_ count: Int = 1) {
        var elements = read()
        guard !elements.isEmpty else { return }
        elements.removeLast(min(count, elements.count))
        write(elements)
    }
}

// MARK: - Focus sections

extension NavigationCoordinator {
    /// Activates the focus section for `depth`, deactivating any deeper ones
    /// this navigation had entered — deepest first, so each level hands its
    /// focus back up the way it was given.
    ///
    /// `sectionID` names each depth's section, or gives `nil` for a depth with
    /// none of its own: a stack's root is ordinary page content and belongs in
    /// whatever section the page is already using, which is also where the
    /// deepest `deactivateSection` reverts to.
    ///
    /// - Returns: the section the screen at `depth` should register in, or
    ///   `nil` where `sectionID` gives none.
    func enterSection(depth: Int, context: RenderContext, sectionID: (Int) -> String?) -> String? {
        let focusManager = context.environment.focusManager
        // Not while rendering as a modal's dimmed backdrop: that pass carries a
        // THROWAWAY focus manager, so the deactivation would land on an object
        // nobody reads — and consuming `renderedDepth` here would spend the
        // trigger, so the real manager would never hear about the pop at all.
        // The page under a presentation is not navigating; it is a picture.
        guard let focusManager, !focusManager.isBackdrop else { return nil }
        if renderedDepth > depth {
            for deeper in stride(from: renderedDepth, to: depth, by: -1) {
                if let id = sectionID(deeper) { focusManager.deactivateSection(id: id) }
            }
        }
        let pushed = renderedDepth < depth
        renderedDepth = depth
        guard let id = sectionID(depth) else { return nil }
        // Registration is per-frame presence: sections are rebuilt every pass,
        // so the section has to be declared again each time or its controls
        // have nowhere to register. For the same reason it is declared to any
        // value-memoizing ancestor, as `.focusSection` declares its own: a
        // navigation served from the cache registers no section at all.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        focusManager.registerSection(id: id)
        // Activation is NOT. It is a transition — it remembers the section it
        // leaves, drops the focus, and restores this one's memory — so calling
        // it every frame while something else is active (an alert or sheet
        // presented FROM a pushed screen) took the focus back from it on every
        // pass: the dialog's control was focused for under a frame, a field in
        // it was torn down and restarted continuously, and the render loop
        // spun at the frame cap for as long as the dialog was up.
        if pushed { focusManager.activateSection(id: id) }
        return id
    }
}

// MARK: - Destinations

extension NavigationCoordinator {

    /// Registers the view to show for pushed values of the type `type`
    /// identifies, read as `D`.
    func register<D: Hashable>(_ type: ObjectIdentifier, builder: @escaping (D) -> AnyView) {
        builders[type] = { erased in
            guard let value = erased.base as? D else { return AnyView(EmptyView()) }
            return builder(value)
        }
    }

    /// Registers the view a `NavigationLink(destination:)` pushes.
    func register(viewDestination: AnyView, forToken id: String) {
        let entry = ViewDestination(view: viewDestination, pass: registrationPass)
        if viewDestinations.updateValue(entry, forKey: id) == nil { addedSinceSweep = true }
    }

    /// How many view destinations are registered. For tests: a number that
    /// only grows is a leak.
    var viewDestinationCount: Int { viewDestinations.count }

    /// Starts one of the stack's render passes: the links in it register
    /// under this pass.
    func beginRegistrationPass() {
        registrationPass &+= 1
        if !presentedBindings.isEmpty { dismissPoppedPresentations() }
    }

    /// Remembers how to clear the binding that put token `id` on the path.
    /// See ``presentedBindings``.
    func trackPresentation(token id: String, dismiss: @escaping () -> Void) {
        presentedBindings[id] = dismiss
    }

    /// Forgets token `id`'s binding: its modifier saw the screen go itself.
    func untrackPresentation(token id: String) {
        presentedBindings[id] = nil
        presentedDepths[id] = nil
    }

    /// Clears the binding of every tracked screen that is no longer on the
    /// path, by whatever route it left.
    private func dismissPoppedPresentations() {
        var onPath: Set<String> = []
        for value in read() {
            if let token = value.base as? NavigationViewToken { onPath.insert(token.id) }
        }
        let popped = presentedBindings.filter { !onPath.contains($0.key) }
        for (id, dismiss) in popped {
            presentedBindings[id] = nil
            dismiss()
        }
    }

    /// Ends the pass ``beginRegistrationPass()`` started, dropping the view
    /// destinations no link registered in it, unless their token is on the
    /// path: a screen buried under another is not rendered, and neither are
    /// its links, yet popping back to the screen above it needs its view.
    ///
    /// Every link that ever drew used to stay registered for the stack's life,
    /// holding its destination view and whatever that captured: a list of
    /// links over changing data grew by a view per row it ever showed.
    ///
    /// Swept when a pass added a destination, which is the only way the table
    /// grows, and otherwise once every ``sweepInterval`` passes for the links
    /// that left, so a steady frame pays nothing proportional to the table.
    /// A link served from a memo registers again from the memo's effect
    /// journal (`NavigationLink`), so it is not taken for gone.
    func endRegistrationPass() {
        guard addedSinceSweep || registrationPass.isMultiple(of: Self.sweepInterval) else { return }
        addedSinceSweep = false
        var onPath: Set<String> = []
        for value in read() {
            if let token = value.base as? NavigationViewToken { onPath.insert(token.id) }
        }
        var gone: [String] = []
        for (id, entry) in viewDestinations where entry.pass != registrationPass && !onPath.contains(id) {
            gone.append(id)
        }
        for id in gone {
            viewDestinations[id] = nil
        }
    }

    /// The view for a pushed value, or `nil` when nothing has claimed its type.
    ///
    /// A `nil` here is the navigation equivalent of a broken link: the value is
    /// on the path but no `.navigationDestination(for:)` for its type has ever
    /// rendered. The stack shows an empty screen with a working back button
    /// rather than dropping the value, so the app stays navigable.
    func destination(for value: AnyHashable) -> AnyView? {
        if let token = value.base as? NavigationViewToken {
            return viewDestinations[token.id]?.view
        }
        return builders[ObjectIdentifier(type(of: value.base))].map { $0(value) }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The enclosing ``NavigationStack``'s coordinator: the path the links
    /// inside push onto, and the registry `.navigationDestination(for:)` fills
    /// in. `nil` outside any stack, which is what makes a `NavigationLink`
    /// there inert rather than a crash.
    ///
    /// Kept in the substrate's `.navigationCoordinator` slot
    /// (``FeatureObjectSlot``), which detaching an environment clears.
    var navigationCoordinator: NavigationCoordinator? {
        get { self[featureObject: .navigationCoordinator] as? NavigationCoordinator }
        set { self[featureObject: .navigationCoordinator] = newValue }
    }

    /// Which screen of the enclosing ``NavigationStack`` this is: `0` on its
    /// root, the screen's place on the path above it. `nil` outside a stack's
    /// screens. A view destination written here puts its screen over this one
    /// (`NavigationCoordinator.push(_:over:)`).
    var navigationScreenDepth: Int? {
        get { self[NavigationScreenDepthKey.self] }
        set { self[NavigationScreenDepthKey.self] = newValue }
    }
}

private struct NavigationScreenDepthKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}
