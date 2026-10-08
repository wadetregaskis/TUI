//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowSeparatorGuides.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The line

/// One separator line as a row draws it: the rule's ink and where it starts
/// and stops across the row's content (decisions A47).
package struct ListRowSeparatorLine: Equatable {
    /// The ink, or `nil` for the list's own — the border's, as a `Divider`'s.
    package var tint: Color?
    /// Cells of the row's content before the rule starts: the row's own
    /// ``HorizontalAlignment/listRowSeparatorLeading``, else 0 — the
    /// content's leading edge, as a macOS list insets its hairline to it.
    package var leading = 0
    /// Where the rule stops, in cells from the content's leading edge: the
    /// row's own ``HorizontalAlignment/listRowSeparatorTrailing``, else `nil`
    /// — the row's trailing edge.
    package var trailing: Int?

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitLists makes these, for its lists.
    package init(tint: Color? = nil, leading: Int = 0, trailing: Int? = nil) {
        self.tint = tint
        self.leading = leading
        self.trailing = trailing
    }

    /// The rule drawn `width` cells wide (the row's content width).
    package func drawn(width: Int, palette: any Palette) -> String {
        let start = max(0, min(leading, width))
        let end = max(start, min(trailing ?? width, width))
        let ink = (tint ?? palette.border).resolve(with: palette).opaqueSpelling
        return String(repeating: " ", count: start)
            + ANSIRenderer.colorize(String(repeating: "─", count: end - start), foreground: ink)
            + String(repeating: " ", count: width - end)
    }
}

// MARK: - Alignment guides

private enum ListRowSeparatorLeadingID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

private enum ListRowSeparatorTrailingID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { Double(context.width) }
}

extension HorizontalAlignment {
    /// A guide marking the leading edge of a `List` row separator.
    ///
    /// Use this guide to align the leading end of the bottom `List` row
    /// separator with any other horizontal guide of a view that is part of
    /// the cell content. The rule starts where the row's content puts it — set
    /// on the row's view, or carried up by a stack from one of its children,
    /// as any explicit guide is — and at the content's leading edge where
    /// nothing sets it.
    ///
    /// ```swift
    /// List {
    ///     ForEach(favoriteFoods) { food in
    ///         HStack {
    ///             Text(food.emoji)
    ///             Text(food.name)
    ///                 .alignmentGuide(.listRowSeparatorLeading) {
    ///                     $0[.leading]
    ///                 }
    ///         }
    ///     }
    /// }
    /// ```
    public static let listRowSeparatorLeading = Self(ListRowSeparatorLeadingID.self)

    /// A guide marking the trailing edge of a `List` row separator.
    ///
    /// Use this guide to align the trailing end of the bottom `List` row
    /// separator with any other horizontal guide of a view that is part of
    /// the cell content. The rule stops at the row's trailing edge where
    /// nothing sets it.
    public static let listRowSeparatorTrailing = Self(ListRowSeparatorTrailingID.self)
}

// MARK: - Reading a row's guides

/// The separator a row of `view`, laid out at `size` in `context`, draws with
/// its own guides — `nil` where the view sets neither, which every view whose
/// type cannot hold a guide answers without being asked.
@MainActor
func listRowSeparatorGuides<V: View>(of view: V, size: (width: Int, height: Int), context: RenderContext) -> (
    leading: Int?, trailing: Int?
)? {
    guard V._providesAlignmentGuide else { return nil }
    var measuring = context
    measuring.isMeasuring = true
    let dimensions = ViewDimensions(width: size.width, height: size.height)
    let leading = explicitGuide(of: view, .horizontal(.listRowSeparatorLeading), in: dimensions, context: measuring)
    let trailing = explicitGuide(of: view, .horizontal(.listRowSeparatorTrailing), in: dimensions, context: measuring)
    guard leading != nil || trailing != nil else { return nil }
    return (leading.map { Int($0.rounded()) }, trailing.map { Int($0.rounded()) })
}

/// Reports the separator guides `child` sets, laid out at `size` in its
/// container's `context`, against list row `row` — nothing where it sets none,
/// which a child whose type cannot hold a guide answers with one stored flag.
@MainActor
package func reportSeparatorGuides(of child: ChildView, size: (width: Int, height: Int), row: Int, context: RenderContext) {
    guard child.providesAlignmentGuide, !context.isMeasuring,
        let reports = context.environment.listRowEditRestrictions
    else { return }
    let dimensions = ViewDimensions(width: size.width, height: size.height)
    let leading = child.explicitGuide(.horizontal(.listRowSeparatorLeading), at: dimensions, context: context)
    let trailing = child.explicitGuide(.horizontal(.listRowSeparatorTrailing), at: dimensions, context: context)
    guard leading != nil || trailing != nil else { return }
    reports.reportSeparatorGuides(row: row, (leading.map { Int($0.rounded()) }, trailing.map { Int($0.rounded()) }))
}
