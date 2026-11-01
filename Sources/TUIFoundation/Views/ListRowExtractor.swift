//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowExtractor.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - List Row

/// A single row in a list, containing an ID and rendered content.
///
/// `ListRow` wraps user-provided content and associates it with an identifier
/// for selection tracking. Rows can span multiple lines (multi-line content).
///
/// The buffer and badge are rendered lazily (see ``LazyListRowContent``): the
/// view is built and rendered only when the row is actually shown. The `id`
/// is resolved eagerly too, except a flattened child's, which is carried
/// still to be asked (``askedID``) — see ``id``.
package struct ListRow<ID: Hashable> {
    /// The identifier the selection knows this row by, or `nil` when it has
    /// none it can express.
    ///
    /// A static row's id is its own `.tag(_:)`, or failing that its index —
    /// and an index cannot be cast into a `String`, a `UUID` or a `Set` of
    /// either. A row with neither draws and simply does not participate in
    /// selection, which is SwiftUI's treatment of a row carrying no `tag(_:)`.
    /// It used to be DROPPED, which made a whole list of static rows render as
    /// the empty placeholder. See ``staticListRowID(of:ordinal:as:)``.
    ///
    /// A row a `Section` flattened out of mixed content is asked for it here,
    /// through ``askedID``: a looped row's answer is its loop's rule, which
    /// for a `.tag(_:)`-carrying row BUILDS the row, and the list asks for
    /// the ids of the rows it draws and the handler wants, not of every row.
    @MainActor package var id: ID? {
        if let askedID { return askedID.id }
        return knownID
    }

    /// ``id``, when it was resolved at construction.
    private let knownID: ID?

    /// ``id``, when it is still to be asked — `nil` for every row but a
    /// flattened child's.
    package let askedID: AskedRowID<ID>?

    /// The lazily-rendered buffer + badge for this row.
    package let content: LazyListRowContent

    /// The rendered content buffer for this row (forces the lazy render).
    @MainActor var buffer: FrameBuffer { content.buffer }

    /// The badge value for this row (forces the lazy render).
    @MainActor var badge: BadgeValue? { content.badge }

    /// The height of this row in lines (forces the lazy render).
    @MainActor var height: Int { content.buffer.height }

    /// Creates a row whose content is rendered on demand.
    package init(id: ID?, content: LazyListRowContent) {
        self.knownID = id
        self.askedID = nil
        self.content = content
    }

    /// This row with `transform` applied to its buffer as it renders — a
    /// modifier on its section, which reaches each of the section's rows (see
    /// `ModifiedView`'s `SectionRowExtractor` conformance). Its id, badge and
    /// type-select text are this row's.
    @MainActor
    package func mappingBuffer(_ transform: @escaping (FrameBuffer) -> FrameBuffer) -> Self {
        Self(knownID: knownID, askedID: askedID, content: content.mapped(transform))
    }

    private init(knownID: ID?, askedID: AskedRowID<ID>?, content: LazyListRowContent) {
        self.knownID = knownID
        self.askedID = askedID
        self.content = content
    }

    /// Creates a flattened child's row, drawn on demand, its id still to be
    /// asked.
    init(askedID: AskedRowID<ID>, content: LazyListRowContent) {
        self.knownID = nil
        self.askedID = askedID
        self.content = content
    }
}

// MARK: - Identifying a statically-built row

/// The selection value a statically-built row takes: its own `.tag(_:)` where
/// it has one, else its ordinal among the rows.
///
/// The tag comes first because it is the only way SwiftUI gives a static row a
/// selection value at all — View/tag(_:): "Sets the unique tag value of this
/// view. Use this modifier to differentiate among certain selectable views" —
/// while the ordinal is a fallback this framework invented, and a row that can
/// say what it is should not be answered with where it sits.
///
/// `nil` means the row draws but cannot be selected: no tag, and an ordinal
/// that will not cast into a `String`, a `UUID` or a `Set` of either.
///
/// One function because both the flat `List` (`_ListCore.extractFromChildren`
/// and its single-row fallback) and `Section.extractListRows` key static rows,
/// and a row inside a Section is a row of the enclosing List — the two must not
/// drift into different rules. The two child walks ask through
/// ``FlattenedRowIDs``, which answers a LOOPED row among the static ones by its
/// `ForEach`'s rule instead, applies this rule to every other row, and withholds
/// an ordinal that a looped row beside it already answers to.
@MainActor
package func staticListRowID<ID: Hashable>(of view: some View, ordinal: Int, as idType: ID.Type) -> ID? {
    extractTagValue(from: view, as: idType) ?? (ordinal as? ID)
}

