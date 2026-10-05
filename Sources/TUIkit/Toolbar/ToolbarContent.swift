//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarContent.swift
//
//  The content a `.toolbar { … }` declares: items, each with a placement, that
//  the window's bars draw.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Toolbar Content

/// Conforming types represent items that can be placed in various locations in
/// a toolbar — mirrors SwiftUI's `ToolbarContent`.
///
/// You write toolbar content in a ``ToolbarContentBuilder`` closure passed to
/// `toolbar(content:)`: ``ToolbarItem``s,
/// ``ToolbarItemGroup``s and ``ToolbarSpacer``s, composed with `if` and
/// `if`/`else`. A type of your own conforms by returning such content from its
/// ``body-swift.property``, as a view returns views.
///
/// The window's bars draw what the items say. An item placed in the top bar
/// (``ToolbarItemPlacement/primaryAction``, ``ToolbarItemPlacement/navigation``,
/// ``ToolbarItemPlacement/principal`` and the rest) joins the bar above the
/// page; one placed in the bottom bar (``ToolbarItemPlacement/bottomBar``,
/// ``ToolbarItemPlacement/status``) joins the bar below it. A bar exists while
/// something is placed in it.
@MainActor
@preconcurrency
public protocol ToolbarContent {
    /// The type of content representing the body of this toolbar content.
    associatedtype Body: ToolbarContent

    /// The composition of content that comprise the toolbar content.
    @ToolbarContentBuilder var body: Body { get }
}

/// `Never` is toolbar content so the framework's own items can declare
/// `Body == Never`, as SwiftUI's do; their bodies are never asked for. The
/// `body` witness is the one `extension Never: View` already declares.
extension Never: ToolbarContent {}

// MARK: - The Items a Declaration Holds

/// One item a toolbar declaration holds: where it goes, and the view it draws.
struct _ToolbarItemSpec {
    /// Where the item goes.
    let placement: ToolbarItemPlacement

    /// What the item draws.
    let view: AnyView

    /// The item's identifier, when it was given one (`ToolbarItem(id:)`) — its
    /// identity in the bar, so its `@State` follows it rather than its index.
    let id: String?
}

/// Toolbar content that hands its items over itself, rather than through
/// ``ToolbarContent/body``. Every toolbar type this framework defines is one;
/// toolbar content an app writes is not, and is walked through its body.
@MainActor
protocol _ToolbarContentPrimitive {
    /// Appends this content's items, in order.
    func appendToolbarItems(to items: inout [_ToolbarItemSpec])
}

/// The items `content` declares, in order.
@MainActor
func toolbarItems<Content: ToolbarContent>(of content: Content) -> [_ToolbarItemSpec] {
    var items: [_ToolbarItemSpec] = []
    appendToolbarItems(content, to: &items)
    return items
}

/// Appends `content`'s items: a primitive's own, anything else's through its
/// body.
@MainActor
func appendToolbarItems<Content: ToolbarContent>(_ content: Content, to items: inout [_ToolbarItemSpec]) {
    if let primitive = content as? any _ToolbarContentPrimitive {
        primitive.appendToolbarItems(to: &items)
        return
    }
    appendToolbarItems(content.body, to: &items)
}

// MARK: - Hiding

extension ToolbarContent {
    /// Hides a toolbar item within its toolbar — mirrors SwiftUI's
    /// `ToolbarContent.hidden(_:)`.
    ///
    /// A hidden item takes no room in its bar, and a bar whose every item is
    /// hidden is not drawn.
    ///
    /// - Parameter hidden: Whether the toolbar item is hidden.
    /// - Returns: The content, hidden if `hidden` is `true`.
    public func hidden(_ hidden: Bool = true) -> some ToolbarContent {
        _HiddenToolbarContent(content: self, isHidden: hidden)
    }
}

/// Toolbar content that hands over its items unless it is hidden.
struct _HiddenToolbarContent<Content: ToolbarContent>: ToolbarContent, _ToolbarContentPrimitive {
    let content: Content
    let isHidden: Bool

    var body: Never { fatalError("_HiddenToolbarContent hands its items over itself") }

    func appendToolbarItems(to items: inout [_ToolbarItemSpec]) {
        guard !isHidden else { return }
        TUIkit.appendToolbarItems(content, to: &items)
    }
}

// MARK: - Optional

extension Optional: ToolbarContent where Wrapped: ToolbarContent {
    /// Never called: an optional hands its items over itself.
    public var body: Never { fatalError("Optional hands its toolbar items over itself") }
}

extension Optional: _ToolbarContentPrimitive where Wrapped: ToolbarContent {
    func appendToolbarItems(to items: inout [_ToolbarItemSpec]) {
        guard let self else { return }
        TUIkit.appendToolbarItems(self, to: &items)
    }
}

// MARK: - Conditional

extension _ConditionalContent: ToolbarContent where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
    /// Never called: a branch hands its items over itself.
    public var body: Never { fatalError("_ConditionalContent hands its toolbar items over itself") }
}

extension _ConditionalContent: _ToolbarContentPrimitive
where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
    func appendToolbarItems(to items: inout [_ToolbarItemSpec]) {
        switch self {
        case .trueContent(let content): TUIkit.appendToolbarItems(content, to: &items)
        case .falseContent(let content): TUIkit.appendToolbarItems(content, to: &items)
        }
    }
}

// MARK: - Blocks

/// Several pieces of toolbar content written one after another in a builder:
/// they hand their items over in order.
struct _TupleToolbarContent: ToolbarContent, _ToolbarContentPrimitive {
    /// Appends every member's items, captured where their types were known.
    let appendMembers: @MainActor (inout [_ToolbarItemSpec]) -> Void

    var body: Never { fatalError("_TupleToolbarContent hands its items over itself") }

    func appendToolbarItems(to items: inout [_ToolbarItemSpec]) {
        appendMembers(&items)
    }
}

/// Toolbar content whose type `if #available(…)` erased.
struct _AnyToolbarContent: ToolbarContent, _ToolbarContentPrimitive {
    /// The erased content's items.
    let items: [_ToolbarItemSpec]

    @MainActor
    init(_ content: any ToolbarContent) {
        func open<C: ToolbarContent>(_ content: C) -> [_ToolbarItemSpec] { toolbarItems(of: content) }
        items = open(content)
    }

    var body: Never { fatalError("_AnyToolbarContent hands its items over itself") }

    func appendToolbarItems(to items: inout [_ToolbarItemSpec]) {
        items += self.items
    }
}
