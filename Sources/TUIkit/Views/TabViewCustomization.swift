//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewCustomization.swift
//
//  What a person changed about a `.sidebarAdaptable` tab view's sidebar —
//  which tabs it shows, and in what order — and the modifiers that identify
//  tabs and sections to it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - TabViewCustomization

/// The customizations a person makes to an adaptable sidebar tab view.
///
/// Bind a `.sidebarAdaptable` tab view to one with
/// ``View/tabViewCustomization(_:)``, and give the tabs and sections that may
/// be customized a ``TabContent/customizationID(_:)``. The value records what
/// has been changed and nothing else: a tab's sidebar visibility reads
/// `.automatic` until something sets it, and a section's tab order reads `nil`
/// while its tabs keep their declared order.
///
/// ```swift
/// @AppStorage("sidebar") private var customization: TabViewCustomization
///
/// TabView {
///     Tab("Home", systemImage: "house") { HomeView() }
///         .customizationID("com.myApp.home")
///     TabSection("Categories") {
///         Tab("Climate", systemImage: "fan") { ClimateView() }
///             .customizationID("com.myApp.climate")
///     }
///     .customizationID("com.myApp.categories")
/// }
/// .tabViewStyle(.sidebarAdaptable)
/// .tabViewCustomization($customization)
/// ```
///
/// A tab whose sidebar visibility is `.hidden` is left out of the sidebar —
/// not out of a tab strip, which a customization does not change (both as
/// measured on macOS 15.8). A section's tab order, and the order of the
/// sections, are applied to the sidebar when the value holds one; nothing in
/// TUIkit sets either yet — macOS reorders sections by dragging, which a
/// terminal sidebar has no gesture for — so only a decoded value has one.
///
/// It is `Codable`, so it can be persisted as is. The encoding is TUIkit's own,
/// not SwiftUI's, which is private.
public struct TabViewCustomization: Equatable, Sendable, Codable {
    /// Each tab's stated sidebar visibility, by identifier. A tab with no
    /// entry is `.automatic`.
    private var sidebarVisibilities: [String: Visibility] = [:]

    /// Each section's tab order, by the section's identifier, once something
    /// has reordered its tabs.
    private var tabOrders: [String: [String]] = [:]

    /// The order of the identified sections, once something has reordered
    /// them; `nil` while they keep their declared order.
    private var sectionOrder: [String]?

    /// Creates an empty tab view customization: every tab shown as its
    /// content declares, in the declared order.
    public init() {}

    /// The customizations a person has made to a tab section.
    public struct SectionCustomization: Equatable, Sendable {
        /// The order customization for the tabs in a section, identified by
        /// customization identifier, or `nil` while the tabs keep the order of
        /// the builder.
        public fileprivate(set) var tabOrder: [String]?

        /// Resets the order of the tabs in the section back to the default.
        public mutating func resetTabOrder() {
            tabOrder = nil
        }
    }

    /// The customizations a person has made to a tab.
    public struct TabCustomization: Equatable, Sendable {
        /// The visibility of the tab in the sidebar: `.hidden` leaves it out,
        /// and `.automatic` and `.visible` show it.
        public var sidebarVisibility: Visibility
    }

    /// The customizations made to the section with this customization
    /// identifier.
    public subscript(section id: String) -> SectionCustomization {
        get { SectionCustomization(tabOrder: tabOrders[id]) }
        set { tabOrders[id] = newValue.tabOrder }
    }

    /// The customizations made to the tab with this customization identifier.
    ///
    /// Setting `.automatic` forgets what was set before.
    public subscript(tab id: String) -> TabCustomization {
        get { TabCustomization(sidebarVisibility: sidebarVisibilities[id] ?? .automatic) }
        set {
            let visibility = newValue.sidebarVisibility
            sidebarVisibilities[id] = visibility == .automatic ? nil : visibility
        }
    }

    /// Resets the order of the sections back to the order they are declared
    /// in.
    public mutating func resetSectionOrder() {
        sectionOrder = nil
    }