// MARK: - List Row Extractor Protocol

/// Protocol for views that can provide list rows with IDs (eagerly).
///
/// Used by `Section`, whose row set is small and structured. The hot path for a
/// large flat `List` is ``WindowedListRowExtractor`` instead.
@MainActor
package protocol ListRowExtractor {
    /// Extracts every list row eagerly, with its associated ID.
    func extractListRows<ID: Hashable>(context: RenderContext) -> [ListRow<ID>]
}

/// A row extractor that supports *windowed* materialisation: the row count and
/// each row's id are resolved on demand (cheap — a count and a key-path read),
/// and a row's content box is built only when that row enters the overflow check
/// or the visible window. A 50,000-row `List` then touches ~viewport rows per
/// frame instead of 50,000 — both id resolution and content are O(visible), not
/// O(total). `ForEach` conforms; `List` prefers this path and falls back to the
/// eager ``ListRowExtractor`` when it isn't available (e.g. heterogeneous
/// content) or the ids can't be expressed as the list's selection type.
///
/// - Important: `List` probes row 0 once to decide windowability, on the
///   expectation that whether ``listRowID(at:rowsPerElement:)`` resolves to a
///   given `ID` does not vary by index. `ForEach`'s element ids do not (one
///   element type, one id key-path), but a row's own tag or link value can, so
///   a later row that declines is drawn as one that selects nothing.
@MainActor
package protocol WindowedListRowExtractor {
    /// The number of rows, in O(1), without building or rendering any content.
    var listRowCount: Int { get }

    /// The id of the row at `index`, resolved cheaply (a key-path read or the
    /// index) without building content. Returns `nil` if the element's id can't
    /// be expressed as `ID` (the rows the eager path draws unselectable) — the
    /// caller then falls back to eager extraction. A row's own `.tag(_:)` is
    /// preferred, then element-natural ids, with the row index as the fallback
    /// (matching ``ListRowExtractor/extractListRows``). Only a row type that
    /// can be carrying a tag is built to be asked for one.
    ///
    /// - Parameter rowsPerElement: ``listRowsPerElement``, asked once by the
    ///   caller for every row it asks about — it is a property of the row
    ///   type, and asking it again for each row cost a conformance test a row.
    func listRowID<ID: Hashable>(at index: Int, rowsPerElement: Int) -> ID?

    /// Builds the deferred content for the row at `index` (0-based over the
    /// rows). Only called for rows that are actually shown.
    ///
    /// - Parameter rowsPerElement: ``listRowsPerElement``, asked once by the
    ///   caller, as for ``listRowID(at:rowsPerElement:)``.
    func makeListRowContent(at index: Int, rowsPerElement: Int, context: RenderContext) -> LazyListRowContent

    /// The rows' data, boxed for comparison, when it can be compared — what
    /// the hug memo checks the widest-row answer against (see
    /// `_ListCore.widestRowWidth`). `nil` means the answer cannot be kept.
    var listRowsSignature: AnyEquatableBox? { get }

    /// Whether each "row" here is itself a `Section`, and so contributes a
    /// header, its own items and a footer rather than one row.
    ///
    /// `List` asks before taking the windowed path, because that path's whole
    /// premise — one row per element, keyed by the element's id — is the wrong
    /// shape for `ForEach(regions) { Section { ForEach($0.seas) … } }`: it made
    /// each region ONE row and wrote a region's id into a binding the app looks
    /// up among seas. Both ids being `UUID`, that compiled and was silently
    /// wrong.
    ///
    /// Answered from the row TYPE, never by building a row, so a 50,000-row
    /// flat `List` pays one `is` check and keeps its windowed path — the same
    /// trick `viewTypeCarriesBadge(_:)` plays for `.badge(_:)`. A view of the
    /// app's own whose body is a `Section` is seen, from its types
    /// (`isSectionRowType(_:)`); a `Section` reached only through a `Group`
    /// or an `if`/`else` is not, exactly as a badge under one is not.
    var listRowsAreSections: Bool { get }

    /// How many list rows each element makes — one for a row of one view, the
    /// row's views for a row of several (`Group { a; b }`, decisions B15) — or
    /// `nil` when that depends on each element, and the list reads the rows
    /// from the child walk instead.
    var listRowsPerElement: Int? { get }
}

