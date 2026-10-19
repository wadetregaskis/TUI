//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarCustomization.swift
//
//  `toolbar(id:content:)`: a toolbar the person customizes — which of its
//  items are in the bar, and in what order — kept per identifier in the app's
//  storage, as macOS keeps a customized toolbar's configuration.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Public Modifier

extension View {
    /// Populates the toolbar or navigation bar with the specified items,
    /// allowing for user customization — mirrors SwiftUI's
    /// `toolbar(id:content:)`.
    ///
    /// The items join the window's bars as `toolbar(content:)`'s do. Those
    /// made with an identifier — `ToolbarItem(id:)` — the person customizes:
    /// from the bar's context menu (a right-click on the top bar, or Shift+F10
    /// while one of its items has the focus) or the menu bar's View ▸
    /// Customize Toolbar… (`ToolbarCommands`), a panel lists them, where the
    /// person puts each in the bar or takes it out, and moves it among the
    /// others, with the keyboard or the mouse.
    ///
    /// ```swift
    /// BrowserView()
    ///     .toolbar(id: "browserToolbar") {
    ///         ToolbarItem(id: "back", placement: .navigation) { BackButton() }
    ///         ToolbarItem(id: "share") { ShareButton() }
    ///         ToolbarItem(id: "downloads") { DownloadsButton() }
    ///             .defaultCustomization(.hidden)
    ///     }
    /// ```
    ///
    /// What the person chose is kept per `id` in the app's default storage
    /// (the store an `@AppStorage` that names none uses), under
    /// `"TUIkit Toolbar Configuration <id>"`, as macOS keeps a customized
    /// toolbar's configuration under its identifier; an item the app adds
    /// later appears in the bar after the ones the person arranged.
    ///
    /// Each item's ``CustomizableToolbarContent/customizationBehavior(_:)``
    /// says what the person may do with it, and
    /// ``CustomizableToolbarContent/defaultCustomization(_:options:)`` whether
    /// it starts out of the bar and whether, removed, it stays in the bar's
    /// overflow menu (the `»` at the trailing end of the top bar).
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this toolbar.
    ///   - content: The content representing the content of the toolbar.
    /// - Returns: A view that declares the customizable items.
    public func toolbar<Content: CustomizableToolbarContent>(
        id: String, @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        _ToolbarModifier(content: self, items: content(), customizationID: id)
    }
}

// MARK: - What the Person Chose

/// What the person chose about one customizable toolbar, as it is kept in the
/// app's storage. Only what they changed: an item they never put in or took
/// out keeps its default, and an order they never changed is the declared one.
struct _ToolbarCustomizationRecord: Codable, Equatable {
    /// The customizable items' identifiers in the person's order, once they
    /// have moved one; `nil` before.
    var order: [String]?

    /// Each item the person put in the bar (`true`) or took out (`false`).
    var shown: [String: Bool] = [:]

    /// The key the record for the toolbar `id` is kept under.
    static func key(_ id: String) -> String {
        "TUIkit Toolbar Configuration \(id)"
    }

    /// The record kept for the toolbar `id` in `store` — read, so a view that
    /// read it draws again when it changes — or an empty one.
    static func load(_ id: String, from store: any StorageBackend) -> Self {
        store.value(forKey: key(id)) ?? Self()
    }

    /// Keeps this record for the toolbar `id` in `store`, or forgets it when it
    /// says nothing.
    func save(_ id: String, to store: any StorageBackend) {
        if self == Self() {
            store.removeValue(forKey: Self.key(id))
        } else {
            store.setValue(self, forKey: Self.key(id))
        }
    }

    /// `items` in the person's order: each movable customizable item takes a
    /// slot a movable customizable item had, in the order the record gives —
    /// one it does not name after those it does, in the declared order — and
    /// every other item keeps its own.
    func arranged(_ items: [_ToolbarItemSpec]) -> [_ToolbarItemSpec] {
        guard let order else { return items }
        var rank: [String: Int] = [:]
        for (index, id) in order.enumerated() where rank[id] == nil { rank[id] = index }
        let slots = items.indices.filter { items[$0].isMovableCustomization }
        let moved = slots.enumerated()
            .sorted { (rank[items[$0.element].id ?? ""] ?? .max, $0.offset) < (rank[items[$1.element].id ?? ""] ?? .max, $1.offset) }
            .map { items[$0.element] }
        var result = items
        for (slot, item) in zip(slots, moved) { result[slot] = item }
        return result
    }