    /// Resets every tab's visibility back to its default.
    public mutating func resetVisibility() {
        sidebarVisibilities = [:]
    }

    // MARK: Applying it

    /// The tabs a sidebar lists, as this customization arranges them: a tab
    /// whose sidebar visibility is `.hidden` left out, each identified
    /// section's tabs in its stated order, and the identified sections in the
    /// stated order, each taking a slot an identified section had.
    func arrangedSidebar(_ tabs: [_RawTab]) -> [_RawTab] {
        let shown = tabs.filter { tab in
            tab.customizationID.map { self[tab: $0].sidebarVisibility != .hidden } ?? true
        }
        // The sidebar's runs: a section's tabs, or the loose tabs between.
        var runs: [[_RawTab]] = []
        for tab in shown {
            if let last = runs.last?.last, last.section?.ordinal == tab.section?.ordinal {
                runs[runs.count - 1].append(tab)
            } else {
                runs.append([tab])
            }
        }
        runs = runs.map { run in
            guard let id = run.first?.section?.customizationID, let order = tabOrders[id] else { return run }
            return Self.arranged(run, by: order, id: \.customizationID)
        }
        if let sectionOrder {
            runs = Self.arranged(runs, by: sectionOrder) { $0.first?.section?.customizationID }
        }
        return runs.flatMap { $0 }
    }

    /// `items` with those `id` ranks in `order` moved, in that order, into the
    /// slots ranked items had; any other item keeps its own slot.
    private static func arranged<Item>(_ items: [Item], by order: [String], id: (Item) -> String?) -> [Item] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }) { first, _ in first }
        func position(_ item: Item) -> Int? { id(item).flatMap { rank[$0] } }
        let slots = items.indices.filter { position(items[$0]) != nil }
        let sorted = slots.map { items[$0] }.sorted { (position($0) ?? 0) < (position($1) ?? 0) }
        var result = items
        for (slot, item) in zip(slots, sorted) {
            result[slot] = item
        }
        return result
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case sidebarVisibility, tabOrder, sectionOrder
    }

    /// Creates a customization by decoding one this type encoded.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stated = try container.decodeIfPresent([String: String].self, forKey: .sidebarVisibility) ?? [:]
        sidebarVisibilities = stated.compactMapValues { name in
            switch name {
            case "visible": .visible
            case "hidden": .hidden
            default: nil
            }
        }
        tabOrders = try container.decodeIfPresent([String: [String]].self, forKey: .tabOrder) ?? [:]
        sectionOrder = try container.decodeIfPresent([String].self, forKey: .sectionOrder)
    }

    /// Encodes this customization: the stated sidebar visibilities by tab
    /// identifier, each reordered section's tab order, and the section order
    /// when one was set.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            sidebarVisibilities.mapValues { $0 == .hidden ? "hidden" : "visible" }, forKey: .sidebarVisibility)
        try container.encode(tabOrders, forKey: .tabOrder)
        try container.encodeIfPresent(sectionOrder, forKey: .sectionOrder)
    }
}

// MARK: - Binding a tab view to one

private struct TabViewCustomizationKey: EnvironmentKey {
    static let defaultValue: TabViewCustomization? = nil
}

extension EnvironmentValues {
    /// The customization a tab view below applies to its sidebar — the value
    /// ``View/tabViewCustomization(_:)`` was bound to as it last drew. The
    /// value, not the binding: nothing in a tab view writes it, and a value
    /// compares, where a binding would turn the render memos off below it.
    var tabViewCustomization: TabViewCustomization? {
        get { self[TabViewCustomizationKey.self] }
        set { self[TabViewCustomizationKey.self] = newValue }
    }
}