// MARK: - Seeing Through a Group or an if/else

/// A view that stands between a `List` (or a `Section`) and its rows without
/// being any part of them — it contributes its content's rows and none of its
/// own — so the list asks its questions of the content instead: what the rows
/// are, which selection value each one answers to, and which `ForEach` owns
/// them for `.onDelete`, `.onMove` and `dropDestination(for:action:)`.
///
/// `Group` and an `if`/`else` (`ConditionalView`) are the conformers, and
/// SwiftUI looks through both the same way: either one around the `ForEach` of
/// a `List`, or of one of its `Section`s, leaves every row deletable, and
/// deleting one removes the element that row draws. Asked of the wrapper
/// itself, every one of those questions stopped there. The rows came from the
/// flattening child walk instead, which cannot say which loop made a row, so
/// they were keyed by position rather than by element — answering to no
/// `String` or `UUID` selection at all — and no `.onDelete` or `.onMove`
/// reached any of them.
///
/// The wrappers come off ONCE, in the walk that extracts the rows, and every
/// later question is asked of the view that walk landed on — `_ListCore`'s
/// `RowSource.rowsContent`, a `Section`'s ``SectionContentRows`` — so the
/// rows and the actions they are edited by cannot have looked through two
/// different sets of wrappers.
///
/// A lone `if` needs no conformance HERE. `as?` looks through an `Optional`'s
/// `some` by itself — a rule of the language, not of anything written here —
/// which is why an `if` around the loop always worked where a `Group` did not.
/// The walk that decides from a view's TYPE whether its body is rows asks of a
/// type, not a value, and has no `some` to look through: it needs
/// `ListRowsOptional`.
///
/// NOT conformers, and not by oversight:
/// - A modifier, even a cosmetic one. `.foregroundStyle(.red)` written after
///   `.onDelete` has to reach each row, which only the child walk does, so the
///   rows still come from there and still cannot be attributed; an action found
///   by looking through the modifier would be handed offsets it cannot be
///   matched to, the guess `ListUnownedEditActionTests` refuses.
/// - `AnyView`, which draws its content only after telling the render cache
///   what type it erased (`AnyView.contentContext(noting:)`). It is a hole of
///   its own, and a larger one: no container sees through an `AnyView`, so
///   `List { AnyView(ForEach(…)) }` draws the whole loop as ONE row.
///
/// A view of the app's own whose `body` is rows is looked through as well, but
/// not as a conformer: its rows are its body's, which only an evaluation —
/// with its `@State` bound — can produce. See ``listRowsBody(of:context:)``.
@MainActor
package protocol ListRowsPassThrough {
    /// The view whose rows these are.
    var listRowsContent: any View { get }

    /// The context ``listRowsContent``'s rows are extracted under: the one the
    /// list is extracting under, plus whatever identity step the child walk
    /// would have taken on the way through this wrapper — so looking through it
    /// moves no row's `@State`. Only an `if`/`else` takes one.
    func listRowsContext(_ context: RenderContext) -> RenderContext

    /// Does what rendering the wrapper would have done on the way through,
    /// beyond the identity step — called once where the list takes it off,
    /// with the wrapper's own context. Only an `if`/`else` does anything.
    func noteLookedThrough(in context: RenderContext)

    /// Every type ``listRowsContent`` can be — a `Group`'s content, both arms
    /// of an `if`/`else` — for the walk that decides from a view's TYPE
    /// whether its body is list rows (``viewTypeHoldsListRowsInBody(_:)``).
    static var listRowsContentTypes: [any View.Type] { get }
}

extension ListRowsPassThrough {
    /// No step: the wrapper renders its content at its own identity.
    package func listRowsContext(_ context: RenderContext) -> RenderContext { context }

    /// Nothing: a `Group` does nothing on the way through.
    package func noteLookedThrough(in context: RenderContext) {}
}

// An `if`/`else` contributes its live arm's rows, and one thing more: the
// branch step `resolveChildViews` gives every one of them, which is what keeps
// two arms that loop over the same ids from sharing a row's `@State`. The label
// is `identityBranchLabel`'s own, so the step taken here cannot drift from the
// one the walk takes.
@MainActor extension ConditionalView: ListRowsPassThrough {
    package var listRowsContent: any View {
        switch self {
        case .trueContent(let content): content
        case .falseContent(let content): content
        }
    }

