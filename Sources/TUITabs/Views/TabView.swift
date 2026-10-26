//  🖥️ TUI — A Terminal UI framework for Swift
//  TabView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUILists

// `Tab`, `TabSection` and the `TabContent` they are written in live in
// `Tab.swift`, `TabSection.swift` and `TabContent.swift`; the style protocol
// and its built-in styles in `Styles/TabViewStyle.swift`.

// The TUI-specific TabView environment modifiers (header alignment, header
// wrapping, content sizing, content padding) live in `TabViewModifiers.swift`.

// MARK: - TabView

/// A view that switches between multiple child views using interactive user
/// interface elements: a strip of tabs above the selected tab's content.
///
/// Declare tabs with ``Tab``, and bind the selected one to `selection`:
///
/// ```swift
/// @State private var tab = 0
///
/// TabView(selection: $tab) {
///     Tab("Received", systemImage: "tray", value: 0) { ReceivedView() }
///     Tab("Sent", systemImage: "paperplane", value: 1) { SentView() }
/// }
/// ```
///
/// Or leave the selection to the tab view, which then selects a tab by its
/// place among the tabs:
///
/// ```swift
/// TabView {
///     Tab("Received", systemImage: "tray") { ReceivedView() }
///     Tab("Sent", systemImage: "paperplane") { SentView() }
/// }
/// ```
///
/// The strip is keyboard-navigable (`←`/`→`) when focused and responds to mouse
/// clicks. Each tab's content keeps its own `@State` — switching tabs does not
/// disturb another tab's editing state.
public struct TabView<SelectionValue: Hashable, Content: View>: View {
    /// The selection binding, or `nil` for a tab view built without one, which
    /// keeps its own (``implicitSelection``).
    let selection: Binding<SelectionValue>?

    /// The tabs the content declares, flattened.
    let tabs: [_RawTab]

    /// The tabs, as SwiftUI's tab view holds them.
    let content: Content

    /// The selected tab's value, for a tab view built without a selection:
    /// `nil` until a tab is chosen, which selects the first.
    @State private var implicitSelection: AnyHashable?

    /// Creates a tab view that uses a provided value to set the selected tab.
    ///
    /// - Parameters:
    ///   - selection: A binding to the value identifying the selected tab.
    ///   - content: The tabs: ``Tab``s, ``TabSection``s, `ForEach` loops of
    ///     them, and conditionals.
    public init<C: TabContent>(
        selection: Binding<SelectionValue>, @TabContentBuilder<SelectionValue> content: () -> C
    ) where Content == TabContentBuilder<SelectionValue>.Content<C> {
        let tabs = content()
        self.selection = selection
        self.tabs = tabList(of: tabs).tabs
        self.content = TabContentBuilder<SelectionValue>.Content(tabs)
    }

    @Environment(\.tabViewStyle) private var style

    /// What ``View/tabViewCustomization(_:)`` bound the sidebar to, if anything.
    @Environment(\.tabViewCustomization) private var customization

    /// A `.sidebarAdaptable` tab view shows a strip in a compact class.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public var body: some View {
        if style.stripLook == .sidebar {
            // In a compact class the layout draws a strip where its sidebar was,
            // and the tabs are then where a strip's are.
            let compact = horizontalSizeClass == .compact
            _TabSidebarLayout(tabs: sidebarTabs, stripTabs: stripTabs, selection: erasedSelection)
                .environment(\.tabBarPlacementValue, compact ? .topBar : .sidebar)
                .environment(\.tabBarShowingSections, !compact)
        } else {
            _TabViewCore(selection: erasedSelection, tabs: stripTabs)
                .environment(\.tabBarPlacementValue, .topBar)
                .environment(\.tabBarShowingSections, false)
        }
    }

    /// The tabs a sidebar lists: every one not hidden, as a bound
    /// customization arranges them.
    private var sidebarTabs: [_RawTab] {
        let shown = tabs.filter { !$0.isHidden }
        return customization?.value.arrangedSidebar(shown) ?? shown
    }

    /// The tabs a strip shows: every one not hidden, and not placed only in a
    /// sidebar.
    private var stripTabs: [_RawTab] {
        tabs.filter { !$0.isHidden && $0.placement != .sidebarOnly }
    }

    /// The selection, erased to the type the core compares tab values in.
    ///
    /// The builder ties every tab's value type to the selection's, so a tab's
    /// value and the selection are erased from the same static type and
    /// compare as values: an `Optional` selection's tabs carry `Optional`
    /// values (`Tab(_:value:)`'s promoting overloads), never bare ones.
    private var erasedSelection: Binding<AnyHashable> {
        if let selection {
            return Binding(
                get: { AnyHashable(selection.wrappedValue) },
                set: { if let value = $0.base as? SelectionValue { selection.wrappedValue = value } })
        }
        let implicit = $implicitSelection
        let first = stripTabs.first { !$0.isDisabled }?.value ?? AnyHashable(0)
        return Binding(get: { implicit.wrappedValue ?? first }, set: { implicit.wrappedValue = $0 })
    }
}

extension TabView where SelectionValue == Never {
    /// Creates a tab view that keeps the selected tab itself.
    ///
    /// The tabs carry no values: the tab view selects one by its place among
    /// them, starting with the first.
    ///
    /// - Parameter content: The tabs.
    public init<C: TabContent>(@TabContentBuilder<Never> content: () -> C)
    where Content == TabContentBuilder<Never>.Content<C> {
        let tabs = content()
        self.selection = nil
        self.tabs = tabList(of: tabs).tabs
        self.content = TabContentBuilder<Never>.Content(tabs)
    }
}

// MARK: - Core

enum TabViewStateIndex {
    static let focusID = 0
    static let handler = 1
    /// Per-tab measured content sizes (``TabSizeCache``), so the panel can size
    /// to the widest *and* tallest tab without re-measuring every tab each pass.
    static let sizeCache = 2
    /// The index of the tab under the pointer, or `nil`.
    static let hoveredTab = 3
}

/// Each tab's natural content size, per extent — width AND height — measured
/// at.
///
/// The extent has to be part of the key because only the *selected* tab is
/// re-measured each pass. Keyed by tab value alone, every other tab kept
/// whatever size it had at the width it was first seen at, so after a resize the
/// panel was built from stale numbers — and since the panel sizes to the tallest
/// and widest of all tabs, it jumped the instant one of those tabs became
/// selected and got re-measured.
///
/// The height too, because a tab's size depends on the height it is offered as
/// much as on the width: a `ScrollView` is as tall as the space it fits in, and
/// a `ViewThatFits(in: .vertical)` picks its layout — and with it its width —
/// by height. Keyed by width alone, a terminal that only got shorter left every
/// other tab at the size it had in the taller one: the panel kept the old
/// tallest tab's rows and its widest tab's columns until that tab was selected.
///
/// Several extents get measured within a single frame — a dialog probes its
/// body at more than one width before settling on one — so a cache that held
/// only the latest would flush and re-seed every tab on each probe. Holding a
/// handful covers a probe sweep and a resize, and evicting the least recently
/// used keeps it bounded across a long resize drag.
/// `Equatable` so the caller can decline to write back a cache that did not
/// change. Writing a `StateBox` invalidates the render cache and requests
/// another render — and this one is written from the MEASURE pass, so an
/// unconditional store made every frame schedule the next one, forever. See
/// ``_TabViewCore/tabContentSizes(insets:available:context:)``.
private struct TabSizeCache: Equatable {
    private static let capacity = 8

