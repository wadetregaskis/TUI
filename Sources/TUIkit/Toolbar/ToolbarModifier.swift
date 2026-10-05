//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarModifier.swift
//
//  `.toolbar { … }`: a view's declaration of the items it puts in the
//  window's bars.
//
//  Created by Wade Tregaskis
//  License: MIT

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
    public func toolbar<Content: ToolbarContent>(@ToolbarContentBuilder content: () -> Content) -> some View {
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
    public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        _ToolbarModifier(content: self, items: ToolbarItemGroup(placement: .automatic, content: content))
    }
}

// MARK: - The Modifier

/// Declares `items` into the window's chrome as `content` renders.
///
/// Each item is recorded with the environment it was declared in and an
/// identity under this view's — keyed by its place in the declaration (or its
/// `id:`), and by how many `.toolbar`s at this identity enclose this one — so
/// the bar draws it as if it were drawn here.
///
/// Declared on the drawn walk only — a measurement declares nothing — except
/// the first frame's seeding walk, which is a measurement whose whole purpose
/// is to find the chrome (``EnvironmentValues/seedsWindowChrome``).
struct _ToolbarModifier<Content: View, Items: ToolbarContent>: View, Renderable, Layoutable {
    let content: Content
    let items: Items

    var body: Never { fatalError("_ToolbarModifier renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if let chrome = context.environment.windowChrome,
            !context.isMeasuring || context.environment.seedsWindowChrome
        {
            // Declared afresh by every walk, so a memoised ancestor serving its
            // buffer would leave the window with no items: the same refusal
            // `.statusBarItems` makes.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            // How many `.toolbar`s at this same identity are declaring around
            // this one: a modifier renders its content at its own identity, so
            // `Text("p").toolbar { A }.toolbar { B }` — or the same with a
            // `.padding()` between — is two declarations at ONE identity, and
            // their first items took the same slot. The window deduplicates by
            // slot (a walk may render a view twice), so A was never drawn.
            let depth = chrome.beginDeclaring(at: context.identity)
            defer { chrome.endDeclaring(at: context.identity) }
            for item in toolbarItems(of: items) {
                let key = depth == 0 ? item.slotKey : "\(depth)/\(item.slotKey)"
                chrome.declare(
                    WindowChromeState.ToolbarEntry(
                        placement: item.placement, view: item.view, environment: context.environment,
                        identity: context.withChildIdentity(erasedType: _ToolbarItemSlot.self, key: key).identity))
            }
            return TUIkit.renderToBuffer(content, context: context)
        }
        return TUIkit.renderToBuffer(content, context: context)
    }

    /// The items are drawn by the window's bars, so this measures as `content`.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// The identity step a toolbar item takes under the view that declared it.
enum _ToolbarItemSlot {}
