//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListSeparators.swift
//
//  A list's separators: a rule line between rows (decisions A47).
//  `listRowSeparatorTint(_:edges:)`, `listSectionSeparator(_:edges:)`,
//  `listSectionSeparatorTint(_:edges:)` and the two separator alignment
//  guides; `listRowSeparator(_:edges:)` is in `ListRowSeparatorModifier.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Preference

/// What a row, a section or a list says about its separators: a visibility
/// and a tint for each vertical edge (decisions A47).
///
/// A list row is whole lines of cells, so a separator is a whole line: a
/// faint `─` rule BETWEEN two rows, in the border's ink unless tinted. Which
/// line answers to whom:
///
/// - Between two rows: the upper row's bottom edge (its
///   ``View/listRowSeparator(_:edges:)``). A row's TOP edge is the style's to
///   decline, as SwiftUI documents a style may ("typically the top edge"):
///   the line above a row is the one below the row before it, and two rules
///   in a row would be a gap.
/// - Below a section's header: the section's top edge
///   (``View/listSectionSeparator(_:edges:)``).
/// - Below a section's last row: the section's bottom edge.
/// - Below the list's last row: never — a list's edges are its border's, or
///   the page's.
///
/// `.automatic` is the style's answer, and no built-in style draws separators
/// by default yet: each costs a line of height, which a list of single-line
/// rows doubles (decisions A47; the default is A-D6L-2's open question).
struct ListSeparatorPreference: Equatable, Sendable {
    /// Whether the line above shows.
    var top: Visibility = .automatic
    /// Whether the line below shows.
    var bottom: Visibility = .automatic
    /// The line above's ink, or `nil` for the style's.
    var topTint: Color?
    /// The line below's ink, or `nil` for the style's.
    var bottomTint: Color?

    /// `self`, with whatever `other` states — a visibility other than
    /// `.automatic`, a tint — written over it: a row's own preference over the
    /// list-wide one.
    func overridden(by other: Self) -> Self {
        var merged = self
        if other.top != .automatic { merged.top = other.top }
        if other.bottom != .automatic { merged.bottom = other.bottom }
        if let tint = other.topTint { merged.topTint = tint }
        if let tint = other.bottomTint { merged.bottomTint = tint }
        return merged
    }
}

/// One separator modifier's statement, carried as data so the views holding
/// it compare as values.
enum ListSeparatorChange: Equatable, Sendable {
    /// `.listRowSeparator(_:edges:)` / `.listSectionSeparator(_:edges:)`.
    case visibility(Visibility, VerticalEdge.Set)
    /// `.listRowSeparatorTint(_:edges:)` / `.listSectionSeparatorTint(_:edges:)`.
    case tint(Color?, VerticalEdge.Set)

    /// `preference` with this statement applied.
    func apply(to preference: inout ListSeparatorPreference) {
        switch self {
        case .visibility(let visibility, let edges):
            if edges.contains(.top) { preference.top = visibility }
            if edges.contains(.bottom) { preference.bottom = visibility }
        case .tint(let tint, let edges):
            if edges.contains(.top) { preference.topTint = tint }
            if edges.contains(.bottom) { preference.bottomTint = tint }
        }
    }
}

/// The separator preferences written OUTSIDE any list row — on a `List`, or
/// anything above one — which every list below takes as its rows' and its
/// sections' defaults.
///
/// SwiftUI documents the modifiers as a row's or a section's preference; on
/// the list itself (unmeasured there) they mean every row's or every
/// section's here, the way TUIkit's other row modifiers flow down.
struct ListSeparatorDefaults: Equatable, Sendable {
    var rows = ListSeparatorPreference()
    var sections = ListSeparatorPreference()
}

private struct ListSeparatorDefaultsKey: EnvironmentKey {
    static let defaultValue = ListSeparatorDefaults()
}

