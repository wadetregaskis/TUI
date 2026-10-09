//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarContent.swift
//
//  The content a `.toolbar { … }` declares: items, each with a placement, that
//  the window's bars draw.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

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

/// One item a toolbar declaration holds: where it goes, the view it draws, and
/// where it sits in the declaration.
struct _ToolbarItemSpec {
    /// Where the item goes.
    let placement: ToolbarItemPlacement

    /// What the item draws.
    let view: AnyView

    /// The item's identifier, when it was given one (`ToolbarItem(id:)`) — its
    /// identity in the bar, so its `@State` follows it rather than its place.
    let id: String?

    /// Whether the item is a flexible ``ToolbarSpacer``, which the bar lays out
    /// as a `Spacer` of its own row (see ``_ToolbarBarRow``).
    var isFlexibleSpace = false

    /// Where the item sits in the content that declared it: the member of each
    /// block it is in, and the branch of each `if`/`else` — its structural
    /// identity, as a view's in a `ViewBuilder` is.
    ///
    /// Not its index in the flattened list, which is what it was: an item
    /// inside an `if` moved every item after it along by one when the `if`
    /// turned, and each of them took the next one's `@State`.
    var path: [Int]

    /// The key the item's identity step takes under the declaring view: its
    /// identifier if it has one, else its ``path``.
    var slotKey: String {
        if let id { "#" + id } else { path.map(String.init).joined(separator: ".") }
    }
}

/// Collects the items of a toolbar declaration, each at its place in the
/// declaration's structure.
struct _ToolbarItemCollector {
    /// The items collected, in order.
    private(set) var items: [_ToolbarItemSpec] = []

    /// The place being collected: one step per block member and `if` branch.
    private var path: [Int] = []

    /// Adds an item at the current place.
    mutating func append(
        placement: ToolbarItemPlacement, view: AnyView, id: String? = nil, isFlexibleSpace: Bool = false
    ) {
        items.append(
            _ToolbarItemSpec(placement: placement, view: view, id: id, isFlexibleSpace: isFlexibleSpace, path: path))
    }

    /// Adds items collected elsewhere, at their places under the current one.
    mutating func append(contentsOf others: [_ToolbarItemSpec]) {
        for var other in others {
            other.path = path + other.path
            items.append(other)
        }
    }

    /// Collects `content`'s items one step further in, at `index`: a block's
    /// member, an `if`/`else`'s branch.
    @MainActor
    mutating func step<Content: ToolbarContent>(_ index: Int, _ content: Content) {
        path.append(index)
        TUIkitChrome.appendToolbarItems(content, to: &self)
        path.removeLast()
    }
}

/// Toolbar content that hands its items over itself, rather than through
/// ``ToolbarContent/body``. Every toolbar type this framework defines is one;
/// toolbar content an app writes is not, and is walked through its body.
@MainActor
protocol _ToolbarContentPrimitive {
    /// Appends this content's items, in order.
    func appendToolbarItems(to items: inout _ToolbarItemCollector)
}

/// The items `content` declares, in order.
@MainActor
func toolbarItems<Content: ToolbarContent>(of content: Content) -> [_ToolbarItemSpec] {
    var collector = _ToolbarItemCollector()
    appendToolbarItems(content, to: &collector)
    return collector.items
}

/// Appends `content`'s items: a primitive's own, anything else's through its
/// body.
@MainActor
func appendToolbarItems<Content: ToolbarContent>(_ content: Content, to items: inout _ToolbarItemCollector) {
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

    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        guard !isHidden else { return }
        TUIkitChrome.appendToolbarItems(content, to: &items)
    }
}

// MARK: - Optional

extension Optional: ToolbarContent where Wrapped: ToolbarContent {
    /// Never called: an optional hands its items over itself.
    public var body: Never { fatalError("Optional hands its toolbar items over itself") }
}

extension Optional: _ToolbarContentPrimitive where Wrapped: ToolbarContent {
    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        guard let self else { return }
        TUIkitChrome.appendToolbarItems(self, to: &items)
    }
}

// MARK: - Conditional

extension _ConditionalContent: ToolbarContent where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
    /// Never called: a branch hands its items over itself.
    public var body: Never { fatalError("_ConditionalContent hands its toolbar items over itself") }
}

extension _ConditionalContent: _ToolbarContentPrimitive
where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        switch self {
        case .trueContent(let content): items.step(0, content)
        case .falseContent(let content): items.step(1, content)
        }
    }
}

// MARK: - Blocks

/// Several pieces of toolbar content written one after another in a builder:
/// they hand their items over in order.
struct _TupleToolbarContent: ToolbarContent, _ToolbarContentPrimitive {
    /// Appends every member's items, captured where their types were known.
    let appendMembers: @MainActor (inout _ToolbarItemCollector) -> Void

    var body: Never { fatalError("_TupleToolbarContent hands its items over itself") }

    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
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

    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        items.append(contentsOf: self.items)
    }
}
