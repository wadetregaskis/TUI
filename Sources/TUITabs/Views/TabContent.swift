//  🖥️ TUI — A Terminal UI framework for Swift
//  TabContent.swift
//
//  The protocol a tab view's tabs are written in, the walk that flattens them
//  for the tab view, and the content types that compose tabs: optionals,
//  groups, conditionals, loops and the type-erased tab.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - TabContent

/// A type that provides content for programmatically selectable tabs in a
/// tab view.
///
/// A type conforming to this protocol inherits `@MainActor` isolation from the
/// protocol, as a view does. The simplest tab is a ``Tab``; ``TabSection``
/// groups tabs, ``ForEach`` builds them from a collection, and
/// ``TabContentBuilder`` composes several, with an `if` and a `Group` among
/// them:
///
/// ```swift
/// TabView(selection: $selection) {
///     Tab("Received", systemImage: "tray", value: 0) { ReceivedView() }
///     TabSection("Folders") {
///         ForEach(folders) { folder in
///             Tab(folder.name, systemImage: "folder", value: folder.id) { FolderView(folder) }
///         }
///     }
/// }
/// ```
///
/// Tab content factored into a type of its own is written as SwiftUI's is:
///
/// ```swift
/// struct MailTabs: TabContent {
///     var body: some TabContent<Int> {
///         Tab("Received", systemImage: "tray", value: 0) { ReceivedView() }
///         Tab("Sent", systemImage: "paperplane", value: 1) { SentView() }
///     }
/// }
/// ```
@MainActor
public protocol TabContent<TabValue> {
    /// The type used to drive selection for the containing tab view.
    associatedtype TabValue: Hashable

    /// The type of content representing the body of this tab content.
    associatedtype Body: TabContent where Body.TabValue == TabValue

    /// The content and behavior of this tab.
    @TabContentBuilder<TabValue> var body: Body { get }
}

// MARK: - Flattening

/// A tab recovered from a tab view's content: everything the tab view draws
/// and selects it by.
struct _RawTab {
    /// The tab's selection value, erased — or, for a tab declared without one,
    /// its place among the tab view's tabs, which is what selects it in a tab
    /// view built without a selection (where no tab has a value).
    var value: AnyHashable

    /// The tab's title, as the strip draws it, for a label that is text: a
    /// title with an SF Symbol where one can be drawn (see ``DefaultTabLabel``),
    /// or nothing for a tab with no label.
    var title: String

    /// A label of the app's own (`Tab(content:label:)`), which the strip draws
    /// inside the tab's chip once the tab view has a context — `nil` for the
    /// default label, whose text is ``title``.
    var customLabel: AnyView?

    /// ``customLabel``'s size in cells, measured once the tab view has a
    /// context (`_TabViewCore.measuringCustomLabels(_:)`) — `nil` for a text
    /// label, and before then. A row of chips is as tall as its tallest label.
    var labelCells: CellSize?

    /// The picture an `image:` initialiser named, which a sidebar's row draws
    /// before the title; a strip's chip draws the title alone.
    var icon: Image?

    /// The tab's content, type-erased. `AnyView` is `Layoutable` and forwards
    /// `sizeThatFits` to the wrapped view, so measuring `content` (see the call
    /// sites in `_TabViewCore`) sizes a `Layoutable` child — e.g. a `ScrollView`
    /// — via its own `sizeThatFits` (its content's size), not a render-to-measure
    /// pass that would let a flexible child fill the viewport and defeat
    /// size-to-content.
    var content: AnyView

    /// The tab's badge, drawn after its title in the strip, or `nil`.
    var badge: BadgeValue?

    /// The tab's role.
    var role: TabRole?

    /// Whether the tab is hidden: left out of the strip and of selection.
    var isHidden = false

    /// Whether the tab is disabled: drawn faint, and never selected.
    var isDisabled = false

    /// Where the tab may appear.
    var placement = TabPlacement.automatic

    /// The tab's own spring loading behavior, or `nil` to follow the tab
    /// view's environment (see ``springLoads(inheriting:)``).
    var springLoading: SpringLoadingBehavior?

    /// The strip's text for the badge — a space, then the badge — or `""` for
    /// a tab with none to show.
    var badgeSuffix: String {
        guard let badge, !badge.isHidden else { return "" }
        return " " + badge.displayText
    }

    /// The section the tab is declared in, or `nil` for a tab outside any.
    var section: _RawTabSection?

    /// The identifier a ``TabViewCustomization`` knows the tab by, or `nil`.
    var customizationID: String?

    /// What the tab does besides being selected: its context menu, popovers,
    /// drag and drops (`TabContentInteractions.swift`).
    var interactions = _TabInteractionTraits()

