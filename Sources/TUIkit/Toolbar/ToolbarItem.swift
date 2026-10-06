//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarItem.swift
//
//  The pieces of toolbar content: an item, a group of items, and a spacer.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Toolbar Item

/// A model that represents an item which can be placed in the toolbar or
/// navigation bar — mirrors SwiftUI's `ToolbarItem`.
///
/// ```swift
/// NoteList()
///     .toolbar {
///         ToolbarItem(placement: .primaryAction) {
///             Button("New") { addNote() }
///         }
///     }
/// ```
///
/// The item's view is drawn in the bar its ``ToolbarItemPlacement`` names, in
/// the environment of the view that declared it: a `.foregroundStyle(_:)` or a
/// `.disabled(_:)` written above `.toolbar` reaches the item, as it would reach
/// a child. Its controls are in the Tab ring, after the page's, and their
/// keyboard shortcuts are live.
public struct ToolbarItem<ID, Content: View>: ToolbarContent {
    /// The item's identifier: `()` for an item made without one.
    public let id: ID

    /// Where the item goes.
    let placement: ToolbarItemPlacement

    /// What the item draws.
    let content: Content

    /// Never called: an item hands itself to the bar.
    public var body: Never { fatalError("ToolbarItem hands itself to the bar") }
}

extension ToolbarItem where ID == () {
    /// Creates a toolbar item with the specified placement and content.
    ///
    /// - Parameters:
    ///   - placement: Which section of the toolbar the item should be placed in.
    ///   - content: The content of the item.
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.id = ()
        self.placement = placement
        self.content = content()
    }
}

extension ToolbarItem where ID == String {
    /// Creates a toolbar item with the specified placement and content, which
    /// allows for user customization.
    ///
    /// The identifier is the item's identity in the bar, so its `@State`
    /// follows it rather than its position. A terminal toolbar has no
    /// customization sheet (`toolbar(id:content:)`), so the identifier does
    /// nothing else.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this item.
    ///   - placement: Which section of the toolbar the item should be placed in.
    ///   - content: The content of the item.
    public init(id: String, placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.id = id
        self.placement = placement
        self.content = content()
    }
}

extension ToolbarItem: @MainActor Identifiable where ID: Hashable {}

extension ToolbarItem: _ToolbarContentPrimitive {
    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        items.append(placement: placement, view: AnyView(content), id: id as? String)
    }
}

// MARK: - Toolbar Item Group

/// A model that represents a group of toolbar items which can be placed in the
/// toolbar or navigation bar — mirrors SwiftUI's `ToolbarItemGroup`.
///
/// The group's views sit side by side in the bar its placement names, one
/// column apart.
public struct ToolbarItemGroup<Content: View>: ToolbarContent {
    /// Where the group goes.
    let placement: ToolbarItemPlacement

    /// The group's views.
    let content: Content

    /// Creates a toolbar item group with the specified placement and content.
    ///
    /// - Parameters:
    ///   - placement: Which section of the toolbar all of the content should be
    ///     placed in.
    ///   - content: The content of the group.
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    /// Never called: a group hands itself to the bar.
    public var body: Never { fatalError("ToolbarItemGroup hands itself to the bar") }
}

extension ToolbarItemGroup: _ToolbarContentPrimitive {
    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        items.append(placement: placement, view: AnyView(HStack(spacing: 1) { content }))
    }
}

// MARK: - Toolbar Spacer

/// How a ``ToolbarSpacer`` sizes itself — mirrors SwiftUI's `SpacerSizing`.
public struct SpacerSizing: Sendable, Equatable {
    /// Whether the spacer takes the room the bar has to spare.
    let isFlexible: Bool

    /// The fixed spacer sizing behavior: one column, the gap a terminal bar
    /// puts between groups.
    public static let fixed = Self(isFlexible: false)

    /// The flexible spacer sizing behavior: the room the bar has to spare,
    /// shared with any other flexible spacer.
    public static let flexible = Self(isFlexible: true)
}

/// A standard space item in toolbars — mirrors SwiftUI's `ToolbarSpacer`.
///
/// A ``SpacerSizing/flexible`` spacer pushes the items after it along the bar;
/// a ``SpacerSizing/fixed`` one is a column of space.
public struct ToolbarSpacer: ToolbarContent {
    /// How the spacer sizes itself.
    let sizing: SpacerSizing

    /// Where the spacer goes.
    let placement: ToolbarItemPlacement

    /// Creates a new toolbar spacer.
    ///
    /// - Parameters:
    ///   - sizing: The sizing behavior of the spacer.
    ///   - placement: The placement of the spacer.
    public init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic) {
        self.sizing = sizing
        self.placement = placement
    }

    /// Never called: a spacer hands itself to the bar.
    public var body: Never { fatalError("ToolbarSpacer hands itself to the bar") }
}

extension ToolbarSpacer: _ToolbarContentPrimitive {
    /// A fixed spacer is a column of space, drawn as an item; a flexible one is
    /// marked, and the bar lays it out as a `Spacer` of its own — wrapped in an
    /// item it was no spacer to the bar's stack, which tells spacers by type,
    /// and the items either side of it stayed together.
    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        let view =
            sizing.isFlexible
            ? AnyView(Spacer(minLength: 0)) : AnyView(Text(" "))
        items.append(placement: placement, view: view, isFlexibleSpace: sizing.isFlexible)
    }
}
