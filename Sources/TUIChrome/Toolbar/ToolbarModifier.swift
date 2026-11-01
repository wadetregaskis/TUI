//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarModifier.swift
//
//  `.toolbar { … }`: a view's declaration of the items it puts in the
//  window's bars.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Public Modifiers

extension View {
    /// Populates the toolbar or navigation bar with the specified items —
    /// mirrors SwiftUI's `toolbar(content:)` for toolbar content.
    ///
    /// ```swift
    /// NoteList()
    ///     .navigationTitle("Notes")
    ///     .toolbar {
    ///         ToolbarItem(placement: .primaryAction) {
    ///             Button("New") { addNote() }
    ///         }
    ///         ToolbarItem(placement: .bottomBar) {
    ///             StatusBar()
    ///         }
    ///     }
    /// ```
    ///
    /// Items declared anywhere in the page join the WINDOW's bars, as they do
    /// in SwiftUI: the top bar above the page and the bottom bar below it (see
    /// ``ToolbarItemPlacement`` for which placement goes where). A bar exists
    /// while something is placed in it. Because the page is what declares the
    /// items, a bar that appears or goes does so a frame after the page that
    /// changed it — so declare an app's bars once, at its root, and they never
    /// move.
    ///
    /// - Parameter content: The items representing the content of the toolbar.
    /// - Returns: A view that declares the items.
    nonisolated public func toolbar<Content: ToolbarContent>(@ToolbarContentBuilder content: () -> Content) -> some View {
        _ToolbarModifier(content: self, items: content())
    }

    /// Populates the toolbar or navigation bar with the specified views —
    /// mirrors SwiftUI's `toolbar(content:)` for views.
    ///
    /// The views are placed with ``ToolbarItemPlacement/automatic``: at the
    /// trailing end of the window's top bar, one column apart.
    ///
    /// - Parameter content: The views representing the content of the toolbar.
    /// - Returns: A view that declares the views.
    nonisolated public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        _ToolbarModifier(content: self, items: ToolbarItemGroup(placement: .automatic, content: content))
    }
}

// MARK: - The Modifier

/// Declares `items` into the window's chrome as `content` renders.
///
/// Each item is recorded with the environment it was declared in and an
/// identity under this view's — keyed by its place in the declaration (or its
/// `id:`), and by how many `.toolbar`s at this identity enclose this one
/// (``declaring(in:)``) — so the bar draws it as if it were drawn here.
///
/// Declared on the drawn walk only — a measurement declares nothing — except
/// the first frame's seeding walk, which is a measurement whose whole purpose
/// is to find the chrome (``EnvironmentValues/seedsWindowChrome``).
nonisolated struct _ToolbarModifier<Content: View, Items: ToolbarContent>: View, Renderable, Layoutable {
    let content: Content
    let items: Items

    /// The identifier of a customizable toolbar (`toolbar(id:content:)`), or
    /// `nil` for an ordinary one.
    var customizationID: String?

    @MainActor var body: Never { fatalError("_ToolbarModifier renders via Renderable") }

    @MainActor func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // In a sheet, a cover or a popover the items are drawn here, round the
        // content (`ToolbarPresentationRows.swift`): the window's bars are
        // inert while the presentation holds the input.
        if context.environment.presentationHostsToolbar {
            // A sheet or a cover hosts the items at its edges; a popover's
            // content draws them round this view.
            guard let host = context.environment.presentationToolbar else {
                return renderInPresentation(context: context)
            }
            return hostInPresentation(host, context: context, measuring: false).render()
        }
        let (depth, contentContext) = declaring(in: context)
        if let chrome = context.environment.windowChrome,
            !context.isMeasuring || context.environment.seedsWindowChrome
        {
            // Declared afresh by every walk, so a memoised ancestor serving its
            // buffer would leave the window with no items: the same refusal
            // `.statusBarItems` makes.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            // A screen pushed onto a navigation stack puts its top-bar items
            // in the stack's bar (`NavigationBarItems`), on a drawn walk. The
            // first frame's seeding walk draws no pushed screen: a screen's
            // destination is registered on a drawn walk
            // (`navigationDestination(for:)`, a link's own), and none has run
            // yet — so no screen's items seed the window's rows.
            let stackBar = context.isMeasuring ? nil : context.environment.navigationBarItems
            // A customizable toolbar is listed for its panel, on a drawn walk.
            if !context.isMeasuring { declareCustomizable(into: chrome, context: context) }
            for item in shownItems(context: context) {
                let entry = WindowChromeState.ToolbarEntry(
                    placement: item.placement, view: item.view, environment: context.environment,
                    identity: itemIdentity(item, depth: depth, context: context),
                    isFlexibleSpace: item.isFlexibleSpace, defaultKind: item.defaultKind,
                    isTitleMenu: item.isTitleMenu,
                    keyboardScope: item.placement.role == .keyboard ? context.identity : nil,
                    customizableItem: customizationID.flatMap { toolbar in
                        item.id.map { CustomizableToolbarDeclaration.ItemKey(toolbarID: toolbar, itemID: $0) }
                    })
                if let stackBar, item.goesInNavigationBar {
                    stackBar.drawsItems = Self.drawsItems
                    stackBar.declare(entry)
                    continue
                }
                chrome.declare(entry)
                // A default item moves the framework's own from where it is
                // drawn by default (`DefaultToolbarItem`).
                switch item.defaultKind {
                case .search: chrome.claimSearchField()
                case .title: chrome.removeTitle()
                case .sidebarToggle, .inspectorToggle, .contentColumnToggle, nil: break
                }
            }
        } else if !context.isMeasuring, context.environment.windowChrome == nil, let storage = context.stateStorage {
            retainItems(depth: depth, storage: storage, context: context)
        }
        return TUIView.renderToBuffer(content, context: contentContext)
    }

    /// Keeps the `@State` of the items a render with no window declares
    /// nowhere — a navigation stack's covered root, a row the focus-reach
    /// probe walks past (`withThrowawayFrameDemand`, `focusRingContinuations`).
    ///
    /// Nothing draws them there, and state whose view did not render is
    /// collected at the end of the pass, so a counter in a stack root's
    /// toolbar went back to 0 when a screen was pushed over the root and
    /// popped again, and a search field there was cleared. The view is still
    /// drawn; so, as far as its state is concerned, are its items — as the
    /// window does for a bar it hides (`retainUndrawnItems`).
    @MainActor private func retainItems(depth: Int, storage: StateStorage, context: RenderContext) {
        for item in toolbarItems(of: items) {
            let identity = itemIdentity(item, depth: depth, context: context)
            storage.markActive(identity)
            storage.retainSubtree(identity)
        }
    }

    /// The items are drawn by the window's bars, so this measures as `content`
    /// — except in presented content, which draws them round it.
    @MainActor func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if context.environment.presentationHostsToolbar {
            guard let host = context.environment.presentationToolbar else {
                return sizeInPresentation(proposal: proposal, context: context)
            }
            return hostInPresentation(host, context: context, measuring: true).measure(proposal)
        }
        return measureChild(content, proposal: proposal, context: declaring(in: context).content)
    }
}