    /// Whether a drag paused over the tab selects it: the tab's own behavior
    /// if it has one, else `inherited`, the tab view's environment's — a tab
    /// spring-loads by default, as SwiftUI's tab views do — and never a
    /// disabled tab, which a click does not select either.
    func springLoads(inheriting inherited: SpringLoadingBehavior) -> Bool {
        !isDisabled && (springLoading ?? inherited).allows(byDefault: true)
    }
}

/// The ``TabSection`` a tab was declared in.
struct _RawTabSection {
    /// Which section this is among the tab view's sections, in declaration
    /// order — what tells two sections with the same header apart.
    let ordinal: Int
    /// The section's header.
    let header: AnyView
    /// The actions `.sectionActions(content:)` gave the section, or `nil`.
    var actions: AnyView?
    /// The identifier a ``TabViewCustomization`` knows the section by, or
    /// `nil`.
    var customizationID: String?
}

/// The tabs a tab view's content declares, in order, for the tab view.
struct _TabList {
    /// The tabs, in order.
    private(set) var tabs: [_RawTab] = []

    /// How many sections have been declared so far.
    private(set) var sectionCount = 0

    /// Appends a tab.
    mutating func append(_ tab: _RawTab) {
        tabs.append(tab)
    }

    /// The value a tab declared without one is selected by: its place among
    /// all the tab view's tabs.
    var nextPosition: AnyHashable { AnyHashable(tabs.count) }

    /// Appends `build`'s tabs as one section with `header`. Into this list, so
    /// a tab's place counts every tab before it, in any section.
    mutating func appendSection(header: AnyView, _ build: (inout Self) -> Void) {
        let section = _RawTabSection(ordinal: sectionCount, header: header)
        sectionCount += 1
        let start = tabs.count
        build(&self)
        for index in start..<tabs.count where tabs[index].section == nil {
            tabs[index].section = section
        }
    }

    /// Gives `build`'s content the customization identifier `id`: the section
    /// it declares, when it declares one — whose tabs carry it by now, an
    /// enclosing section being written onto its tabs only after its content is
    /// built — else each of its tabs. An inner identifier keeps its own.
    mutating func identifying(_ id: String, _ build: (inout Self) -> Void) {
        let start = tabs.count
        let firstSection = sectionCount
        build(&self)
        for index in start..<tabs.count {
            if let section = tabs[index].section, section.ordinal >= firstSection {
                if section.customizationID == nil { tabs[index].section?.customizationID = id }
            } else if tabs[index].customizationID == nil {
                tabs[index].customizationID = id
            }
        }
    }

    /// Applies a tab modifier to the tabs `build` appends.
    mutating func modifying(_ apply: (inout _RawTab) -> Void, _ build: (inout Self) -> Void) {
        let start = tabs.count
        build(&self)
        for index in start..<tabs.count { apply(&tabs[index]) }
    }
}

/// Tab content that hands the tab view its tabs itself, rather than through
/// ``TabContent/body``. Every tab type this framework defines is one; tab
/// content an app writes is not, and is walked through its body. A cast to it
/// is a plain conformance check: nothing parameterizes it. The table's row and
/// column content, whose casts named the row type, have hidden requirements
/// instead (``TableRowContent/_appendRows(_:to:)``).
@MainActor
protocol _TabContentPrimitive {
    /// Appends this content's tabs, in order.
    func appendTabs(to tabs: inout _TabList)
}

/// The tabs `content` declares, in order.
@MainActor
func tabList<Content: TabContent>(of content: Content) -> _TabList {
    var tabs = _TabList()
    appendTabs(content, to: &tabs)
    return tabs
}

/// Appends `content`'s tabs: a primitive's own, anything else's through its
/// body.
@MainActor
func appendTabs<Content: TabContent>(_ content: Content, to tabs: inout _TabList) {
    if let primitive = content as? any _TabContentPrimitive {
        primitive.appendTabs(to: &tabs)
        return
    }
    appendTabs(content.body, to: &tabs)
}

// MARK: - Optional

extension Optional: TabContent where Wrapped: TabContent {
    /// The type used to drive selection for the containing tab view.
    public typealias TabValue = Wrapped.TabValue

    /// An optional is primitive tab content: it hands its tabs over itself.
    public var body: Wrapped? {
        // `return`, so the builder the requirement names does not apply.
        return self  // swiftlint:disable:this implicit_return
    }
}

extension Optional: _TabContentPrimitive where Wrapped: TabContent {
    func appendTabs(to tabs: inout _TabList) {
        guard let self else { return }
        TUITabs.appendTabs(self, to: &tabs)
    }
}

// MARK: - Group

extension Group: TabContent where Content: TabContent {
    /// The type used to drive selection for the containing tab view.
    public typealias TabValue = Content.TabValue

    /// A group is primitive tab content: it hands its tabs over itself.
    public var body: Group<Content> {
        return self  // swiftlint:disable:this implicit_return
    }

