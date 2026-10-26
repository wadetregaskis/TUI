//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowSeparatorGuides.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - The line

/// One separator line as a row draws it: the rule's ink, where it starts and
/// stops across the row's content (decisions A47), and whether it is a rule
/// of its own or a hairline (A-D6L-2).
///
/// `@usableFromInline`, with its fields (the module split's tier 2): TUILists
/// makes one for every row that draws a separator, and an `@inlinable` member of
/// a type that is only `package` is not serialized for another module to
/// inline, whatever it says. `Sendable` stated, as it was inferred while the
/// type was not usable from inline code: the compiler infers it only for types
/// that are not.
@usableFromInline
package struct ListRowSeparatorLine: Equatable, Sendable {
    /// The ink, or `nil` for the list's own — the border's, as a `Divider`'s.
    @usableFromInline package var tint: Color?
    /// Cells of the row's content before the rule starts: the row's own
    /// ``HorizontalAlignment/listRowSeparatorLeading``, else 0 — the
    /// content's leading edge, as a macOS list insets its hairline to it.
    @usableFromInline package var leading = 0
    /// Where the rule stops, in cells from the content's leading edge: the
    /// row's own ``HorizontalAlignment/listRowSeparatorTrailing``, else `nil`
    /// — the row's trailing edge.
    @usableFromInline package var trailing: Int?
    /// Whether it is drawn as a hairline along the top of the row below
    /// (`ListSeparatorStyle.hairline`), which takes no row, rather than as a
    /// rule on a line of its own below the row (``takesRow``).
    @usableFromInline package var isHairline: Bool

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUILists makes these, for its lists.
    @inlinable
    package init(tint: Color? = nil, leading: Int = 0, trailing: Int? = nil, isHairline: Bool = false) {
        self.tint = tint
        self.leading = leading
        self.trailing = trailing
        self.isHairline = isHairline
    }

    /// Whether the row this separates draws it on a line of its own below
    /// itself: the rule does, the hairline does not.
    @inlinable
    package var takesRow: Bool { !isHairline }

    /// The cells of a content `width` cells wide the separator runs across.
    private func columns(width: Int) -> Range<Int> {
        let start = max(0, min(leading, width))
        return start..<max(start, min(trailing ?? width, width))
    }

    /// The rule drawn `width` cells wide (the row's content width).
    package func drawn(width: Int, palette: any Palette) -> String {
        let columns = columns(width: width)
        let ink = (tint ?? palette.border).resolve(with: palette).opaqueSpelling
        return String.spaces(columns.lowerBound)
            + ANSIRenderer.colorize(String(repeating: "─", count: columns.count), foreground: ink)
            + String.spaces(width - columns.upperBound)
    }

    /// `line` — the row below's first line — marked for the hairline along its
    /// top (``HairlineMarker``): across the same cells the rule would run
    /// across, `offset` cells into the line, where the row's content starts.
    ///
    /// Unmarked where the ink has no RGB to draw a strip in: a palette slot
    /// the terminal never reported, which a blend cannot use either.
    package func markingHairline(on line: String, offset: Int, width: Int, palette: any Palette) -> String {
        let columns = columns(width: width)
        guard !columns.isEmpty,
            let rgb = (tint ?? palette.border).resolve(with: palette).opaqueSpelling.rgbComponents
        else { return line }
        return HairlineMarker.marking(
            line, columns: (offset + columns.lowerBound)..<(offset + columns.upperBound),
            red: rgb.red, green: rgb.green, blue: rgb.blue)
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
