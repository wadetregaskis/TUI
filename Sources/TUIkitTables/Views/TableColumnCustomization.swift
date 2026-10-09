//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnCustomization.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - TableColumnCustomization

/// A representation of the state of the columns in a table.
///
/// Bind a table to one with a `columnCustomization:` initializer, and give the
/// columns that may be customized a ``TableColumnContent/customizationID(_:)``.
/// The value records what has been changed and nothing else: a column's
/// visibility reads `.automatic` until something sets it, and then the
/// column follows what was set rather than its
/// ``TableColumnContent/defaultVisibility(_:)``.
///
/// ```swift
/// @State private var columnCustomization = TableColumnCustomization<BugReport>()
///
/// Table(reports, columnCustomization: $columnCustomization) {
///     TableColumn("Title", value: \.title)
///         .customizationID("title")
///     TableColumn("Reporter", value: \.reporter)
///         .customizationID("reporter")
///         .defaultVisibility(.hidden)
/// }
/// ```
///
/// It is `Codable`, so it can be persisted as is. The encoding is TUIkit's own
/// — a column's stated visibility and width by identifier, and an order when
/// one has been set — not SwiftUI's, which is private.
///
/// The user changes it as they would a SwiftUI table's: a right-click (or
/// Ctrl-click) on the header opens a menu that hides or shows a column;
/// dragging a header moves its column; dragging the gap after a column's
/// header resizes it, within its bounds — and the width it is given is kept
/// here, as SwiftUI keeps it. From the keyboard, **Ctrl-K** on the focused
/// table picks a column (←/→ choose another): `<` and `>` move it, `-` and
/// `+` resize it, Return opens the menu on it, Escape lets it go. Only a
/// column with a ``TableColumnContent/customizationID(_:)`` takes part, and
/// a column's ``TableColumnContent/disabledCustomizationBehavior(_:)`` takes
/// away the gestures it names.
public struct TableColumnCustomization<RowValue: Identifiable>: Equatable, Sendable, Codable {
    /// Each customizable column's stated visibility, by identifier. A column
    /// with no entry is `.automatic`.
    private var visibilities: [String: Visibility] = [:]

    /// The order of the customizable columns, by identifier, once something
    /// has reordered them; `nil` while they keep their declared order.
    private var order: [String]?

    /// Each resized column's width, in cells, by identifier. A column with no
    /// entry is as wide as its declaration makes it.
    private var widths: [String: Int] = [:]

    /// Creates an empty table column customization.
    ///
    /// An empty customization changes no column: each is visible or hidden as
    /// its `defaultVisibility(_:)` says, in the order it was declared.
    public init() {}

    /// The visibility of the column identified by its identifier.
    ///
    /// Explicit identifiers can be associated with a column using
    /// ``TableColumnContent/customizationID(_:)``.
    ///
    /// Reads `.automatic` for a column nothing has set, whatever its default
    /// visibility. Setting `.automatic` forgets what was set before.
    public subscript(visibility id: String) -> Visibility {
        get { visibilities[id] ?? .automatic }
        set { visibilities[id] = newValue == .automatic ? nil : newValue }
    }

    /// Resets the column order back to the default, preserving the
    /// customized visibility.
    public mutating func resetOrder() {
        order = nil
    }

    // MARK: What the gestures change

    /// The width the column identified by `id` was resized to, in cells, or
    /// `nil` when it keeps its declared width. Setting `nil` forgets it.
    ///
    /// Not public: SwiftUI's customization keeps a resized width too, and says
    /// nothing about it in its API — it travels in the encoding.
    subscript(width id: String) -> Int? {
        get { widths[id] }
        set { widths[id] = newValue.map { max(1, $0) } }
    }

    /// Moves the column identified by `id` to the place `target` holds, the
    /// columns between them shifting one place toward where it came from —
    /// what dropping a dragged header on another does.
    ///
    /// - Parameter declared: The identifiers of the table's customizable
    ///   columns, in declaration order: what an order is laid over.
    mutating func move(_ id: String, toPlaceOf target: String, declared: [String]) {
        var current = currentOrder(declared: declared)
        guard id != target, let from = current.firstIndex(of: id),
            let to = current.firstIndex(of: target)
        else { return }
        current.remove(at: from)
        current.insert(id, at: to)
        order = current
    }

    /// The customizable columns' order as it stands: the stated order, with
    /// any declared column it does not name after it in declaration order,
    /// and any it names that is no longer declared left out.
    func currentOrder(declared: [String]) -> [String] {
        guard let order else { return declared }
        let known = Set(declared)
        var seen = Set<String>()
        var result = order.filter { known.contains($0) && seen.insert($0).inserted }
        result += declared.filter { !seen.contains($0) }
        return result
    }

    // MARK: Applying it

    /// The columns of a table bound to this customization that are shown, in
    /// the order they are shown.
    ///
    /// A column is shown when its stated visibility is `.visible`, or when
    /// nothing was stated and its default visibility is not `.hidden` — and
    /// a column with no identifier has nothing to be stated about it.
    func shownColumns(_ columns: [_TableColumnSpec<RowValue>]) -> [_TableColumnSpec<RowValue>] {
        var shown = columns.filter { column in
            let stated = column.customizationID.map { self[visibility: $0] } ?? .automatic
            return Self.isShown(stated: stated, default: column.defaultVisibility)
        }
        if !widths.isEmpty {
            for index in shown.indices {
                if let id = shown[index].customizationID, let width = widths[id] {
                    shown[index].resizedWidth = width
                }
            }
        }
        guard let order else { return shown }
        // The customizable columns take the slots customizable columns had,
        // in the stated order; any other column keeps its own slot.
        let rank = Dictionary(order.enumerated().map { ($1, $0) }) { first, _ in first }
        let slots = shown.indices.filter { shown[$0].customizationID.flatMap { rank[$0] } != nil }
        func position(_ column: _TableColumnSpec<RowValue>) -> Int {
            column.customizationID.flatMap { rank[$0] } ?? 0
        }
        let arranged = slots.map { shown[$0] }.sorted { position($0) < position($1) }
        for (slot, column) in zip(slots, arranged) {
            shown[slot] = column
        }
        return shown
    }

