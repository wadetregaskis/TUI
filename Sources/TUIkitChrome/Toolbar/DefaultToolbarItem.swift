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

    /// Creates a toolbar item for a component the framework provides.
    ///
    /// - Parameters:
    ///   - kind: The kind of item.
    ///   - placement: Which section of the toolbar the item should be placed in.
    public init(kind: ToolbarDefaultItemKind, placement: ToolbarItemPlacement = .automatic) {
        self.kind = kind.kind
        self.placement = placement
    }

    /// Never called: an item hands itself to the bar.
    public var body: Never { fatalError("DefaultToolbarItem hands itself to the bar") }
}

extension DefaultToolbarItem: _ToolbarContentPrimitive {
    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        items.append(placement: placement, view: AnyView(_DefaultToolbarItemCore(kind: kind)), defaultKind: kind)
    }
}

/// Draws what a ``DefaultToolbarItem`` places, as the window's chrome holds it
/// once the page has drawn: the field a claimed searchable handed over, or
/// the window's title.
private struct _DefaultToolbarItemCore: View, Renderable, Layoutable {
    let kind: ToolbarDefaultItemKind.Kind

    var body: Never { fatalError("_DefaultToolbarItemCore renders via Renderable") }

    /// What the item draws: `nil` for nothing — in a presentation, which does
    /// not move the window's items, or with nothing to draw.
    private func item(_ context: RenderContext) -> AnyView? {
        guard let chrome = context.environment.windowChrome, !context.environment.presentationHostsToolbar
        else { return nil }
        switch kind {
        case .search:
            return chrome.searchField
        case .title:
            return chrome.title.isEmpty ? nil : AnyView(_ToolbarTitle(title: chrome.title, subtitle: chrome.subtitle))
        case .sidebarToggle:
            return AnyView(_PanelToggleButton(panel: .sidebar))
        }
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        item(context).map { TUIkitView.renderToBuffer($0, context: context) } ?? FrameBuffer()
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        item(context).map { measureChild($0, proposal: proposal, context: context) } ?? ViewSize.fixed(0, 0)
    }
}
