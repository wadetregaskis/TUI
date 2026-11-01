//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarCustomization.swift
//
//  `toolbar(id:content:)`: a toolbar the person customizes — which of its
//  items are in the bar, and in what order — kept per identifier in the app's
//  storage, as macOS keeps a customized toolbar's configuration.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

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
    /// Customize Toolbar… (F10, then View: offered whether or not the scene's
    /// commands include `ToolbarCommands`, which macOS needs for it; a scene
    /// with no `commands` has no menu bar), a panel lists them, where the
    /// person puts each in the bar or takes it out, and moves it among the
    /// others in its place — its region of its bar's row — with the keyboard
    /// or the mouse. While the panel is open, the items in the bar are dragged
    /// rather than used, as on macOS: sideways to move one, off the bar to
    /// take it out.
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
    /// `"TUI Toolbar Configuration <id>"`, as macOS keeps a customized
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
    nonisolated public func toolbar<Content: CustomizableToolbarContent>(
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
        "TUI Toolbar Configuration \(id)"
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

    /// Where the bars draw the item, as far as its order goes: its bar, and
    /// the region of the bar's row it is in. A bar lays out each region's
    /// items in their order, one region after another, so the person moves an
    /// item among those of its own place: moved past an item in another, it
    /// would stay where it was in the bar.
    var customizationPlace: _ToolbarCustomizationPlace {
        _ToolbarCustomizationPlace(
            bar: placement.bar, accessoryBar: placement.accessoryBar, region: placement.region)
    }
}

/// A place in the bars a customizable toolbar's items are moved within: a
/// region of one bar's row (``_ToolbarItemSpec/customizationPlace``).
struct _ToolbarCustomizationPlace: Hashable {
    let bar: WindowChromeState.Edge
    let accessoryBar: AccessoryBarID?
    let region: ToolbarItemPlacement.Region

    /// Where the place comes in the bars: the top bar's own row, then its
    /// accessory bars, then the bottom bar — each row's regions in the order
    /// it lays them out.
    var rank: (bar: Int, region: Int) {
        let bar = self.bar == .bottom ? 2 : accessoryBar == nil ? 0 : 1
        let region: Int
        switch self.region {
        case .leading: region = 0
        case .principal: region = 1
        case .secondary: region = 2
        case .trailing: region = 3
        }
        return (bar, region)
    }

    /// `items` in the order the bars draw them, place by place (``rank``) —
    /// the accessory bars in the order their first items come — and each
    /// place's items in their order.
    static func inBarOrder(_ items: [_ToolbarItemSpec]) -> [_ToolbarItemSpec] {
        var firstOfBar: [AccessoryBarID: Int] = [:]
        for (index, item) in items.enumerated() {
            if let bar = item.placement.accessoryBar, firstOfBar[bar] == nil { firstOfBar[bar] = index }
        }
        func key(_ offset: Int) -> [Int] {
            let place = items[offset].customizationPlace
            let rank = place.rank
            return [rank.bar, place.accessoryBar.flatMap { firstOfBar[$0] } ?? 0, rank.region, offset]
        }
        return items.indices.sorted { key($0).lexicographicallyPrecedes(key($1)) }.map { items[$0] }
    }
}

// MARK: - Applying It

@MainActor extension _ToolbarModifier {
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

    /// The customizable items as `record` arranges them: their identifiers
    /// in the record's order, the items in the order the bars draw them, and
    /// each movable item's neighbours, the movable items before and after it
    /// in its own place.
    private static func arrangement(
        of declared: [_ToolbarItemSpec], by record: _ToolbarCustomizationRecord
    ) -> (ids: [String], listed: [_ToolbarItemSpec], neighbours: [String: (earlier: String?, later: String?)]) {
        let arranged = record.arranged(declared).filter { $0.id != nil && !$0.isTitleMenu }
        // The record's order is the arranged one; the panel's, the bars'.
        let listed = _ToolbarCustomizationPlace.inBarOrder(arranged)
        var neighbours: [String: (earlier: String?, later: String?)] = [:]
        for place in Set(listed.map(\.customizationPlace)) {
            let movable = listed.filter { $0.isMovableCustomization && $0.customizationPlace == place }.compactMap(\.id)
            for (index, id) in movable.enumerated() {
                neighbours[id] = (
                    index > 0 ? movable[index - 1] : nil, index + 1 < movable.count ? movable[index + 1] : nil
                )
            }
        }
        return (arranged.compactMap(\.id), listed, neighbours)
    }

    /// Records this customizable toolbar in the window's chrome, for its panel
    /// and the menu bar's Customize Toolbar…: its customizable items in the
    /// order the bars draw them, whether each is in the bar, and the ways to
    /// change it.
    func declareCustomizable(into chrome: WindowChromeState, context: RenderContext) {
        guard let customizationID else { return }
        let store = context.environment.defaultAppStorage?.store ?? StorageDefaults.backend
        let record = _ToolbarCustomizationRecord.load(customizationID, from: store)
        let declared = toolbarItems(of: items)
        let (_, listed, neighbours) = Self.arrangement(of: declared, by: record)
        let items = listed.map { item in
            let id = item.id ?? ""
            return CustomizableToolbarDeclaration.Item(
                id: id, view: item.view, isRemovable: item.isRemovableCustomization,
                canMoveEarlier: neighbours[id]?.earlier != nil, canMoveLater: neighbours[id]?.later != nil,
                isShown: record.isChosen(item), isHiddenByApp: item.customization.isHiddenByApp)
        }
        // From the order stored NOW, not this frame's: a drag moves an item a
        // place at a time through closures kept from the frame it began in,
        // and a second move worked out from that frame's order swapped the
        // first one back.
        func stored() -> (ids: [String], neighbours: [String: (earlier: String?, later: String?)]) {
            let (ids, _, neighbours) = Self.arrangement(
                of: declared, by: _ToolbarCustomizationRecord.load(customizationID, from: store))
            return (ids, neighbours)
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
                    let (ids, neighbours) = stored()
                    guard let other = offset < 0 ? neighbours[id]?.earlier : neighbours[id]?.later,
                        let at = ids.firstIndex(of: id), let to = ids.firstIndex(of: other)
                    else { return }
                    // The whole order, with the two items of one place swapped:
                    // every other item, of that place or another, stays put.
                    var order = ids
                    order.swapAt(at, to)
                    var record = _ToolbarCustomizationRecord.load(customizationID, from: store)
                    record.order = order
                    record.save(customizationID, to: store)
                },
                neighbour: { id, offset in
                    let neighbours = stored().neighbours[id]
                    return offset < 0 ? neighbours?.earlier : neighbours?.later
                },
                reset: { _ToolbarCustomizationRecord().save(customizationID, to: store) }))
    }
}