    /// The space the tabs were measured in.
    struct Extent: Hashable {
        let width: Int
        let height: Int
    }

    /// The extents held, least recently used first.
    private var order: [Extent] = []
    private var sizes: [Extent: [AnyHashable: ViewSize]] = [:]

    subscript(extent: Extent) -> [AnyHashable: ViewSize]? { sizes[extent] }

    mutating func set(_ entry: [AnyHashable: ViewSize], for extent: Extent) {
        if let existing = order.firstIndex(of: extent) { order.remove(at: existing) }
        order.append(extent)
        sizes[extent] = entry
        while order.count > Self.capacity { sizes.removeValue(forKey: order.removeFirst()) }
    }

    /// Whether these hold the same measurements — ignoring which width was
    /// touched most recently.
    ///
    /// The LRU order is bookkeeping, not content, and it moves on every `set`.
    /// A `TabView` measures at more than one width per frame (the panel sizes
    /// to its widest tab, then renders at the panel's width), so the order
    /// flipped every frame and the memo compared unequal to itself: the guarded
    /// write fired, the write invalidated the render cache and asked for
    /// another frame, and that frame did it again. A page with a `TabView` on
    /// it re-rendered forever, drawing an identical picture — measured at 14%
    /// of a core on the Example's Tab Views page, with nothing animating.
    func hasSameSizes(as other: Self) -> Bool { sizes == other.sizes }
}

/// Renders the tab strip plus the selected tab's content.
///
/// The selected content is rendered under a value-keyed *branch identity*, so
/// each tab's subtree (and its `@State`) is isolated — switching tabs can't
/// alias one tab's state onto another's.
struct _TabViewCore<SelectionValue: Hashable>: View, Renderable, Layoutable {
    let selection: Binding<SelectionValue>
    let tabs: [_RawTab]

    private typealias StateIndex = TabViewStateIndex

    var body: Never { fatalError("_TabViewCore renders via Renderable") }

    /// Index of the tab whose value matches the selection, or 0 (so something is
    /// always shown even if the binding holds a value with no matching tab).
    private var selectedIndex: Int {
        index(matching: selection.wrappedValue) ?? 0
    }

    /// The tab `value` names: the tab whose erased value equals the erased
    /// selection.
    ///
    /// Comparing two `AnyHashable`s is exact only where both were erased from
    /// the same static type, and the tab content builder is what makes that
    /// so: it ties every tab's value type to the tab view's selection type,
    /// and a tab naming a bare value in a view whose selection is OPTIONAL
    /// takes one of `Tab`'s promoting overloads and carries the Optional.
    /// Before the builder nothing linked the two, and
    /// `AnyHashable(Choice.b) == AnyHashable(Choice?.some(.b))` is FALSE — the
    /// view fell back to tab 0 and drew the wrong body; worse, `AnyHashable`
    /// unwraps Optionals for types with an ObjC bridge, so the `Int` spelling
    /// of that mistake worked on Apple platforms and failed on Linux.
    ///
    /// `TabView` hands its core the selection erased (it may be the tab view's
    /// own, for one built without a selection), so `SelectionValue` is
    /// `AnyHashable` here and the cast this used to make into the selection's
    /// type would only re-erase a tab value's base, unwrapping an Optional.
    private func index(matching value: SelectionValue) -> Int? {
        let erased = AnyHashable(value)
        return tabs.firstIndex { $0.value == erased }
    }

    /// The render context for the active tab's content: identity branched by the
    /// selected value, height reduced by the strip, and the tab — `available`
    /// across, that height down — as its `containerRelativeFrame` container.
    private func contentContext(_ context: RenderContext, stripHeight: Int, available: Int) -> RenderContext {
        var child = context.withBranchIdentity("tab-\(tabs[selectedIndex].value)")
        child.availableHeight = max(0, context.availableHeight - stripHeight)
        child = child.publishingContainerSize(CellSize(width: max(0, available), height: child.availableHeight))
        // The body is painted on the strip's surface, so anything inside that
        // draws a surface of its own has to step off THAT, not off the page.
        // Without this a `TextField` in a tab computed "a step above the page"
        // — which is the tab's own colour — and disappeared into it.
        child.environment.surfaceBackground = surfaceColor(context)
        return child
    }

    /// The context tab `index`'s content is MEASURED in: its own branch
    /// identity, `available` across, and the height the render lays it out in
    /// (``contentMeasureHeight(available:context:)``).
    ///
    /// One builder for every measure of a tab, so the panel's size and the
    /// selected tab's natural width are the same question, and a pass answers
    /// the second from the memo the first filled.
    private func tabMeasureContext(
        _ index: Int, available: Int, context: RenderContext
    ) -> RenderContext {
        var branch = context.withBranchIdentity("tab-\(tabs[index].value)")
        branch.availableWidth = available
        branch.availableHeight = contentMeasureHeight(available: available, context: context)
        // The tab is its content's `containerRelativeFrame` container, as in
        // `contentContext`; set, not noted, from a measure.
        return branch.publishingContainerSize(
            CellSize(width: max(0, available), height: branch.availableHeight), noting: false)
    }

    /// The height a tab's content is measured against: what the TabView has,
    /// less the strip's chrome — the height the render lays it out in
    /// (``contentContext(_:stripHeight:available:)``), not the whole of it.
    ///
    /// Measured against the whole, content within the strip's height of it was
    /// sized for rows the strip then took back. A scroll view there measured as
    /// fitting, so its ideal width had no column for a bar; drawn in the shorter
    /// height it overflowed, and its bar took that column out of the rows. A
    /// `ViewThatFits(in: .vertical)` sized the panel for the candidate that fits
    /// the whole height and was drawn as the one that fits what is left.
    ///
    /// Under the default wrap the strip folds at `available`, the width it is
    /// laid out in, so its rows are known before any content is measured. Under
    /// `.toContentWidth` it folds at the widest tab — which is what this measure
    /// finds — so the strip is taken at its one-row minimum there, and a strip
    /// that folds onto more rows still measures its content a row too tall per
    /// extra row (two in the bordered style).
    private func contentMeasureHeight(available: Int, context: RenderContext) -> Int {
        // No strip at all beside a sidebar, which draws the tabs instead.
        guard showsStrip(context) else { return context.availableHeight }
        let rows =
            context.environment.tabViewHeaderWrap == .toContentWidth
            ? 1 : stripRowGroups(style: .compact, available: available).count
        // Each strip row, and under `.bordered` each row's tops plus the box's
        // content border and bottom — the render's own `chrome`.
        let chrome = context.environment.tabStripLook == .bordered ? 2 * rows + 2 : rows
        return max(0, context.availableHeight - chrome)
    }