    package func listRowsContext(_ context: RenderContext) -> RenderContext {
        identityBranchLabel.map { context.withBranchIdentity($0) } ?? context
    }

    /// Records which arm is live, and drops the other arm's `@State` when it
    /// flipped — what `renderToBuffer` does, which a list looking through the
    /// conditional never calls. Without it the arm a flip left kept its
    /// state: every identity under a list is retained, so an expanded row
    /// came back expanded after a flip away and back, where a conditional
    /// drawn any other way starts it afresh, as SwiftUI does.
    package func noteLookedThrough(in context: RenderContext) {
        guard let label = identityBranchLabel else { return }
        noteConditionalArm(label, in: context)
    }

    package static var listRowsContentTypes: [any View.Type] { [TrueContent.self, FalseContent.self] }
}

// MARK: - ForEach Conformance

@MainActor extension ForEach: ListRowExtractor, WindowedListRowExtractor where Content: View {
    package func extractListRows<RowID: Hashable>(context: RenderContext) -> [ListRow<RowID>] {
        // The row type's shape, once for every row: asked of each, it was a
        // conformance test per row of every section's loop, every frame. A
        // loop of `EmptyView` rows makes none (`.none`), as `listRowCount`
        // counts it: an empty row here was an invisible one the cursor
        // stopped on, and Space selected.
        let perElement = listRowsPerElement ?? 1
        guard perElement > 0 else { return [] }
        return (0..<data.count * perElement).map { index -> ListRow<RowID> in
            // Resolve the row's selection ID up front — it's cheap (a key-path
            // read or the index) and the scroll / selection handler needs it for
            // EVERY row, on- or off-screen. Building and rendering the row view,
            // by contrast, is deferred into the lazy box below so a long List
            // only pays for the rows in its visible window.
            //
            // A row whose id the selection cannot hold is drawn unselectable,
            // as a static row without a usable tag is (see `ListRow.id`) and as
            // SwiftUI draws it — `Int` ids in a `String`-selection list. It used
            // to be dropped, which showed a section of them as its bare header
            // and a list of nothing else as the empty placeholder.
            ListRow(
                id: rowID(at: index, rowsPerElement: perElement),
                content: makeListRowContent(at: index, rowsPerElement: perElement, context: context))
        }
    }

    /// The rows of a loop whose rows have a count (``listRowsPerElement``):
    /// one whose rows vary is read through the child walk, which builds them,
    /// and never asks.
    package var listRowCount: Int { data.count * (listRowsPerElement ?? 1) }

    /// The row type's shape in a walk that keeps sections whole, as a list's
    /// does: a section row is one (and read as a section), a row of several
    /// views is that many, and a row whose count only it knows is `nil`.
    package var listRowsPerElement: Int? { rowShape(sectionWholeness: .all).childrenPerElement }

    // `RowID`, not `ID` — `ForEach`'s own `ID` generic parameter is in scope here.
    // Resolves one row's id lazily (the windowed `List` asks only for the visible
    // window + the focused row). `nil` when the element's id can't be expressed
    // as `RowID` — exactly the row `extractListRows` draws unselectable; the
    // list probes row 0 and bails to the eager path when it's `nil`.
    package func listRowID<RowID: Hashable>(at index: Int, rowsPerElement: Int) -> RowID? {
        rowID(at: index, rowsPerElement: rowsPerElement)
    }

    /// The collection itself, when its elements can be compared: a `Range`,
    /// or an `Array` of `Equatable` elements. Boxed without copying.
    package var listRowsSignature: AnyEquatableBox? {
        (data as? any Equatable).map { AnyEquatableBox($0) }
    }

    // A static property of the row type — no element is built to answer it —
    // and a row of the app's own whose body is a section is one too
    // (`isSectionRowType(_:)`), handed over as that section by the walk.
    package var listRowsAreSections: Bool {
        Content.self is any SectionRowExtractor.Type || isSectionRowType(Content.self)
    }