    /// Whether `item` is in the bar: not while the app hides it; always, for
    /// one the person may not remove; else as the person chose, or as it
    /// starts.
    func isShown(_ item: _ToolbarItemSpec) -> Bool {
        !item.customization.isHiddenByApp && isChosen(item)
    }

    /// Whether the person has `item` in the bar, the app aside: always, for
    /// one they may not remove; else as they chose, or as it starts.
    func isChosen(_ item: _ToolbarItemSpec) -> Bool {
        guard let id = item.id, item.isRemovableCustomization else { return true }
        return shown[id] ?? !item.customization.startsHidden
    }
}

extension _ToolbarItemSpec {
    /// Whether the person may take the item out of a customizable toolbar.
    var isRemovableCustomization: Bool {
        id != nil && customization.behavior == .default
    }

    /// Whether the person may move the item in a customizable toolbar.
    var isMovableCustomization: Bool {
        id != nil && customization.behavior != .disabled
    }
}

// MARK: - Applying It

extension _ToolbarModifier {
    /// The items this declaration puts in the bars: in a customizable toolbar,
    /// those in the bar as the person arranged them, and the overflow menu of
    /// the always-available ones they removed; elsewhere every item the app
    /// does not hide.
    func shownItems(context: RenderContext) -> [_ToolbarItemSpec] {
        let declared = toolbarItems(of: items)
        guard let customizationID else { return declared.filter { !$0.customization.isHiddenByApp } }
        let store = context.environment.defaultAppStorage?.store ?? StorageDefaults.backend
        let record = _ToolbarCustomizationRecord.load(customizationID, from: store)
        let arranged = record.arranged(declared)
        var shown = arranged.filter { record.isShown($0) }
        let overflow = arranged.filter {
            !record.isShown($0) && !$0.customization.isHiddenByApp && $0.customization.isAlwaysAvailable
        }
        if !overflow.isEmpty { shown.append(Self.overflowItem(overflow)) }
        return shown
    }

    /// The overflow menu: a pull-down at the top bar's trailing end of the
    /// always-available items the person removed, which stay usable there.
    private static func overflowItem(_ items: [_ToolbarItemSpec]) -> _ToolbarItemSpec {
        let views = items.map(\.view)
        return _ToolbarItemSpec(
            placement: .primaryAction,
            view: AnyView(
                _ToolbarPullDown(
                    label: Text(verbatim: "»"),
                    items: ForEach(views.indices, id: \.self) { views[$0] })),
            id: "tuikit.overflow", path: [])
    }

    /// Records this customizable toolbar in the window's chrome, for its panel
    /// and the menu bar's Customize Toolbar…: its customizable items in the
    /// person's order, whether each is in the bar, and the ways to change it.
    func declareCustomizable(into chrome: WindowChromeState, context: RenderContext) {
        guard let customizationID else { return }
        let store = context.environment.defaultAppStorage?.store ?? StorageDefaults.backend
        let record = _ToolbarCustomizationRecord.load(customizationID, from: store)
        let arranged = record.arranged(toolbarItems(of: items)).filter { $0.id != nil && !$0.isTitleMenu }
        let ids = arranged.compactMap(\.id)
        let movable = arranged.filter(\.isMovableCustomization).compactMap(\.id)
        let items = arranged.map { item in
            CustomizableToolbarDeclaration.Item(
                id: item.id ?? "", view: item.view, isRemovable: item.isRemovableCustomization,
                isMovable: item.isMovableCustomization, isShown: record.isChosen(item),
                isHiddenByApp: item.customization.isHiddenByApp)
        }
        chrome.declare(
            CustomizableToolbarDeclaration(
                id: customizationID, items: items, environment: context.environment,
                setShown: { id, isShown in
                    var record = _ToolbarCustomizationRecord.load(customizationID, from: store)
                    record.shown[id] = isShown
                    record.save(customizationID, to: store)
                },
                move: { id, offset in
                    guard let at = movable.firstIndex(of: id) else { return }
                    let to = at + offset
                    guard movable.indices.contains(to) else { return }
                    var order = movable
                    order.swapAt(at, to)
                    var record = _ToolbarCustomizationRecord.load(customizationID, from: store)
                    // The whole order, the immovable ones where they are.
                    var moved = order.makeIterator()
                    record.order = ids.map { movable.contains($0) ? moved.next() ?? $0 : $0 }
                    record.save(customizationID, to: store)
                },
                reset: { _ToolbarCustomizationRecord().save(customizationID, to: store) }))
    }
}