    /// Creates a group of tabs.
    ///
    /// - Parameter content: The tabs to group.
    public init<V>(@TabContentBuilder<V> content: () -> Content) where V == Content.TabValue {
        self = .grouping(content())
    }
}

extension Group: _TabContentPrimitive where Content: TabContent {
    func appendTabs(to tabs: inout _TabList) {
        TUITabs.appendTabs(content, to: &tabs)
    }
}

// MARK: - Conditional

extension _ConditionalContent: TabContent
where TrueContent: TabContent, FalseContent: TabContent, TrueContent.TabValue == FalseContent.TabValue {
    /// The type used to drive selection for the containing tab view.
    public typealias TabValue = TrueContent.TabValue

    /// A branch is primitive tab content: it hands its tabs over itself.
    public var body: _ConditionalContent<TrueContent, FalseContent> {
        return self  // swiftlint:disable:this implicit_return
    }
}

extension _ConditionalContent: _TabContentPrimitive
where TrueContent: TabContent, FalseContent: TabContent, TrueContent.TabValue == FalseContent.TabValue {
    func appendTabs(to tabs: inout _TabList) {
        switch self {
        case .trueContent(let content): TUITabs.appendTabs(content, to: &tabs)
        case .falseContent(let content): TUITabs.appendTabs(content, to: &tabs)
        }
    }
}

// MARK: - ForEach

@MainActor extension ForEach: TabContent where Content: TabContent {
    /// The type used to drive selection for the containing tab view.
    public typealias TabValue = Content.TabValue

    /// A loop is primitive tab content: it hands its tabs over itself.
    public var body: ForEach<Data, ID, Content> {
        return self  // swiftlint:disable:this implicit_return
    }

    /// Creates an instance that uniquely identifies and creates tabs across
    /// updates based on the identity of the underlying data.
    ///
    /// - Parameters:
    ///   - data: The identified data that the instance uses to create tabs
    ///     dynamically.
    ///   - content: The tab content builder that creates tabs dynamically.
    public init<V>(
        _ data: Data, @TabContentBuilder<V> content: @escaping (Data.Element) -> Content
    ) where ID == Data.Element.ID, V == Content.TabValue, Data.Element: Identifiable {
        self.init(storing: data, id: \Data.Element.id, directID: { $0.id }, content: content)
    }

    /// Creates an instance that uniquely identifies and creates tabs across
    /// updates based on the provided key path to the underlying data's
    /// identifier.
    ///
    /// - Parameters:
    ///   - data: The data that the instance uses to create tabs dynamically.
    ///   - id: The key path to the provided data's identifier.
    ///   - content: The tab content builder that creates tabs dynamically.
    public init<V>(
        _ data: Data, id: KeyPath<Data.Element, ID>,
        @TabContentBuilder<V> content: @escaping (Data.Element) -> Content
    ) where V == Content.TabValue {
        self.init(storing: data, id: id, content: content)
    }

    /// Creates an instance that computes tabs over a given constant range.
    ///
    /// - Parameters:
    ///   - data: A constant range.
    ///   - content: The tab content builder that creates tabs dynamically.
    public init<V>(
        _ data: Range<Int>, @TabContentBuilder<V> content: @escaping (Int) -> Content
    ) where Data == Range<Int>, ID == Int, V == Content.TabValue {
        self.init(storing: data, id: \.self, directID: { $0 }, content: content)
    }
}

@MainActor extension ForEach: _TabContentPrimitive where Content: TabContent {
    func appendTabs(to tabs: inout _TabList) {
        for element in data {
            TUITabs.appendTabs(content(element), to: &tabs)
        }
    }
}

// MARK: - AnyTabContent

/// Type-erased tab content.
///
/// ```swift
/// var tabs: AnyTabContent<Int> {
///     isCompact ? AnyTabContent(compactTabs) : AnyTabContent(regularTabs)
/// }
/// ```
public struct AnyTabContent<SelectionValue: Hashable>: TabContent {
    /// The type used to drive selection for the containing tab view.
    public typealias TabValue = SelectionValue

    /// Appends the erased content's tabs, captured where its type was known.
    private let appendErased: @MainActor (inout _TabList) -> Void

    /// Creates an instance that type-erases tab content.
    ///
    /// - Parameter tabContent: The tab content to erase.
    public init<T: TabContent>(_ tabContent: T) where SelectionValue == T.TabValue {
        appendErased = { TUITabs.appendTabs(tabContent, to: &$0) }
    }

    /// Erased content is primitive: it hands its tabs over itself.
    public var body: AnyTabContent<SelectionValue> {
        return self  // swiftlint:disable:this implicit_return
    }
}

extension AnyTabContent: _TabContentPrimitive {
    func appendTabs(to tabs: inout _TabList) {
        appendErased(&tabs)
    }
}
