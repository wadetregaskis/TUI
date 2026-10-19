//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackReportedRowID.swift
//
//  The id a scroll view reports for one child of the stack that is its
//  content: what `.scrollPosition(id:)` is handed back for the row it shows,
//  and what `onScrollTargetVisibilityChange` lists for the rows it shows.
//
//  Created by Wade Tregaskis
//  License: MIT

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
        if let id = anyID(at: ordinal) { return id }
        guard let children = eagerChildViews, children.indices.contains(ordinal) else { return nil }
        if children[ordinal].identityChildKey != nil,
            let id = FlattenedRowIDs<AnyHashable>(content: content, children: children, sectionsWhole: sectionsWhole)
                .elementID(ofChildAt: ordinal)
        {
            return id
        }
        return children[ordinal].explicitID
    }
}