extension View {
    /// Specifies the customizations to apply to the sidebar representation of
    /// the tab view.
    ///
    /// Only the ``TabViewStyle/sidebarAdaptable`` style supports
    /// customization: its sidebar leaves out a tab the customization hides
    /// and lists the tabs in any order it states. See
    /// ``TabViewCustomization``.
    ///
    /// - Parameter customization: The customization, or `nil` for none.
    public func tabViewCustomization(_ customization: Binding<TabViewCustomization>?) -> some View {
        environment(\.tabViewCustomization, customization?.wrappedValue)
    }
}

// MARK: - Identifying tabs and sections

extension TabContent {
    /// Sets the identifier for this tab or tab section, by which a
    /// ``TabViewCustomization`` refers to it.
    ///
    /// On a ``TabSection`` it identifies the section; on a ``Tab``, the tab.
    ///
    /// - Parameter id: The customization identifier.
    public func customizationID(_ id: String) -> some TabContent<TabValue> {
        _TabCustomizationIDContent(content: self, id: id)
    }

    /// Sets the default visibility of this tab or tab section in the given
    /// placements.
    ///
    /// Measured on macOS 15.8, hiding a tab for `.tabBar` or `.automatic`
    /// leaves it in both the tab bar and the sidebar, with or without a
    /// customization bound, and TUIkit draws it so too; the placement it acts
    /// on, `.sidebar`, is not one macOS has.
    ///
    /// - Parameters:
    ///   - visibility: The default visibility.
    ///   - placements: The placements it applies to.
    public func defaultVisibility(
        _ visibility: Visibility, for placements: AdaptableTabBarPlacement...
    ) -> some TabContent<TabValue> {
        self
    }

    /// Sets the customization behavior of this tab or tab section in the
    /// given placements.
    ///
    /// macOS has one behavior, ``TabCustomizationBehavior/automatic``, which
    /// is every tab's already.
    ///
    /// - Parameters:
    ///   - behavior: The customization behavior.
    ///   - placements: The placements it applies to.
    public func customizationBehavior(
        _ behavior: TabCustomizationBehavior, for placements: AdaptableTabBarPlacement...
    ) -> some TabContent<TabValue> {
        self
    }
}

/// Tab content with a customization identifier: its section's, when the
/// content is a section, else its tabs'.
struct _TabCustomizationIDContent<Content: TabContent>: TabContent, _TabContentPrimitive {
    typealias TabValue = Content.TabValue

    let content: Content
    let id: String

    var body: _TabCustomizationIDContent<Content> {
        return self  // swiftlint:disable:this implicit_return
    }

    func appendTabs(to tabs: inout _TabList) {
        tabs.identifying(id) { TUIkit.appendTabs(content, to: &$0) }
    }
}

// MARK: - Placements and behaviors

/// A placement for tabs in a tab view using the adaptable sidebar style.
public struct AdaptableTabBarPlacement: Hashable, Sendable {
    /// Which placement this is.
    private let name: String

    /// The default placement.
    public static let automatic = Self(name: "automatic")

    /// The tab bar placement.
    public static let tabBar = Self(name: "tabBar")
}

/// The customization behavior of customizable tab view content.
public struct TabCustomizationBehavior: Equatable, Sendable {
    /// Which behavior this is.
    private let name: String

    /// The default customization behavior.
    public static var automatic: Self { Self(name: "automatic") }
}

// MARK: - Persisting it

extension SceneStorage {
    /// Creates a property that can save and restore tab view customization.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if tab view customization is not
    ///     available for the given key.
    ///   - key: A key used to save and restore the value.
    public init(wrappedValue: Value = TabViewCustomization(), _ key: String) where Value == TabViewCustomization {
        self.init(wrappedValue: wrappedValue, key, store: StorageDefaults.backend)
    }
}

extension AppStorage {
    /// Creates a property that can save and restore tab view customization.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if tab view customization is not
    ///     available for the given key.
    ///   - key: A key used to save and restore the value.
    public init(wrappedValue: Value = TabViewCustomization(), _ key: String) where Value == TabViewCustomization {
        self.init(wrappedValue: wrappedValue, key, store: StorageDefaults.backend)
    }
}