    package func makeListRowContent(at index: Int, rowsPerElement: Int, context: RenderContext) -> LazyListRowContent {
        // One of a row of several views: a list row of its own, as SwiftUI's
        // (decisions B15).
        if rowsPerElement > 1 {
            return makeMemberListRowContent(at: index, perElement: rowsPerElement, context: context)
        }
        let element = self.element(at: index)
        // Which row of the enclosing LIST this element draws — the element's
        // own offset plus wherever this `ForEach`'s first element sits. The two
        // are the same number in a flat `List { ForEach … }` and differ inside
        // a `Section` by its header and every earlier section's rows. Read here
        // rather than in the thunk below because a Section's boxes are built
        // during that Section's extraction, which is the only moment the base
        // names THIS ForEach (see ``RowEditRestrictions/rowIndexBase``).
        let listRowIndex =
            (context.environment.listRowEditRestrictions?.rowIndexBase ?? 0) + index
        // A per-row child identity (matching ForEach.childViews) so each row's
        // @State / focus / cache entry is distinct — and keyed by the element's
        // ID, not its position, so the row's state follows the element across
        // reorders/insertions (and across List scrolling, where the window's
        // indices shift).
        //
        // Built HERE rather than inside the closure so the box can carry it: a
        // `List` needs to know a row's identity to recognise it as the source of
        // a `.draggable` drag, and that question is asked of rows whose content
        // has not been rendered. It costs nothing extra — a box is only built
        // for a row that is about to be shown, and every such row renders.
        let rowContext = context.withChildIdentity(
            erasedType: Content.self,
            key: identityKey(elementID(of: element)))
        // Defer view construction, badge extraction, and rendering until the row
        // enters the visible window (see ``LazyListRowContent``).
        let box = LazyListRowContent(
            identity: rowContext.identity,
            carriesBadge: viewTypeCarriesBadge(Content.self),
            // The row's size without rendering it — what a `List` placing a
            // ramp asks its first row, and what a hugging `List` asks EVERY
            // row, every frame. Through `_MemoizedRow` for an Equatable
            // element, so the answer comes from the size memo keyed by the
            // element from the second frame on; the entry is marked alive here
            // because `_MemoizedRow.sizeThatFits` deliberately marks nothing
            // (a giant eager tree measures rows it will never draw) and a hug
            // over rows nobody draws would otherwise rebuild its answer every
            // frame. Bounded by the rows the hug asks about, not the tree.
            measure: { [content] in
                let proposal = ProposedSize(width: rowContext.availableWidth, height: nil)
                let size: ViewSize
                if let equatableElement = element as? any Equatable {
                    rowContext.renderCache?.markActive(rowContext.identity)
                    size = Self.measureMemoizedRow(
                        keyedBy: equatableElement, element: element, build: content,
                        proposal: proposal, context: rowContext)
                } else {
                    size = measureChild(content(element), proposal: proposal, context: rowContext)
                }
                return (size, rowContext.availableWidth)
            },
            render: { [content] placement, prominence in
                // Where this row sits in a ramp spanning the whole list (`nil`
                // unless one is in force). Applied HERE because the render is
                // here, and the colour is decided by the render it is about to
                // run.
                var rowContext = rowContext
                rowContext.gradientFrame = placement ?? rowContext.gradientFrame
                // The focused, selected row's raised background. Written
                // straight in rather than through a modifier: the list clears
                // this row's cached renders whenever its prominence changes
                // (`_ListCore.raiseBackgroundProminence`), which is what an
                // environment modifier's note would otherwise do.
                if prominence != .standard { rowContext.environment.backgroundProminence = prominence }
                // Which row of the LIST this is, for anything inside it that
                // needs to name itself to that list — `deleteDisabled` /
                // `moveDisabled` / `selectionDisabled`, all of which the
                // handler looks up by list row. Stamped on the (per-List, per-frame) collector
                // rather than into the environment: an environment write is a
                // copy of its whole storage dictionary, and it ran once per
                // visible row per frame (see `RowEditRestrictions.currentRowIndex`
                // for the full reasoning). Stamped INSIDE the thunk, immediately
                // before the render that might report against it, and cleared
                // after it, as the eager paths clear it, so what draws next
                // outside a row reports against none.
                context.environment.listRowEditRestrictions?.currentRowIndex = listRowIndex
                defer { context.environment.listRowEditRestrictions?.currentRowIndex = nil }
                // When the element is Equatable, wrap the row in a value-memo keyed
                // by the element, so an unchanged row is served from the render cache
                // instead of re-rendered. The wrapper is Renderable (adds no child
                // identity), so the inner view keeps the same `rowContext` identity
                // it would have unwrapped — the memo is identity-transparent.
                // _MemoizedRow's own gate declines to cache interactive / volatile rows.
                if let equatableElement = element as? any Equatable {
                    // The row view is NOT built here (see `ForEach.makeChild`, which
                    // learned this first): `_MemoizedRow` takes the element and the
                    // content closure and builds the row only if the memo misses —
                    // in steady state, it mostly does not, and building the view
                    // anyway priced every List frame in row views the next cache
                    // hit discarded. The badge is the one thing read off the BUILT
                    // view every frame, so rows whose static type cannot carry one
                    // — all but a `.badge(_:)`-outermost row, or one with only
                    // environment writes around it — skip that build too.
                    let badge: ListRowBadge? =
                        viewTypeCarriesBadge(Content.self)
                        ? extractListRowBadge(from: content(element)) : nil
                    let buffer = Self.renderMemoizedRow(
                        keyedBy: equatableElement, element: element, build: content, context: rowContext)
                    Self.reportSeparatorGuides(
                        build: content, element: element, buffer: buffer, row: listRowIndex, context: rowContext)
                    return (buffer, badge)
                }
                // Non-equatable elements cannot memoize, so the view is built for
                // the render regardless; the badge peek reuses it.
                let view = content(element)
                let buffer = TUIView.renderToBuffer(view, context: rowContext)
                Self.reportSeparatorGuides(
                    build: { _ in view }, element: element, buffer: buffer, row: listRowIndex, context: rowContext)
                return (buffer, extractListRowBadge(from: view))
            })
        // The row's type-select text, asked only when the user types to find a
        // row: its stated equivalent, else its first line drawn as a measure,
        // which registers nothing — the row may be far out of sight.
        box.typeSelectProbe = { [content] in
            let view = content(element)
            if let stated = statedTypeSelectEquivalent(of: view), let stated { return stated }
            var probe = rowContext
            probe.isMeasuring = true
            return TUIView.renderToBuffer(view, context: probe).lines.first.map {
                $0.stripped.trimmingCharacters(in: .whitespaces)
            }
        }
        return box
    }