    /// Each tab's natural (unconstrained) content size, memoised per tab.
    ///
    /// Only the *selected* tab is measured each pass; the others reuse their last
    /// measured size from a per-tab cache. Measuring every tab each pass would
    /// fully render the non-`Layoutable` tabs (channel editors, the 139/216/256-
    /// swatch grids) hundreds of cells at a time — pathologically slow. A tab not
    /// yet seen is measured once to seed its entry. So the selected tab tracks its
    /// own `@State` (e.g. the 256-grid's "show numbers"), and the panel holds the
    /// widest/tallest of all tabs without re-rendering them.
    ///
    /// The cache is a pure memo keyed by content identity **and the extent it
    /// was measured in** (it can only ever equal what a measure would compute),
    /// so writing it during a measure pass is benign — it doesn't perturb layout,
    /// only avoids recomputation. A single `measureChild` already yields both
    /// axes, so caching the full ``ViewSize`` (rather than only the width) lets
    /// the panel size to the tallest tab too, at no extra measure cost.
    ///
    /// The extent has to be part of the key precisely *because* only the
    /// selected tab is re-measured: with the sizes keyed by tab value alone,
    /// every other tab kept whatever it measured at the width it was first seen
    /// at. Once the terminal (or any enclosing layout) changed width, the panel —
    /// sized to the tallest and widest of all tabs — was built from stale
    /// numbers, and jumped the instant you switched to one of them. The height
    /// is in it for the same reason (see ``TabSizeCache``). Re-seeding on a
    /// resize costs one full measure per tab and nothing in the steady state.
    private func tabContentSizes(
        insets: EdgeInsets, available: Int, context: RenderContext
    ) -> [AnyHashable: ViewSize] {
        func measureTab(_ index: Int) -> ViewSize {
            measureChild(
                tabs[index].content.padding(insets),
                proposal: ProposedSize(width: nil, height: nil),
                context: tabMeasureContext(index, available: available, context: context))
        }
        guard let stateStorage = context.stateStorage else {
            return [AnyHashable(tabs[selectedIndex].value): measureTab(selectedIndex)]
        }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.sizeCache)
        let box: StateBox<TabSizeCache> = stateStorage.storage(for: key, default: TabSizeCache())
        var cache = box.value
        // The space `measureTab` measures in.
        let extent = TabSizeCache.Extent(
            width: available, height: contentMeasureHeight(available: available, context: context))
        var entry = cache[extent] ?? [:]
        entry[AnyHashable(tabs[selectedIndex].value)] = measureTab(selectedIndex)
        for (i, tab) in tabs.enumerated() where entry[AnyHashable(tab.value)] == nil {
            entry[AnyHashable(tab.value)] = measureTab(i)  // one-time seed per tab, per extent
        }
        let present = Set(tabs.map { AnyHashable($0.value) })
        entry = entry.filter { present.contains($0.key) }  // drop removed tabs
        cache.set(entry, for: extent)
        // Only when the MEASUREMENTS actually changed. This runs during the
        // measure pass, and writing a `StateBox` invalidates the render cache
        // and asks for another render — which measures again, which wrote
        // again. An idle page with a tab view rendered itself forever at
        // whatever rate the loop would run, producing byte-identical frames,
        // with nothing on screen changing. The cache is a memo, not state;
        // re-storing the same memo must not dirty anything — and "the same"
        // means the same sizes, not the same LRU order (see `hasSameSizes`).
        if !cache.hasSameSizes(as: box.value) { box.value = cache }
        return entry
    }

    /// The widest tab's natural (unconstrained) content width — the panel sizes to
    /// it (stable across tab switches) and the strip folds to it, rather than a
    /// wide strip ballooning the panel. Capped to what's available.
    private func widestContentWidth(
        insets: EdgeInsets, available: Int, context: RenderContext
    ) -> Int {
        let cache = tabContentSizes(insets: insets, available: available, context: context)
        let widest = tabs.map { cache[AnyHashable($0.value)]?.width ?? 0 }.max() ?? 0
        return min(max(1, widest), max(1, available))
    }

    /// The tallest tab's natural (unconstrained) content height — the panel sizes
    /// to it so switching tabs doesn't change the panel height (mirroring how
    /// ``widestContentWidth`` keeps the width stable). Opt out per
    /// ``EnvironmentValues/tabViewContentSizing``: `.activeTab` returns the
    /// selected tab's height instead, so the panel tracks each tab's own height.
    ///
    /// Measuring the natural height at the same single per-tab measure the width
    /// uses makes this free. It is a safe panel height: the selected content is
    /// rendered at the (widest-tab) panel width, or at its own natural width
    /// when it fills its width (`selectedTabWidths`) — never narrower than its
    /// natural width — so it wraps no taller than its natural height.
    private func tallestContentHeight(
        insets: EdgeInsets, available: Int, context: RenderContext
    ) -> Int {
        let cache = tabContentSizes(insets: insets, available: available, context: context)
        if context.environment.tabViewContentSizing == .activeTab {
            return max(0, cache[AnyHashable(tabs[selectedIndex].value)]?.height ?? 0)
        }
        return tabs.map { cache[AnyHashable($0.value)]?.height ?? 0 }.max() ?? 0
    }

    /// The selected tab's two widths in a panel `panelWidth` wide: the width it
    /// is RENDERED at, and the width it is then clamped to and centred as — its
    /// natural (unconstrained) content width, what its ink actually occupies,
    /// capped at the panel.
    ///
    /// Content that does not fill its width is rendered at the full panel width
    /// (so a `ViewThatFits` editor reliably picks its wide single-row candidate
    /// rather than tipping onto a stacked fallback at a tight width), then
    /// clamped to its natural width and block-centred. A tab narrower than the
    /// panel — e.g. a slim channel editor in a panel widened by the 256-swatch
    /// grid — is thus centred; a tab as wide as the panel clamps to the panel
    /// and fills it.
    ///
    /// Content that FILLS its width is rendered at its natural width instead.
    /// Rendered at the panel's, it filled the panel — a `Divider` across it, a
    /// title centred in it, a scroll view's bar in its last column — and the
    /// clamp back to the natural width cut away whatever was drawn past it: a
    /// scroll view's bar, clamped off on every frame; a title and body either
    /// side of a `Divider`, both gone, the rule left alone in the middle of the
    /// panel; a text field's closing cap. At its natural width it fills exactly
    /// that, and the clamp has nothing to take.
    ///
    /// The natural width is measured in the height the tab is drawn in. That
    /// is `tabContentSizes`' own measure, served from this pass's memo —
    /// except under a `.toContentWidth` strip that folds onto more rows than
    /// that measure allowed for (``contentMeasureHeight(available:context:)``).
    /// There a scroll view measured as fitting eleven rows answered no column
    /// for a bar, and rendered at that width in the four rows eight strip rows
    /// left, its bar took the column out of the rows: "row 10" wrapped onto two
    /// lines.
    ///
    /// Neither rule applies where the natural width says nothing the panel
    /// should hold the content to — content that took all the width it was
    /// measured in, and any content when the panel is wider than that width: a
    /// strip wider than the space, as a bordered panel's one-tab row is in a
    /// very narrow terminal. Such content is rendered at the panel's width and
    /// not clamped. Measured in the six cells inside an eight-cell box under a
    /// seven-cell strip, an `HStack` of "a", a spacer and "b" reported the one
    /// cell it could squeeze into and a `List` the two it was given: rendered
    /// at those widths, the `HStack` lost its "b" and the `List` its right
    /// border.
    private func selectedTabWidths(
        insets: EdgeInsets, available: Int, panelWidth: Int, drawnHeight: Int,
        context: RenderContext
    ) -> (render: Int, natural: Int) {
        var measureContext = tabMeasureContext(selectedIndex, available: available, context: context)
        measureContext.availableHeight = drawnHeight
        let size = measureChild(
            tabs[selectedIndex].content.padding(insets),
            proposal: ProposedSize(width: nil, height: nil), context: measureContext)
        guard size.width < available, panelWidth <= available else {
            return (render: panelWidth, natural: panelWidth)
        }
        let natural = min(max(1, size.width), panelWidth)
        return (render: size.isWidthFlexible ? natural : panelWidth, natural: natural)
    }

    /// The wrap budget for the header strip: the content width when folding
    /// (`toContentWidth`), otherwise the full available width (wrap only on
    /// overflow).
    private func stripWrapBudget(widest: Int, available: Int, context: RenderContext) -> Int {
        context.environment.tabViewHeaderWrap == .toContentWidth ? widest : max(1, available)
    }

    /// The strip's visual rows (tab indices, top-to-bottom with the active row
    /// floated to the bottom) and each tab's horizontal centre in panel-relative
    /// cells. Mirrors the render geometry so the `TabStripHandler`'s up/down keys
    /// move to the tab actually above/below the current one.
    private func navigationGeometry(context: RenderContext) -> (rows: [[Int]], centers: [Int: Int]) {
        let style = context.environment.tabStripLook
        let alignment = context.environment.tabViewHeaderAlignment
        let insets = resolvedContentInsets(style: style, context: context)
        let bordered = style == .bordered
        let avail = bordered ? max(1, context.availableWidth - 2) : context.availableWidth
        let widest = widestContentWidth(insets: insets, available: avail, context: context)
        let rows = floatActiveRowToBottom(
            stripRowGroups(style: .compact, available: stripWrapBudget(widest: widest, available: avail, context: context)),
            selectedIndex: selectedIndex)
        let rowWidthOf: ([Int]) -> Int = bordered ? folderRowWidth : compactRowWidth
        let panelWidth = max(widest, rows.map(rowWidthOf).max() ?? 0)
        var centers: [Int: Int] = [:]
        for row in rows {
            var col = max(0, alignment.childOffset(childWidth: rowWidthOf(row), in: panelWidth))
            for i in row {
                let bodyWidth = tabWidth(i, style: bordered ? .bordered : .compact)
                let lead = bordered ? 1 : 0  // bordered: a wall precedes each tab body
                centers[i] = col + lead + bodyWidth / 2
                col += lead + bodyWidth
            }
        }
        return (rows, centers)
    }

    /// This core with every label of the app's own (`Tab(content:label:)`)
    /// replaced by its text, or `nil` when no tab has one — nearly always.
    ///
    /// The strip draws a tab's label as text, in its own ink and on its own
    /// field, so a label view is rendered — as a measure, which registers
    /// nothing — and its first line taken without its colours. Each label
    /// renders under an identity of its tab's, so one with `@State` keeps it.
    private func resolvingCustomLabels(_ context: RenderContext) -> Self? {
        guard tabs.contains(where: { $0.customLabel != nil }) else { return nil }
        var labelContext = context
        labelContext.isMeasuring = true
        let resolved = tabs.map { tab -> _RawTab in
            guard let label = tab.customLabel else { return tab }
            var tab = tab
            let text = TUIView.renderToBuffer(
                label, context: labelContext.withBranchIdentity("tab-label-\(tab.value)")
            ).lines.first?.stripped ?? ""
            tab.title = String(text.reversed().drop { $0 == " " }.reversed())
            tab.customLabel = nil
            return tab
        }
        return Self(selection: selection, tabs: resolved)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if let resolved = resolvingCustomLabels(context) {
            return resolved.sizeThatFits(proposal: proposal, context: context)
        }
        guard !tabs.isEmpty else { return ViewSize.fixed(0, 0) }
        let style = context.environment.tabStripLook
        var ctx = context
        ctx.availableWidth = proposal.width ?? context.availableWidth
        let insets = resolvedContentInsets(style: style, context: ctx)

        if style == .bordered {
            // Size to the widest tab; the strip wraps per the header-wrap mode.
            // Box chrome: each tab row is 2 lines (tops + labels) + the
            // content-border line + the bottom border, plus a 1-cell border side.
            let avail = max(1, ctx.availableWidth - 2)
            let widest = widestContentWidth(insets: insets, available: avail, context: ctx)
            let rows = stripRowGroups(
                style: .compact,
                available: stripWrapBudget(widest: widest, available: avail, context: ctx))
            let chrome = 2 * rows.count + 2
            // Size to the TALLEST tab (stable across switches), not just the
            // selected one — mirroring the widest-tab width.
            let contentHeight = tallestContentHeight(insets: insets, available: avail, context: ctx)
            let interior = max(widest, rows.map(folderRowWidth).max() ?? 0)
            return ViewSize(
                width: interior + 2, height: chrome + contentHeight,
                isWidthFlexible: false, isHeightFlexible: false)
        }

        // Compact: size to the widest tab; the strip wraps per the header-wrap
        // mode and the selected content is centred within it.
        let widest = widestContentWidth(insets: insets, available: ctx.availableWidth, context: ctx)
        let rows =
            showsStrip(ctx)
            ? stripRowGroups(
                style: .compact,
                available: stripWrapBudget(widest: widest, available: ctx.availableWidth, context: ctx))
            : []
        // Size to the TALLEST tab (stable across switches), not just the selected
        // one — mirroring the widest-tab width.
        let contentHeight = tallestContentHeight(
            insets: insets, available: ctx.availableWidth, context: ctx)
        let panelWidth = max(widest, rows.map(compactRowWidth).max() ?? 0)
        return ViewSize(
            width: panelWidth, height: rows.count + contentHeight,
            isWidthFlexible: false, isHeightFlexible: false)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if let resolved = resolvingCustomLabels(context) { return resolved.renderToBuffer(context: context) }
        guard !tabs.isEmpty else { return FrameBuffer() }
        let style = context.environment.tabStripLook
        let palette = context.environment.palette
        let isDisabled = !context.environment.isEnabled

        // Focus handler (arrow-key tab switching).
        let stateStorage = context.stateStorage!
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil, defaultPrefix: "tabview",
            propertyIndex: StateIndex.focusID)
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        // The matching TAB's erasure, not the selection's own: the handler
        // compares this against `values`, which are the tabs', so re-erasing
        // the selection here reintroduces exactly the mismatch
        // `index(matching:)` exists to avoid — the arrow keys would step from
        // whichever tab the fallback named. Falls back to the selection's own
        // erasure when no tab matches, so the handler always holds something.
        let erased = Binding<AnyHashable>(
            get: {
                let current = selection.wrappedValue
                return index(matching: current).map { tabs[$0].value }
                    ?? AnyHashable(current)
            },
            set: { if let v = $0.base as? SelectionValue { selection.wrappedValue = v } })
        let handlerBox: StateBox<TabStripHandler> = stateStorage.storage(
            for: handlerKey,
            default: TabStripHandler(
                focusID: persistedFocusID, selection: erased,
                values: tabs.map(\.value), canBeFocused: !isDisabled))
        let handler = handlerBox.value
        handler.selection = erased
        handler.values = tabs.map(\.value)
        handler.disabledValues = Set(tabs.filter(\.isDisabled).map(\.value))
        handler.canBeFocused = !isDisabled
        // The core's state — the size memo above all — is kept for the next
        // frame whether or not the strip registers, which marks it too.
        // Beside a sidebar nothing did: the memo the measure pass wrote was
        // gone by the next pass, which wrote it again, so every frame asked
        // for another and cleared every memo around the tab view.
        if !context.isMeasuring { stateStorage.markActive(context.identity) }
        // Beside a sidebar the strip is not drawn and is no focus stop: the
        // sidebar's list takes the keys and the clicks.
        if !context.isMeasuring, showsStrip(context) {
            let geometry = navigationGeometry(context: context)
            handler.rows = geometry.rows
            handler.centers = geometry.centers
            FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        }
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. The strip is
        // the only consumer of this flag, and all it does with it is breathe
        // the active chip; the arrow keys still reach the strip either way.
        let isFocused = context.indicatesFocus(
            FocusRegistration.isFocused(context: context, focusID: persistedFocusID) && !isDisabled)
        let selected = selectedIndex

        var buffer =
            style == .bordered
            ? renderBordered(
                selectedIndex: selected, isFocused: isFocused, palette: palette, context: context)
            : renderCompact(
                selectedIndex: selected, isFocused: isFocused && showsStrip(context), palette: palette,
                context: context)
        attachRevealRegion(
            to: &buffer, persistedFocusID: persistedFocusID, context: context)
        return buffer
    }

    /// A whole-TabView region carrying the persisted focusID, so an
    /// ENCLOSING ScrollView can locate the focused TabView and scroll it
    /// into view (`snapViewportToFocusedControl` scans regions by focusID —
    /// the same rule Table, List, and ScrollView follow). Whole-control
    /// deliberately, not the strip: a TabView taller than the viewport then
    /// top-aligns (headers visible, content filling the rest), and a
    /// shorter one is revealed entirely. The handler is inert and the
    /// region sits at the BACK of the dispatch order, so the tab-strip
    /// click regions and interactive tab content keep winning every click.
    @MainActor
    private func attachRevealRegion(
        to buffer: inout FrameBuffer, persistedFocusID: String, context: RenderContext
    ) {
        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        else { return }
        let handlerID = dispatcher.registerPassive(in: context) { _ in false }
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                handlerID: handlerID, focusID: persistedFocusID),
            at: 0
        )
    }

    private func persistedFocusIDForClicks(_ context: RenderContext) -> String {
        FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil, defaultPrefix: "tabview",
            propertyIndex: StateIndex.focusID)
    }

    /// Registers a click handler per tab region (selecting that tab).
    @MainActor
    private func attachTabClicks(
        to buffer: inout FrameBuffer,
        regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)],
        context: RenderContext
    ) {
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher else { return }
        let captureFocusID = persistedFocusIDForClicks(context)
        let focusManager = context.environment.focusManager
        // A tab is a click target, so it answers the pointer like one.
        dispatcher.requestFeature(.motion, in: context)
        let hoverBox = hoveredTabBox(context: context)
        for region in regions {
            let value = tabs[region.index].value
            let isDisabledTab = tabs[region.index].isDisabled
            let capture = selection
            let index = region.index
            let handlerID = dispatcher.register(in: context) { event in
                if let lifted = Self.hover(event, overTab: index, hoverBox: hoverBox) { return lifted }
                guard event.phase == .released, event.button == .left else {
                    return event.phase == .pressed && event.button == .left
                }
                focusManager?.focus(id: captureFocusID)
                // A disabled tab takes the click and selects nothing.
                if !isDisabledTab, let v = value.base as? SelectionValue { capture.wrappedValue = v }
                return true
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: region.x, offsetY: region.y, width: region.width, height: region.height,
                    handlerID: handlerID, focusID: nil))
            // A drag held still over the chip selects its tab, as the click
            // above does.
            registerSpringLoading(forTab: region.index, handlerID: handlerID, context: context)
        }
        // Each chip's own context menu, popovers, drag and drops, in front of
        // the click regions above.
        attachTabInteractions(to: &buffer, regions: regions, context: context)
    }

    /// Renders the `.bordered` style: folder tabs sitting on a line-drawn content
    /// box. Inactive tabs sit on the box's top border (separated from the content
    /// by it); the active tab's row floats to the bottom and its underside opens
    /// into the content — the border curves around it (`╯ … ╰`) so the tab and
    /// the body read as one surface. The strip is aligned (leading / centre /
    /// trailing) over the box.
    ///
    /// For a single row this matches a classic notebook tab exactly. When the
    /// tabs wrap, upper rows stack as folder-tab strips above the active row; only
    /// the active (bottom) row connects into the content.
    private func renderBordered(
        selectedIndex: Int, isFocused: Bool, palette: any Palette, context: RenderContext
    ) -> FrameBuffer {
        let surface = surfaceColor(context)
        let border = palette.border
        // The appearance's border, as every box's is (owner, 2026-10-24:
        // "TabView borders should reflect the active border style").
        let glyphs = TabBoxGlyphs(context.environment.appearance.borderStyle)
        let insets = resolvedContentInsets(style: .bordered, context: context)
        let alignment = context.environment.tabViewHeaderAlignment
        let chip = ActiveChipCycle(
            surface: surface,
            restingLabel: ContrastingLabel.on(surface, palette: palette),
            palette: palette, isFocused: isFocused, context: context)
        let (inactiveFg, inactiveBg) = stripLabelColors(palette: palette)

        // Size to the widest tab; the strip wraps per the header-wrap mode.
        let avail = max(1, context.availableWidth - 2)
        let widest = widestContentWidth(insets: insets, available: avail, context: context)
        let rows = floatActiveRowToBottom(
            stripRowGroups(
                style: .compact,
                available: stripWrapBudget(widest: widest, available: avail, context: context)),
            selectedIndex: selectedIndex)
        guard !rows.isEmpty else { return FrameBuffer() }
        let chrome = 2 * rows.count + 2  // each row: tops + labels; plus content-border + bottom
        let interior = max(widest, rows.map(folderRowWidth).max() ?? 0)
        let boxWidth = interior + 2

        // Render the content at the full interior width (so a ViewThatFits editor
        // reliably picks its wide layout) — or, when it fills its width, at its
        // natural width (see `selectedTabWidths`) — then clamp it to its own
        // natural width so the per-line padding below centres it as a block; a
        // tab as wide as the interior clamps to it and fills. (See the compact
        // path.)
        var contentCtx = contentContext(context, stripHeight: chrome, available: avail)
        let widths = selectedTabWidths(
            insets: insets, available: avail, panelWidth: interior,
            drawnHeight: contentCtx.availableHeight, context: context)
        contentCtx.availableWidth = widths.render
        let full = TUIView.renderToBuffer(
            tabs[selectedIndex].content.padding(insets).background(surface), context: contentCtx)
        let content = full.clamped(toWidth: widths.natural, height: full.height)

        let strip = folderStripRows(
            rows: rows, selectedIndex: selectedIndex, chip: chip,
            style: FolderStripStyle(
                inactiveFg: inactiveFg, hoveredIndex: liftedTab(context: context),
                palette: palette, inactiveBg: inactiveBg,
                border: border, glyphs: glyphs, surface: surface, interior: interior, boxWidth: boxWidth,
                alignment: alignment, legibility: context.environment.legibilityWeight))
        /// Every line of the box, the strip's first. Each carries its own claims,
        /// placed on the row it lands on when the box is flattened below.
        var box = strip.lines
        /// A line of the box below the strip: border ink on nothing either side, and
        /// whatever lies between them bringing its own claims.
        func boxLine(_ inside: ClaimingRow) -> ClaimingRow {
            var line = ClaimingRow()
            line.append(String(glyphs.wall), cells: 1, ink: border, field: glyphs.field(border))
            line.append(contentsOf: inside)
            line.append(String(glyphs.rightWall), cells: 1, ink: border, field: glyphs.field(border))
            return line
        }

        // Content rows, centred within the interior as one block (a uniform
        // offset, so internal column alignment is preserved), then the bottom.
        //
        // The rows the content may occupy once the strip and borders take
        // theirs. The panel is hard-capped to `availableHeight` (the clamp at
        // the end), so any content beyond this budget could only survive by
        // displacing the bottom border — GitHub issue #13's missing `╰─╯`, with
        // stray interior rows where it should have been. Two ways past the
        // budget, both capped here: a tab genuinely taller than the terminal;
        // and, under `.toContentWidth`, a height-flexible tab (a ScrollView, a
        // Spacer) measured against a strip of fewer rows than the one drawn —
        // its rows are not known until the tabs are measured
        // (`contentMeasureHeight`), so `tallestContentHeight` can pad the panel
        // a strip row past what fits. Either way the content clips INSIDE the
        // border, like any other bordered container.
        let contentPad = max(0, (interior - content.width) / 2)
        let contentStartY = box.count
        let (visibleContent, panelContentHeight) = borderedPanelContent(
            content: content, insets: insets, avail: avail, chrome: chrome, context: context)
        for line in visibleContent.lines {
            box.append(boxLine(panelRow(
                line, used: line.strippedLength, leftPad: contentPad, width: interior, surface: surface)))
        }
        // Size the box to the TALLEST tab so switching tabs doesn't change the
        // box height: pad the (selected) content down to that height with
        // surface-filled interior rows before the bottom border.
        while box.count - contentStartY < panelContentHeight {
            box.append(boxLine(panelRow("", used: 0, leftPad: 0, width: interior, surface: surface)))
        }
        var bottom = ClaimingRow()
        let rule =
            String(glyphs.bottomLeft) + String(repeating: glyphs.bottomHorizontal, count: interior)
            + String(glyphs.bottomRight)
        bottom.append(rule, cells: interior + 2, ink: border, field: glyphs.field(border))
        box.append(bottom)

        var buffer = FrameBuffer(lines: box.map(\.text))
        // The box's own claims — the strip's chrome and labels, the walls, the pads,
        // the fillers, the rule — each on the row its line landed on. The content
        // between the pads is claimed by its own buffer, added below.
        buffer.opacityRegions = box.enumerated().flatMap { row, line in
            line.claims.map { $0.shifted(byX: 0, y: row) }
        }
        // The strip's rows open the buffer, so the run's coordinates are the
        // buffer's already.
        buffer.animatedCells = context.isMeasuring ? [] : strip.animatedCells
        // Re-attach the content's interactive regions/overlays (slider, toggle, …):
        // the content rows above were rebuilt as fresh strings, so the content
        // buffer's hit regions are not carried automatically. Shift them past the
        // left border + centring pad and down past the tab-strip rows. From the
        // budget-clipped content, so nothing hit-tests against rows not drawn.
        let contentShiftX = 1 + contentPad
        buffer.appendHitTestRegions(of: visibleContent, shiftedByX: contentShiftX, y: contentStartY)
        buffer.overlays.append(
            contentsOf: visibleContent.shiftedOverlays(byX: contentShiftX, y: contentStartY))
        // The strip, the walls and the bottom rule are drawn over what the tab
        // draws past its region, as a box's border is; past them it is still
        // drawn (decisions-GUIDE3 B-GUIDE3-5).
        buffer.coverOverflowUnderBorder(innerWidth: interior, topRows: contentStartY)
        // …and the runs, for the same reason and by the same shift: a focused
        // control inside the tab breathes only if its run reaches the root, and
        // the assignment above replaced the buffer's runs with the strip's.
        if !context.isMeasuring {
            buffer.animatedCells.append(
                contentsOf: visibleContent.shiftedAnimatedCells(
                    byX: contentShiftX, y: contentStartY))
        }
        // …and the opacity regions, likewise. Only this style needs saying: the
        // `.compact` panel composes with `replacingLines` + `appendVertically`,
        // which carry every payload on their own.
        buffer.opacityRegions.append(
            contentsOf: visibleContent.shiftedOpacityRegions(
                byX: contentShiftX, y: contentStartY))
        attachTabClicks(to: &buffer, regions: strip.regions, context: context)
        return buffer.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// The budget-clipped content rows and the interior height the panel pads
    /// to — both capped to what fits below the strip, so the bottom border
    /// always survives (GitHub issue #13; see the call site's rationale).
    private func borderedPanelContent(
        content: FrameBuffer, insets: EdgeInsets, avail: Int, chrome: Int, context: RenderContext
    ) -> (visible: FrameBuffer, panelHeight: Int) {
        let budget = max(0, context.availableHeight - chrome)
        let visible =
            content.height > budget
            ? content.clamped(toWidth: content.width, height: budget)
            : content
        let panelHeight = min(
            tallestContentHeight(insets: insets, available: avail, context: context), budget)
        return (visible, panelHeight)
    }

    // MARK: Surface, padding & geometry

    /// The shared surface — a very subtle lift above the base background (the
    /// app-header tone), used for the active tab and the content area so they
    /// read as one continuous surface without an accent fill washing out the
    /// content. Follows `appHeaderBackground` when the palette states one, and
    /// otherwise a derived step off the page — never the page colour itself.
    ///
    /// ``EnvironmentValues/liftedSurface``: a tab body inside another tab body
    /// steps off THAT, not off the page. (This view publishes
    /// `surfaceBackground` for its children, which is what a nested one reads
    /// there.)
    private func surfaceColor(_ context: RenderContext) -> Color {
        context.environment.liftedSurface
    }

    /// Whether this core draws its strip: always, except beside the sidebar a
    /// `.sidebarAdaptable` tab view draws its tabs in (`_TabSidebarLayout`),
    /// where it draws the selected tab's content alone — which is not there in
    /// a compact size class (``EnvironmentValues/tabStripLook``).
    func showsStrip(_ context: RenderContext) -> Bool {
        context.environment.tabStripLook != .sidebar
    }

    /// The interior padding around each tab's content. An explicit
    /// `.tabViewContentPadding(_:)` wins; otherwise bordered gets a comfortable
    /// inset and compact none (the strip already abuts the content).
    private func resolvedContentInsets(style: _TabStripLook, context: RenderContext) -> EdgeInsets {
        if let explicit = context.environment.tabViewContentPadding { return explicit }
        return style == .bordered ? EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2) : EdgeInsets()
    }

    /// Reorders a wrapped strip so the active tab's row sits at the bottom (it
    /// abuts and connects to the content), *rotating* the others so they keep
    /// their cyclic order above it.
    ///
    /// Rotating — rather than just lifting the active row out and appending it —
    /// is what makes Up navigation reach every row. Up always selects the row
    /// directly above the active (bottom) one, which then rotates to the bottom;
    /// rotation feeds a *different* row into the second-from-bottom slot each
    /// time, so repeated Up walks the whole strip. Lifting-and-appending instead
    /// froze the upper rows, leaving Up oscillating between the bottom two.
    private func floatActiveRowToBottom(_ rows: [[Int]], selectedIndex: Int) -> [[Int]] {
        guard rows.count > 1,
            let activeRow = rows.firstIndex(where: { $0.contains(selectedIndex) })
        else { return rows }
        let pivot = (activeRow + 1) % rows.count  // rotate so the active row lands last
        return Array(rows[pivot...] + rows[..<pivot])
    }

    /// A bordered (folder-tab) row's width: each tab body is `" title "`, and the
    /// tabs share `count + 1` vertical walls.
    func folderRowWidth(_ row: [Int]) -> Int {
        row.reduce(0) { $0 + tabWidth($1, style: .bordered) } + (row.count + 1)
    }

    /// A compact row's width: the chips (each `▐ title ▌`, or another family's
    /// caps, always a cell each) abut with no separator.
    func compactRowWidth(_ row: [Int]) -> Int {
        row.reduce(0) { $0 + tabWidth($1, style: .compact) }
    }

    // MARK: Strip rendering

    /// Per-tab visible width (cells), excluding inter-tab separators. Compact
    /// tabs carry two extra cells for their caps (``ControlEnds``), whatever
    /// the family draws in them.
    ///
    /// The title is measured in CELLS, not Characters: a CJK or emoji title
    /// draws two cells per Character, and every width in the strip — row widths,
    /// the panel it sizes, the folder-tab walls, the click regions — is derived
    /// from this one number. Counting Characters here drew a strip wider than it
    /// measured, so the box came out ragged and the click regions slid left of
    /// the tabs they belong to.
    func tabWidth(_ index: Int, style: _TabStripLook) -> Int {
        let body = tabs[index].title.strippedLength + tabs[index].badgeSuffix.strippedLength + 2  // " title "
        return style == .compact ? body + 2 : body
    }

    /// Cells between adjacent tabs on a row (bordered uses a │; compact's caps
    /// abut, so none).
    private func tabSeparatorWidth(style: _TabStripLook) -> Int {
        style == .bordered ? 1 : 0
    }

    /// The visible width the strip occupies on a single row.
    private func stripVisibleWidth(style: _TabStripLook) -> Int {
        let body = tabs.indices.reduce(0) { $0 + tabWidth($1, style: style) }
        let separators = max(0, tabs.count - 1) * tabSeparatorWidth(style: style)
        return body + separators + (style == .bordered ? 1 : 0)  // bordered: leading │
    }

    /// Groups tab indices into rows that each fit within `available`. Wraps only
    /// when the single-row strip would overflow, then balances the tabs across
    /// the fewest rows so no row hogs the full width — with few tabs (the common
    /// case) this stays one row. A single tab is never split.
    private func stripRowGroups(style: _TabStripLook, available: Int) -> [[Int]] {
        let widths = tabs.indices.map { tabWidth($0, style: style) }
        let sep = tabSeparatorWidth(style: style)
        let total = stripVisibleWidth(style: style)
        let avail = max(1, available)
        let rowCount = max(1, (total + avail - 1) / avail)   // ceil(total / avail)

        // Greedily pack tabs into rows no wider than `cap` (a single tab is never
        // split).
        func pack(cap: Int) -> [[Int]] {
            var rows: [[Int]] = []
            var current: [Int] = []
            var width = 0
            for i in tabs.indices {
                let addend = (current.isEmpty ? 0 : sep) + widths[i]
                if !current.isEmpty && width + addend > cap {
                    rows.append(current)
                    current = []
                    width = 0
                }
                width += (current.isEmpty ? 0 : sep) + widths[i]
                current.append(i)
            }
            if !current.isEmpty { rows.append(current) }
            return rows
        }

        // Start from the balanced target row width, then widen the cap just enough
        // that greedy packing actually fits in `rowCount` rows. Greedy alone can
        // spill an extra (often single-tab) row — e.g. orphaning the last tab on
        // its own line — when the balanced target is a hair too tight.
        var cap = max((total + rowCount - 1) / rowCount, (widths.max() ?? 0) + sep)
        var rows = pack(cap: cap)
        while rows.count > rowCount && cap < avail {
            cap += 1
            rows = pack(cap: cap)
        }
        return rows
    }

    /// Compact: a border-free strip of chips, the active row floated to the
    /// bottom, above the content. The active chip and the content share the
    /// subtle surface, so they read as one island; inactive chips recede onto the
    /// base background.
    private func renderCompact(
        selectedIndex: Int, isFocused: Bool, palette: any Palette, context: RenderContext
    ) -> FrameBuffer {
        let surface = surfaceColor(context)
        let insets = resolvedContentInsets(style: .compact, context: context)
        let alignment = context.environment.tabViewHeaderAlignment
        let chip = ActiveChipCycle(
            surface: surface,
            restingLabel: ContrastingLabel.on(surface, palette: palette),
            palette: palette, isFocused: isFocused, context: context)

        // Size to the widest tab; the strip wraps per the header-wrap mode (folded
        // to the content width, or only on overflow) — and is not drawn at all
        // beside a sidebar, which draws the tabs instead.
        let widest = widestContentWidth(insets: insets, available: context.availableWidth, context: context)
        let rows =
            showsStrip(context)
            ? floatActiveRowToBottom(
                stripRowGroups(
                    style: .compact,
                    available: stripWrapBudget(widest: widest, available: context.availableWidth, context: context)),
                selectedIndex: selectedIndex)
            : []
        let panelWidth = max(widest, rows.map(compactRowWidth).max() ?? 0)

        // Render the content at the full panel width (so a ViewThatFits editor
        // reliably picks its wide single-row layout rather than tipping onto a
        // stacked fallback at a tight width) — or, when it fills its width, at
        // its natural width (see `selectedTabWidths`) — then clamp it to its own
        // natural width so the leftPad below centres it as a block. A tab as
        // wide as the panel clamps to the panel and fills it (leftPad 0). Clamp
        // preserves the content's hit regions, so its controls stay clickable
        // once centred.
        var contentCtx = contentContext(context, stripHeight: rows.count, available: context.availableWidth)
        let widths = selectedTabWidths(
            insets: insets, available: context.availableWidth, panelWidth: panelWidth,
            drawnHeight: contentCtx.availableHeight, context: context)
        contentCtx.availableWidth = widths.render
        let full = TUIView.renderToBuffer(
            tabs[selectedIndex].content.padding(insets).background(surface), context: contentCtx)
        let content = full.clamped(toWidth: widths.natural, height: full.height)

        let strip = compactStripLines(
            rows: rows, selectedIndex: selectedIndex,
            hoveredIndex: liftedTab(context: context),
            chip: chip, palette: palette,
            width: panelWidth, alignment: alignment, context: context)
        let (stripLines, regions) = (strip.lines, strip.regions)
        let claims = strip.claims

        // Centre the content block within the panel as one surface island,
        // shifting it (and its click regions) by a uniform offset so a narrower
        // tab's content is centred without disturbing its internal column
        // alignment (sliders / fields stay lined up). Each row is `panelRow`'s — the
        // content spliced in, the pads either side claimed — and its claims move to
        // the row it lands on, in panel coordinates.
        let leftPad = max(0, (panelWidth - content.width) / 2)
        var padded: [OpacityRegion] = []
        var centredLines = content.lines.enumerated().map { row, line -> String in
            let panelLine = panelRow(
                line, used: line.strippedLength, leftPad: leftPad, width: panelWidth, surface: surface)
            padded += panelLine.claims.map { $0.shifted(byX: 0, y: row) }
            return panelLine.text
        }
        // Size the panel to the TALLEST tab so switching tabs doesn't change the
        // panel height: pad the (selected) content down to that height with
        // surface-filled rows, so the shorter tabs read as the same island.
        let panelContentHeight = tallestContentHeight(
            insets: insets, available: context.availableWidth, context: context)
        while centredLines.count < panelContentHeight {
            // A filler row is a panel row with no content: surface all the way across,
            // one pad and so one claim.
            let filler = panelRow("", used: 0, leftPad: 0, width: panelWidth, surface: surface)
            padded += filler.claims.map { $0.shifted(byX: 0, y: centredLines.count) }
            centredLines.append(filler.text)
        }
        var centredContent = content.replacingLines(centredLines, overlayShiftX: leftPad)
        // After `replacingLines`, which shifts the content's OWN regions by `leftPad`.
        // These are already in panel coordinates, so they are appended rather than
        // carried through that shift.
        centredContent.opacityRegions += padded

        var buffer = FrameBuffer(lines: stripLines)
        buffer.appendVertically(centredContent)
        // The strip is the top of the buffer, so its coordinates are already
        // the buffer's. (The clamp below drops the run if the chip is off-screen
        // — the run goes with the cells it describes.) Prepended rather than
        // assigned: `appendVertically` already carried the content's own runs
        // up, correctly shifted, and overwriting them froze every focused
        // control inside a tab.
        buffer.animatedCells =
            context.isMeasuring ? [] : strip.animatedCells + buffer.animatedCells
        // The strip opens the buffer, so its claims are already in the buffer's
        // coordinates; `appendVertically` has carried the panel's up, shifted.
        buffer.opacityRegions += claims
        attachTabClicks(to: &buffer, regions: regions, context: context)
        return buffer.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// The persistent "which tab is the pointer over" box.
    func hoveredTabBox(context: RenderContext) -> StateBox<Int?> {
        context.stateStorage!.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.hoveredTab),
            default: nil)
    }
}

// `TabStripHandler` (the strip's focus/keyboard handler) lives in
// `TabStripHandler.swift`.

// MARK: - Environment without reflection

extension TabView: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _style.resolveEnvironment(environment)
        _customization.resolveEnvironment(environment)
        _horizontalSizeClass.resolveEnvironment(environment)
    }
}
