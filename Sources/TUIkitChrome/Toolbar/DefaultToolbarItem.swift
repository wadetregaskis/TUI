//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DefaultToolbarItem.swift
//
//  `DefaultToolbarItem(kind:placement:)`: an item the framework provides by
//  default, placed in a bar (refusal review O17).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Default Toolbar Item

/// A toolbar item that represents a system component — mirrors SwiftUI's
/// `DefaultToolbarItem`.
///
/// It places an item the framework draws by default in the bar its placement
/// names, instead of where the framework would draw it:
///
/// - ``ToolbarDefaultItemKind/search``: the field of the window's `searchable`
///   modifier, with its scopes, instead of at the top of the view the modifier
///   modifies. The first searchable drawn is the window's.
/// - ``ToolbarDefaultItemKind/title``: the window's title and subtitle,
///   instead of in the top bar's title slot.
/// - ``ToolbarDefaultItemKind/sidebarToggle``: a button that hides and shows
///   a ``NavigationSplitView``'s sidebar, as ⌃S does: ◀ while the sidebar
///   shows, ▶ while it is hidden. Declared in one of a split view's columns
///   it toggles that split's sidebar; declared round a split view, the
///   window's — the first split view the window draws. While the button is
///   drawn the split leaves out the ▶ edge column it would show for a hidden
///   sidebar, which the button stands in for; the ◀ on its divider stays,
///   since it also says the column can be hidden. Declare one in each split
///   view's content to give each a button. Where there is no split view, or
///   its toggle was removed (``View/toolbar(removing:)``), it draws nothing.
///   Without one, a window whose page has a top bar shows a button for its
///   first split view at the bar's leading edge, as SwiftUI's macOS toolbar
///   does; an item of this kind for that split places it instead.
/// - ``ToolbarDefaultItemKind/inspectorToggle``, a TUIkit addition: a button
///   that hides and shows an inspector (``View/inspector(isPresented:content:)``),
///   ▶ while it shows, ◀ while it is hidden — the mirror of the sidebar's. It
///   toggles the inspector it is declared round or in, else the window's
///   first. The window shows none without one, as SwiftUI's toolbar shows no
///   inspector button.
///
/// ```swift
/// NavigationStack {
///     NoteList()
///         .toolbar {
///             ToolbarSpacer(.flexible, placement: .bottomBar)
///             DefaultToolbarItem(kind: .search, placement: .bottomBar)
///         }
/// }
/// .searchable(text: $query)
/// ```
///
/// Declared inside the searchable's content, as above, the field moves a frame
/// after the toolbar is first declared, as a bar appears a frame after its
/// first item (the first frame of all has it); declared round the searchable, at
/// once. In a sheet, a cover or a popover, whose items are drawn round its
/// content, the item draws nothing and the field stays where it is.
public struct DefaultToolbarItem: ToolbarContent {
    /// What the item is.
    let kind: ToolbarDefaultItemKind.Kind

    /// Where the item goes.
    let placement: ToolbarItemPlacement

    /// What a toggle's button shows beside its arrow, or `nil`.
    let label: AnyView?

    /// Creates a toolbar item for a component the framework provides.
    ///
    /// - Parameters:
    ///   - kind: The kind of item.
    ///   - placement: Which section of the toolbar the item should be placed in.
    public init(kind: ToolbarDefaultItemKind, placement: ToolbarItemPlacement = .automatic) {
        self.kind = kind.kind
        self.placement = placement
        self.label = nil
    }

    /// Creates a toolbar item for a component the framework provides, with a
    /// label that names it.
    ///
    /// A TUIkit addition, for a toggle's button: with a sidebar on each side, or
    /// several split views, two arrows alone do not say which panel each one
    /// works.
    ///
    /// ```swift
    /// NavigationSplitView { Folders() } detail: { Editor() }
    ///     .inspector(isPresented: $showsInfo) { Info() }
    ///     .toolbar {
    ///         DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation) {
    ///             Label("Folders", systemImage: "sidebar.left")
    ///         }
    ///         DefaultToolbarItem(kind: .inspectorToggle, placement: .primaryAction) {
    ///             Label("Info", systemImage: "sidebar.right")
    ///         }
    ///     }
    /// ```
    ///
    /// The button draws the label after its arrow, and the label's text names
    /// the panel wherever the panel's toggles are described while the button
    /// is drawn: the button's help ("Hide “Folders”"), and the key hints of
    /// the button, of the split view's ◀ divider and ▶ edge, and of the
    /// inspector's divider ("hide Folders"). The ``ToolbarDefaultItemKind/search``
    /// and ``ToolbarDefaultItemKind/title`` items draw no label.
    ///
    /// - Parameters:
    ///   - kind: The kind of item.
    ///   - placement: Which section of the toolbar the item should be placed in.
    ///   - label: What the button shows after its arrow.
    public init<Label: View>(
        kind: ToolbarDefaultItemKind, placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder label: () -> Label
    ) {
        self.kind = kind.kind
        self.placement = placement
        self.label = AnyView(label())
    }

    /// Never called: an item hands itself to the bar.
    public var body: Never { fatalError("DefaultToolbarItem hands itself to the bar") }
}

extension DefaultToolbarItem: _ToolbarContentPrimitive {
    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        items.append(
            placement: placement, view: AnyView(_DefaultToolbarItemCore(kind: kind, label: label)), defaultKind: kind)
    }
}

/// Draws what a ``DefaultToolbarItem`` places, as the window's chrome holds it
/// once the page has drawn: the field a claimed searchable handed over, or
/// the window's title.
private struct _DefaultToolbarItemCore: View, Renderable, Layoutable {
    let kind: ToolbarDefaultItemKind.Kind
    let label: AnyView?

    var body: Never { fatalError("_DefaultToolbarItemCore renders via Renderable") }

    /// What the item draws: `nil` for nothing — in a presentation, which does
    /// not move the window's items, or with nothing to draw.
    ///
    /// What it reads of the window's chrome — a field a `.searchable` hands
    /// over, a title a `.navigationTitle` sets, a panel's toggle — is set as
    /// the walk draws the page, so it is an unkeyed read
    /// (``VolatileReadTracker/recordUnkeyedRead()``), as `SearchFieldPlace`'s
    /// is: the bar can measure this item before and after in one pass.
    private func item(_ context: RenderContext) -> AnyView? {
        guard let chrome = context.environment.windowChrome, !context.environment.presentationHostsToolbar
        else { return nil }
        context.environment.volatileReadTracker?.recordUnkeyedRead()
        switch kind {
        case .search:
            return chrome.searchField
        case .title:
            return chrome.title.isEmpty ? nil : AnyView(_ToolbarTitle(title: chrome.title, subtitle: chrome.subtitle))
        case .sidebarToggle:
            return AnyView(_PanelToggleButton(panel: .sidebar, label: label))
        case .inspectorToggle:
            return AnyView(_PanelToggleButton(panel: .inspector, label: label))
        case .contentColumnToggle:
            return AnyView(_PanelToggleButton(panel: .content, label: label))
        }
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        item(context).map { TUIkitView.renderToBuffer($0, context: context) } ?? FrameBuffer()
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        item(context).map { measureChild($0, proposal: proposal, context: context) } ?? ViewSize.fixed(0, 0)
    }
}