    /// `element`'s row, memoised by `rowKey` — the element opened from its
    /// `any Equatable`, so the memo's key is the element's own type — and
    /// measured. See `ForEach.memoizedChild(keyedBy:element:key:)` for why.
    private static func measureMemoizedRow<RowKey: Equatable>(
        keyedBy rowKey: RowKey, element: Data.Element, build: @escaping (Data.Element) -> Content,
        proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        measureChild(_MemoizedRow(element: rowKey, source: element, build: build), proposal: proposal, context: context)
    }

    /// ``measureMemoizedRow(keyedBy:element:build:proposal:context:)``'s twin
    /// for the render.
    private static func renderMemoizedRow<RowKey: Equatable>(
        keyedBy rowKey: RowKey, element: Data.Element, build: @escaping (Data.Element) -> Content,
        context: RenderContext
    ) -> FrameBuffer {
        TUIView.renderToBuffer(_MemoizedRow(element: rowKey, source: element, build: build), context: context)
    }

    /// The element at a 0-based offset (O(1) — `Data` is `RandomAccessCollection`).
    private func element(at index: Int) -> Data.Element {
        data[data.index(data.startIndex, offsetBy: index)]
    }

    /// Resolves the row ID for the element at `index`: the row's own
    /// `.tag(_:)` first, then the element's natural ID when that matches the
    /// requested type, then the index (see ``extractListRows`` for why the
    /// index fallback matters), else `nil`.
    ///
    /// The tag comes first because SwiftUI calls the id-tag a *default*:
    /// `ForEach` "automatically assigns a tag to the selection views using
    /// each option's `id`", and `tag(_:)`'s own documentation offers that as
    /// the reason you may "omit the explicit tag modifier". Apple works the
    /// example end to end for a `Picker` — a row of `ForEach(Flavor.allCases)`
    /// carrying `.tag(flavor.suggestedTopping)` binds the TOPPING — and that
    /// is the same precedence ``staticListRowID(of:ordinal:as:)`` already
    /// applies against a static row's ordinal, and the same one a `Picker`
    /// applies, reading a member's ``ContainerValues/tag(for:)``, where an
    /// explicit tag outranks the element's id. One rule for both containers,
    /// in both of their row shapes.
    ///
    /// This is the SELECTION value only. The row's identity is still the
    /// element's `id` — the `@State`, focus and render-cache key in
    /// ``makeListRowContent(at:rowsPerElement:context:)``, and the key a
    /// `ScrollViewProxy.scrollTo(_:)` seeks by — so a tag moves what the
    /// binding receives and moves nothing else.
    ///
    /// ``viewTypeCarriesTag(_:)`` gates the build: the tag can only be read
    /// off a BUILT row, and this is asked for every row of the visible window
    /// on every frame, so a row type that cannot carry one pays a cached `is`
    /// check and keeps its bare key-path read.
    private func rowID<RowID: Hashable>(at index: Int, rowsPerElement: Int) -> RowID? {
        // A row of several views is several list rows, each naming itself by
        // its element, as SwiftUI tags each (decisions B15).
        let elementIndex = index / max(1, rowsPerElement)
        return selectionID(of: element(at: elementIndex)) ?? (elementIndex as? RowID)
    }

