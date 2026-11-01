//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarContent.swift
//
//  The content a `.toolbar { … }` declares: items, each with a placement, that
//  the window's bars draw.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Toolbar Content

/// Conforming types represent items that can be placed in various locations in
/// a toolbar — mirrors SwiftUI's `ToolbarContent`.
///
/// You write toolbar content in a ``ToolbarContentBuilder`` closure passed to
/// `toolbar(content:)`: ``ToolbarItem``s, ``ToolbarItemGroup``s and
/// ``ToolbarSpacer``s, composed with `if`, `if`/`else` and `Group`. A type of
/// your own conforms by returning such content from its
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

    /// The default item a ``DefaultToolbarItem`` places, which declaring it
    /// claims from the window's chrome; `nil` for every other item.
    var defaultKind: ToolbarDefaultItemKind.Kind?

    /// Whether the item is a ``ToolbarTitleMenu``: drawn as the top bar's
    /// title, not beside it.
    var isTitleMenu = false

    /// What a customizable toolbar's modifiers said of the item
    /// (``CustomizableToolbarContent``).
    var customization = _ToolbarItemCustomization()

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
        placement: ToolbarItemPlacement, view: AnyView, id: String? = nil, isFlexibleSpace: Bool = false,
        defaultKind: ToolbarDefaultItemKind.Kind? = nil, isTitleMenu: Bool = false
    ) {
        items.append(
            _ToolbarItemSpec(
                placement: placement, view: view, id: id, isFlexibleSpace: isFlexibleSpace,
                defaultKind: defaultKind, isTitleMenu: isTitleMenu, path: path))
    }

    /// Annotates every item collected since the collector held `start` of
    /// them: what a modifier on toolbar content says of the items its content
    /// hands over.
    mutating func annotate(from start: Int, _ body: (inout _ToolbarItemSpec) -> Void) {
        for index in start..<items.count { body(&items[index]) }
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
        TUIChrome.appendToolbarItems(content, to: &self)
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

// MARK: - Shared Background

extension ToolbarContent {
    /// Controls the visibility of the background toolbar items share with the
    /// other items of their group — mirrors SwiftUI's
    /// `ToolbarContent.sharedBackgroundVisibility(_:)`.
    ///
    /// SwiftUI's macOS 26 toolbar sets each group of items on a shared piece of
    /// glass, and ``Visibility/hidden`` takes an item off it. A terminal bar has
    /// no glass under its groups: every item sits on the bar's own fill
    /// (`.toolbarBackground(_:for:)`), the one background they all share. So
    /// ``Visibility/hidden`` is what the bar draws already, and
    /// ``Visibility/visible`` and ``Visibility/automatic`` leave the item on
    /// the bar's fill.
    ///
    /// - Parameter visibility: The visibility of the shared background.
    /// - Returns: The content, unchanged in a terminal bar.
    public func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent {
        _SharedBackgroundToolbarContent(content: self)
    }
}

/// Toolbar content with its shared background's visibility stated: it hands
/// over its items as they are, a terminal bar having no per-group background
/// to show or hide.
struct _SharedBackgroundToolbarContent<Content: ToolbarContent>: ToolbarContent, _ToolbarContentPrimitive {
    let content: Content

    var body: Never { fatalError("_SharedBackgroundToolbarContent hands its items over itself") }

    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        TUIChrome.appendToolbarItems(content, to: &items)
    }
}

/// Toolbar content that hands over its items unless it is hidden.
struct _HiddenToolbarContent<Content: ToolbarContent>: ToolbarContent, _ToolbarContentPrimitive {
    let content: Content
    let isHidden: Bool

    var body: Never { fatalError("_HiddenToolbarContent hands its items over itself") }

    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        guard !isHidden else { return }
        TUIChrome.appendToolbarItems(content, to: &items)
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
        TUIChrome.appendToolbarItems(self, to: &items)
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

// MARK: - Group

extension Group: ToolbarContent where Content: ToolbarContent {
    /// Creates a group of toolbar content instances — mirrors SwiftUI's
    /// `Group.init(content:)` for toolbar content.
    ///
    /// The group hands over its content's items as they are, each where the
    /// content places it: it groups them for a modifier, or past the ten a
    /// builder block takes, and adds nothing of its own to the bars.
    ///
    /// - Parameter content: A ``ToolbarContentBuilder`` that produces the
    ///   toolbar content instances to group.
    public init(@ToolbarContentBuilder content: () -> Content) {
        self = .grouping(content())
    }

    /// Never called: a group hands its items over itself.
    public var body: Never { fatalError("Group hands its toolbar items over itself") }
}

extension Group: _ToolbarContentPrimitive where Content: ToolbarContent {
    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        TUIChrome.appendToolbarItems(content, to: &items)
    }
}

// MARK: - Blocks

/// Several pieces of toolbar content written one after another in a builder:
/// they hand their items over in order.
struct _TupleToolbarContent<each Member: ToolbarContent>: ToolbarContent, _ToolbarContentPrimitive {
    /// The members, in order.
    let members: (repeat each Member)

    init(_ member: repeat each Member) {
        members = (repeat each member)
    }

    var body: Never { fatalError("_TupleToolbarContent hands its items over itself") }

    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        var index = 0
        for member in repeat each members {
            items.step(index, member)
            index += 1
        }
    }
}

/// Toolbar content whose type `if #available(…)` erased.
struct _AnyToolbarContent: ToolbarContent, _ToolbarContentPrimitive {
    /// The erased content.
    let content: any ToolbarContent

    init(_ content: any ToolbarContent) {
        self.content = content
    }

    var body: Never { fatalError("_AnyToolbarContent hands its items over itself") }

    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        items.append(contentsOf: toolbarItems(of: content))
    }
}
