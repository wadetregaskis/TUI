//  🖥️ TUI — A Terminal UI framework for Swift
//  StackReportedRowID.swift
//
//  The id a scroll view reports for one child of the stack that is its
//  content: what `.scrollPosition(id:)` is handed back for the row it shows,
//  and what `onScrollTargetVisibilityChange` lists for the rows it shows.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The ids of a stack's children, asked one at a time — see
/// ``ChildViewCollection/reportedID(at:content:sectionsWhole:)`` for what each
/// is. A class so that the placement of the looped rows on their loops,
/// made on the first question about a looped row, serves every later one.
@MainActor
final class StackRowIDs {
    private let collection: ChildViewCollection
    private let content: any View
    private let sectionsWhole: Bool
    private var flattened: FlattenedRowIDs<AnyHashable>?

    /// The ids of `collection`, which was resolved from `content` — keeping
    /// each `Section` whole when `sectionsWhole`.
    init<Content: View>(_ collection: ChildViewCollection, content: Content, sectionsWhole: Bool) {
        self.collection = collection
        self.content = content
        self.sectionsWhole = sectionsWhole
    }

    /// The id of the child at `ordinal`, or `nil`.
    func id(at ordinal: Int) -> AnyHashable? {
        if let id = collection.anyID(at: ordinal) { return id }
        guard let children = collection.eagerChildViews, children.indices.contains(ordinal) else { return nil }
        if children[ordinal].identityChildKey != nil {
            let rows = flattened ?? Self.placing(content, children: children, sectionsWhole: sectionsWhole)
            flattened = rows
            if let id = rows.elementID(ofChildAt: ordinal) { return id }
        }
        return children[ordinal].explicitID
    }

    private static func placing<Content: View>(
        _ content: Content, children: [ChildView], sectionsWhole: Bool
    ) -> FlattenedRowIDs<AnyHashable> {
        FlattenedRowIDs(content: content, children: children, sectionsWhole: sectionsWhole)
    }
}

extension ChildViewCollection {
    /// The id of the child at `ordinal` of a stack whose content is `content`
    /// — its element's `id` for a `ForEach`'s row, its `.id(_:)` tag for a
    /// child of the stack's own — or `nil` for a child with neither.
    ///
    /// Per child, as a seek is (`ChildView.matchesSeekKey(_:)`), not per
    /// collection: a lone `ForEach` answers from its data without building a
    /// row (``anyID(at:)``), and any other content — two `ForEach`es, a
    /// heading above one, a stack of tagged views — is an eager array, whose
    /// looped rows are placed on their loops by position (`FlattenedRowIDs`,
    /// as a `List` places them for its selection) and whose other children
    /// answer by their tag. Before, only the lone `ForEach` answered, and a
    /// stack of anything else reported no row at all.
    ///
    /// - Parameters:
    ///   - ordinal: The child's index in this collection.
    ///   - content: The content the collection was resolved from.
    ///   - sectionsWhole: Whether that walk kept each `Section` whole.
    /// - Returns: The id, or `nil`.
    @MainActor
    func reportedID<Content: View>(at ordinal: Int, content: Content, sectionsWhole: Bool) -> AnyHashable? {
        StackRowIDs(self, content: content, sectionsWhole: sectionsWhole).id(at: ordinal)
    }
}