    /// The list row for view `index % perElement` of element
    /// `index / perElement`'s row of several: drawn as a container draws that
    /// view, at the identity it has there, with what a list asks of any row —
    /// its size, its badge, where it sits in a ramp, its raised background
    /// when focused and selected, its type-select text.
    private func makeMemberListRowContent(
        at index: Int, perElement: Int, context: RenderContext
    ) -> LazyListRowContent {
        deferredListRow(
            of: rowMember(index % perElement, of: element(at: index / perElement), context: context),
            listRow: (context.environment.listRowEditRestrictions?.rowIndexBase ?? 0) + index, context: context)
    }

    /// The selection value `element`'s row names itself by: its own
    /// `.tag(_:)`, else the element's id — ``rowID(at:rowsPerElement:)`` without the index
    /// fallback, which is a position in THIS collection rather than anything
    /// the row says about itself.
    private func selectionID<RowID: Hashable>(of element: Data.Element) -> RowID? {
        if viewTypeCarriesTag(Content.self),
            let tagged: RowID = extractTagValue(from: content(element), as: RowID.self) {
            return tagged
        }
        return elementID(of: element) as? RowID
    }
}

// MARK: - ForEach's rows among other rows

@MainActor extension ForEach where Content: View {
    /// Reports the separator guides the row `build(element)` makes sets
    /// (``HorizontalAlignment/listRowSeparatorLeading``, `…Trailing`;
    /// decisions A47) against list row `row` — building the row only where
    /// `Content`'s type can hold a guide, so every other row is answered by one
    /// static check.
    static func reportSeparatorGuides(
        build: (Data.Element) -> Content, element: Data.Element, buffer: FrameBuffer, row: Int,
        context: RenderContext
    ) {
        guard Content._providesAlignmentGuide, !context.isMeasuring,
            let reports = context.environment.listRowEditRestrictions,
            let guides = listRowSeparatorGuides(of: build(element), size: (buffer.width, buffer.height), context: context)
        else { return }
        reports.reportSeparatorGuides(row: row, guides)
    }
}

@MainActor extension ForEach: KeyedRowProvider, KeyedLoop where Content: View {
    /// This loop's rows, as the flattening emits them: one child per element,
    /// the same number of each element's views (a row of several, decisions
    /// B15), or as many as each element's row makes — placed by their keys,
    /// which every one of them carries — in order; see ``FlattenedRowIDs``.
    package func appendKeyedRowRuns(to runs: inout KeyedRowRuns, sectionsWhole: Bool) {
        let shape = rowShape(sectionWholeness: sectionsWhole ? .all : .apart)
        guard shape != .none else { return }
        runs.append(.loop(self, rowsPerElement: shape.childrenPerElement))
    }

    package var keyedElementCount: Int { data.count }

    /// Keyed as `makeChild(for:)` keys the row's identity — the element's key,
    /// which each of a row's several views carries too.
    package func keyedRowKey(ofElement element: Int) -> String {
        identityKey(elementID(of: self.element(at: element)))
    }

    /// Through `selectionID(of:)`, so without `rowID(at:rowsPerElement:)`'s index
    /// fallback: a row whose element id is not the selection type is
    /// answered as such, so its container falls back to its own ordinal for it
    /// — the number it had before.
    package func keyedRowSelectionID<RowID: Hashable>(ofElement element: Int) -> RowID? {
        selectionID(of: self.element(at: element))
    }

    package func keyedRowElementID(ofElement element: Int) -> AnyHashable {
        AnyHashable(elementID(of: self.element(at: element)))
    }
}