/// The identity step a toolbar item takes under the view that declared it.
enum _ToolbarItemSlot {}

@MainActor extension _ToolbarModifier {
    /// How a navigation stack's bar draws a run of the items a screen put in
    /// it: side by side, as a window bar's run (``_ToolbarItemRun``).
    static var drawsItems: @MainActor ([WindowChromeState.ToolbarEntry]) -> AnyView {
        { AnyView(_ToolbarItemRun(entries: $0)) }
    }
}

extension _ToolbarItemSpec {
    /// Whether, declared by a screen pushed onto a navigation stack, the item
    /// goes in the stack's bar: one placed in the top bar's own row. An
    /// accessory bar's, the bottom bar's (`.keyboard`'s too) stay the
    /// window's, as do the title's menu and the default items, which move
    /// the window's own.
    var goesInNavigationBar: Bool {
        placement.bar == .top && placement.accessoryBar == nil && !isTitleMenu && defaultKind == nil
    }
}

// MARK: - Nested Declarations

/// A `.toolbar` declaring around a view: the identity it declares at, and how
/// many `.toolbar`s at that identity enclose it.
struct _ToolbarDeclaration: Hashable {
    let identity: ViewIdentity
    let depth: Int
}

/// Environment key for the innermost `.toolbar` declaring around a view.
private struct EnclosingToolbarDeclarationKey: EnvironmentKey {
    static let defaultValue: _ToolbarDeclaration? = nil
}

extension EnvironmentValues {
    /// The innermost `.toolbar` whose content this is: how the next one in
    /// tells whether it declares at the same identity, and how deep.
    var enclosingToolbarDeclaration: _ToolbarDeclaration? {
        get { self[EnclosingToolbarDeclarationKey.self] }
        set { self[EnclosingToolbarDeclarationKey.self] = newValue }
    }
}

@MainActor extension _ToolbarModifier {
    /// How many `.toolbar`s at this identity enclose this one, and the context
    /// its content is measured and drawn in, which says so to the next one in.
    ///
    /// A modifier renders its content at its own identity, so
    /// `Text("p").toolbar { A }.toolbar { B }` — or the same with a
    /// `.padding()` between — is two declarations at ONE identity, and their
    /// first items took the same slot: the window deduplicates by slot (a walk
    /// may render a view twice), so A was never drawn, and in a sheet the two
    /// shared their `@State` and their focus ID.
    ///
    /// Carried down the environment, so it is the same on every walk — the
    /// window's, a measurement, a navigation stack's covered root, a render
    /// outside an app — and on a second render of the same view.
    func declaring(in context: RenderContext) -> (depth: Int, content: RenderContext) {
        let enclosing = context.environment.enclosingToolbarDeclaration
        let depth = enclosing.map { $0.identity == context.identity ? $0.depth + 1 : 0 } ?? 0
        var contentContext = context
        contentContext.environment.enclosingToolbarDeclaration = _ToolbarDeclaration(
            identity: context.identity, depth: depth)
        return (depth, contentContext)
    }

    /// The identity `item` is drawn at: under this view's, keyed by its place
    /// in the declaration and by `depth` (``declaring(in:)``).
    func itemIdentity(_ item: _ToolbarItemSpec, depth: Int, context: RenderContext) -> ViewIdentity {
        let key = depth == 0 ? item.slotKey : "\(depth)/\(item.slotKey)"
        return context.withChildIdentity(erasedType: _ToolbarItemSlot.self, key: key).identity
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or a container value
/// — a `.tag` among them, as a `Layout` or `ForEach(subviews:)` reads it — can
/// look through this wrapper instead of stopping at it: `.zIndex(1).toolbar {
/// … }` still orders a `ZStack`, as in SwiftUI, where a container value "is
/// unaffected by views that aren't containers". Read-only: it does NOT conform to
/// ``ContentRewrapping``, so its declaration is not multiplied across the
/// members of multi-view content.
@MainActor extension _ToolbarModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}
