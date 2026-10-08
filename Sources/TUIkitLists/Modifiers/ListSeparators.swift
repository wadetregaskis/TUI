//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListSeparators.swift
//
//  A list's separators: a rule line between rows (decisions A47).
//  `listRowSeparatorTint(_:edges:)`, `listSectionSeparator(_:edges:)`,
//  `listSectionSeparatorTint(_:edges:)`. `listRowSeparator(_:edges:)` is in
//  `ListRowSeparatorModifier.swift`, the two separator alignment guides in
//  `ListRowSeparatorGuides.swift`, and the statement a row reports in
//  `ListSeparatorPreference.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

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

/// Names its content, so a z-index inside is still found.
extension _ListRowSeparatorPreferenceView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Answers for the guides its content sets, which it draws unchanged at its own
/// identity — the separator guides above all: Apple's documented row writes
/// `.listRowSeparatorLeading` on a view INSIDE the one the separator modifiers
/// are written on.
extension _ListRowSeparatorPreferenceView {
    /// See ``ListRowSeparatorModifier/_providesAlignmentGuide``.
    static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

extension _ListRowSeparatorPreferenceView: AlignmentGuideQuerying {
    func explicitGuide(_ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext) -> Double? {
        TUIkitFoundation.explicitGuide(of: content, query, in: dimensions, context: context)
    }
}

/// `content` drawn after reporting `change` against the list row rendering now
/// — or, outside any list row, drawn with `change` applied to the defaults the
/// lists below read (``ListSeparatorDefaults``). A section's preference
/// (`sections`) is only ever a default here: inside a list, a `Section` is read
/// by the list's extraction and never drawn through this.
///
/// The report is `_RowEditRestrictionView`'s mechanism — the list stamps which
/// row is rendering on its per-frame collector — and declares a render side
/// effect where losing it could change what the row draws
/// (``ListSeparatorChange/changesRow(over:)``), so a memoized row cannot skip
/// it and lose its preference. A row carrying no separator modifier pays
/// nothing, and neither does one whose modifiers change nothing — the
/// ported `.listRowSeparator(.hidden)` under a list that draws none: a side
/// effect stops the row's memo, and every memo around the list, from keeping
/// anything, as `_RowEditRestrictionView` refuses to for a row that refuses
/// nothing. Such a row still reports while it renders: in a row whose other
/// statements DO change something, it is rendered every frame, and the order
/// of its statements is what decides. The default is written through
/// `transformEnvironment`, which notes the write for the render memo: a
/// memoized list below a default that changed must not serve rows it drew
/// under the old one.
@MainActor
func renderReportingSeparator<Content: View>(
    _ content: Content, change: ListSeparatorChange, sections: Bool, context: RenderContext
) -> FrameBuffer {
    if !sections, let reports = context.environment.listRowEditRestrictions, let row = reports.currentRowIndex {
        if !context.isMeasuring {
            if change.changesRow(over: context.environment.listSeparatorDefaults.rows) {
                context.environment.volatileReadTracker?.recordRenderSideEffect()
            }
            reports.reportSeparator(row: row, change)
        }
        return TUIkitView.renderToBuffer(content, context: context)
    }
    return TUIkitView.renderToBuffer(
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