    /// Whether a column is shown, from what was stated and its default.
    static func isShown(stated: Visibility, default defaultVisibility: Visibility?) -> Bool {
        switch stated {
        case .visible: true
        case .hidden: false
        case .automatic: defaultVisibility != .hidden
        }
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case visibility, order, width
    }

    /// Creates a customization by decoding one this type encoded.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stated = try container.decodeIfPresent([String: String].self, forKey: .visibility) ?? [:]
        visibilities = stated.compactMapValues(VisibilityCoding.visibility(named:))
        order = try container.decodeIfPresent([String].self, forKey: .order)
        widths = (try container.decodeIfPresent([String: Int].self, forKey: .width) ?? [:])
            .filter { $0.value > 0 }
    }

    /// Encodes this customization: the stated visibilities by identifier, the
    /// order when one was set, and the widths columns were resized to, when any
    /// were.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visibilities.mapValues(VisibilityCoding.name(of:)), forKey: .visibility)
        try container.encodeIfPresent(order, forKey: .order)
        if !widths.isEmpty { try container.encode(widths, forKey: .width) }
    }
}

/// How a column's stated visibility is spelled in a customization's encoding.
private enum VisibilityCoding {
    static func name(of visibility: Visibility) -> String {
        switch visibility {
        case .automatic: "automatic"
        case .visible: "visible"
        case .hidden: "hidden"
        }
    }

    static func visibility(named name: String) -> Visibility? {
        switch name {
        case "visible": .visible
        case "hidden": .hidden
        default: nil
        }
    }
}

// MARK: - TableColumnCustomizationBehavior

/// A set of customization behaviors of a column that a user can perform.
///
/// ``TableColumnContent/disabledCustomizationBehavior(_:)`` takes one: the
/// behaviors a user may not perform on that column. It never stops the app
/// changing a ``TableColumnCustomization`` itself.
public struct TableColumnCustomizationBehavior: SetAlgebra, Sendable {
    public typealias Element = Self
    public typealias ArrayLiteralElement = Self

    /// The behaviors, one bit each: reorder, resize, visibility.
    private var bits: UInt8

    private init(bits: UInt8) {
        self.bits = bits & 0b111
    }

    /// Creates an empty set of behaviors.
    public init() {
        bits = 0
    }

    /// All customization behaviors.
    public static var all: Self { Self(bits: 0b111) }

    /// The ability to reorder a column.
    public static let reorder = Self(bits: 0b001)

    /// The ability to resize a column.
    public static let resize = Self(bits: 0b010)

    /// The ability to change the visibility of a column.
    public static let visibility = Self(bits: 0b100)

    public func contains(_ member: Self) -> Bool {
        bits & member.bits == member.bits
    }

    public func union(_ other: Self) -> Self {
        Self(bits: bits | other.bits)
    }

    public func intersection(_ other: Self) -> Self {
        Self(bits: bits & other.bits)
    }

    public func symmetricDifference(_ other: Self) -> Self {
        Self(bits: bits ^ other.bits)
    }

    @discardableResult
    public mutating func insert(_ newMember: Self) -> (inserted: Bool, memberAfterInsert: Self) {
        let inserted = !contains(newMember)
        bits |= newMember.bits
        return (inserted, newMember)
    }

    @discardableResult
    public mutating func remove(_ member: Self) -> Self? {
        let present = intersection(member)
        bits &= ~member.bits
        return present.isEmpty ? nil : present
    }

    @discardableResult
    public mutating func update(with newMember: Self) -> Self? {
        let present = intersection(newMember)
        bits |= newMember.bits
        return present.isEmpty ? nil : present
    }

    public mutating func formUnion(_ other: Self) {
        bits |= other.bits
    }

    public mutating func formIntersection(_ other: Self) {
        bits &= other.bits
    }

    public mutating func formSymmetricDifference(_ other: Self) {
        bits ^= other.bits
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bits == rhs.bits
    }
}

// MARK: - Persisting it

extension SceneStorage {
    /// Creates a property that can save and restore table column state.
    ///
    /// Table column state is typically not bound from a table directly to
    /// `SceneStorage`, but instead indirecting through `State` to prevent
    /// redundant encode and decodes when writing to it.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if table column state is not
    ///     available for the given key.
    ///   - key: A key used to save and restore the value.
    public init<RowValue>(
        wrappedValue: Value = TableColumnCustomization<RowValue>(), _ key: String
    ) where Value == TableColumnCustomization<RowValue> {
        self.init(wrappedValue: wrappedValue, key, store: StorageDefaults.backend)
    }
}

extension AppStorage {
    /// Creates a property that can save and restore table column state.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if table column state is not
    ///     available for the given key.
    ///   - key: A key used to save and restore the value.
    public init<RowValue>(
        wrappedValue: Value = TableColumnCustomization<RowValue>(), _ key: String
    ) where Value == TableColumnCustomization<RowValue> {
        self.init(wrappedValue: wrappedValue, key, store: StorageDefaults.backend)
    }
}