extension EnvironmentValues {
    /// The separator preferences written above the lists in this subtree.
    var listSeparatorDefaults: ListSeparatorDefaults {
        get { self[ListSeparatorDefaultsKey.self] }
        set { self[ListSeparatorDefaultsKey.self] = newValue }
    }
}

// MARK: - The line

/// One separator line as a row draws it: the rule's ink and where it starts
/// and stops across the row's content (decisions A47).
struct ListRowSeparatorLine: Equatable {
    /// The ink, or `nil` for the list's own — the border's, as a `Divider`'s.
    var tint: Color?
    /// Cells of the row's content before the rule starts: the row's own
    /// ``HorizontalAlignment/listRowSeparatorLeading``, else 0 — the
    /// content's leading edge, as a macOS list insets its hairline to it.
    var leading = 0
    /// Where the rule stops, in cells from the content's leading edge: the
    /// row's own ``HorizontalAlignment/listRowSeparatorTrailing``, else `nil`
    /// — the row's trailing edge.
    var trailing: Int?

    /// The rule drawn `width` cells wide (the row's content width).
    func drawn(width: Int, palette: any Palette) -> String {
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
func reportSeparatorGuides(of child: ChildView, size: (width: Int, height: Int), row: Int, context: RenderContext) {
    guard child.providesAlignmentGuide, !context.isMeasuring,
        let reports = context.environment.listRowEditRestrictions
    else { return }
    let dimensions = ViewDimensions(width: size.width, height: size.height)
    let leading = child.explicitGuide(.horizontal(.listRowSeparatorLeading), at: dimensions, context: context)
    let trailing = child.explicitGuide(.horizontal(.listRowSeparatorTrailing), at: dimensions, context: context)
    guard leading != nil || trailing != nil else { return }
    reports.reportSeparatorGuides(row: row, (leading.map { Int($0.rounded()) }, trailing.map { Int($0.rounded()) }))
}

// MARK: - Row tint

extension View {
    /// Sets the tint color associated with a row.
    ///
    /// Separators can be presented above and below a row. You can specify to
    /// which edge this preference should apply. The tint colours the rule
    /// line under the row where one is drawn (``listRowSeparator(_:edges:)``);
    /// the line above a row is the row before it's, so `.top` tints nothing
    /// TUIkit's styles draw.
    ///
    /// ```swift
    /// List {
    ///     ForEach(garage.cars) { car in
    ///         Text(car.model)
    ///             .listRowSeparatorTint(car.brandColor)
    ///     }
    /// }
    /// ```
    ///
    /// Written on a `List` (or above one) rather than on a row, it tints every
    /// row's separator in the lists below.
    ///
    /// - Parameters:
    ///   - color: The color to use to tint the row separators, or `nil` to use
    ///     the default color for the current list style.
    ///   - edges: The set of row edges for which the tint applies. The default
    ///     is ``VerticalEdge/Set/all``.
    public func listRowSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View {
        _ListRowSeparatorPreferenceView(content: self, change: .tint(color, edges))
    }
}

/// Reports a row's separator preference to the list the row is in — or,
/// written outside any row, makes it the default of the lists below
/// (``renderReportingSeparator(_:change:sections:context:)``).
struct _ListRowSeparatorPreferenceView<Content: View>: View {
    let content: Content
    let change: ListSeparatorChange

    var body: Never {
        fatalError("_ListRowSeparatorPreferenceView renders via Renderable")
    }
}

extension _ListRowSeparatorPreferenceView: Renderable, Layoutable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderReportingSeparator(content, change: change, sections: false, context: context)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Names its content, so a guide or a z-index inside is still found.
extension _ListRowSeparatorPreferenceView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// `content` drawn after reporting `change` against the list row rendering now
/// — or, outside any list row, drawn with `change` applied to the defaults the
/// lists below read (``ListSeparatorDefaults``). A section's preference
/// (`sections`) is only ever a default here: inside a list, a `Section` is read
/// by the list's extraction and never drawn through this.
///
/// The report is `_RowEditRestrictionView`'s mechanism — the list stamps which
/// row is rendering on its per-frame collector — and declares a render side
/// effect, so a memoized row cannot skip it and lose its preference. A row
/// carrying no separator modifier pays nothing. The default is written through
/// `transformEnvironment`, which notes the write for the render memo: a
/// memoized list below a default that changed must not serve rows it drew
/// under the old one.
@MainActor
func renderReportingSeparator<Content: View>(
    _ content: Content, change: ListSeparatorChange, sections: Bool, context: RenderContext
) -> FrameBuffer {
    if !sections, let reports = context.environment.listRowEditRestrictions, let row = reports.currentRowIndex {
        if !context.isMeasuring {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            reports.reportSeparator(row: row, change)
        }
        return TUIkit.renderToBuffer(content, context: context)
    }
    return TUIkit.renderToBuffer(
        content.transformEnvironment(\.listSeparatorDefaults) { defaults in
            if sections { change.apply(to: &defaults.sections) } else { change.apply(to: &defaults.rows) }
        },
        context: context)
}

// MARK: - Section separators

extension View {
    /// Sets whether to hide the separator associated with a list section.
    ///
    /// Separators can be presented above and below a section: the rule line
    /// under the section's header (`.top`), and the one under its last row
    /// (`.bottom`) — where anything follows it.
    ///
    /// ```swift
    /// List {
    ///     ForEach(garage) { garage in
    ///         Section(header: Text(garage.location)) {
    ///             ForEach(garage.cars) { car in
    ///                 Text(car.model)
    ///             }
    ///         }
    ///         .listSectionSeparator(.hidden, edges: .bottom)
    ///     }
    /// }
    /// ```
    ///
    /// Written on a `List` (or above one) rather than on a `Section`, it is
    /// every section's in the lists below.
    ///
    /// - Parameters:
    ///   - visibility: The visibility of this section's separators.
    ///   - edges: The set of row edges for which the preference applies. The
    ///     default is ``VerticalEdge/Set/all``.
    public func listSectionSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        _ListSectionSeparatorView(content: self, change: .visibility(visibility, edges))
    }

    /// Sets the tint color associated with a section.
    ///
    /// Separators can be presented above and below a section — see
    /// ``listSectionSeparator(_:edges:)`` for which lines those are.
    ///
    /// - Parameters:
    ///   - color: The color to use to tint the section separators, or `nil` to
    ///     use the default color for the current list style.
    ///   - edges: The set of row edges for which the tint applies. The default
    ///     is ``VerticalEdge/Set/all``.
    public func listSectionSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View {
        _ListSectionSeparatorView(content: self, change: .tint(color, edges))
    }
}

/// A `Section` with a separator preference: read by a list as that section,
/// its preference in ``SectionInfo/separator``; anywhere else, its content
/// with the preference the default for the sections of the lists below.
struct _ListSectionSeparatorView<Content: View>: View {
    let content: Content
    let change: ListSeparatorChange

    var body: Never {
        fatalError("_ListSectionSeparatorView renders via Renderable")
    }
}

extension _ListSectionSeparatorView: Renderable, Layoutable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderReportingSeparator(content, change: change, sections: true, context: context)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _ListSectionSeparatorView: SectionRowExtractor where Content: SectionRowExtractor {
    func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID> {
        content.extractSectionContentRows(context: context)
    }

    func extractSectionInfo(context: RenderContext) -> SectionInfo {
        var info = content.extractSectionInfo(context: context)
        change.apply(to: &info.separator)
        return info
    }
}

/// Seen as the section it wraps by a list whose rows a `ForEach` of sections
/// makes (`isSectionRowType`). The preference does not travel that way: a
/// section the loop makes is drawn without it.
extension _ListSectionSeparatorView: SectionPartsProviding where Content: SectionPartsProviding {
    var sectionParts: SectionParts { content.sectionParts }
}
