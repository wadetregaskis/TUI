//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Selection Mode

/// The selection mode for a list or table component.
public enum SelectionMode: Sendable {
    /// Single selection with optional binding (nil = no selection).
    case single

    /// Multi-selection with Set binding.
    case multi
}

// MARK: - Item List Handler

/// A reusable focus handler for list and table components.
///
/// `ItemListHandler` consolidates the navigation and selection logic shared by
/// `List` and `Table`. It handles:
/// - Focus registration with the focus manager
/// - Keyboard navigation (Up/Down/Home/End/PageUp/PageDown)
/// - Single and multi-selection modes
/// - Scroll offset management to keep the focused item visible
/// - Disabled state (prevents focus when disabled)
///
/// ## Usage
///
/// ```swift
/// // In List's renderToBuffer:
/// let handler = ItemListHandler(
///     focusID: focusID,
///     itemCount: items.count,
///     viewportHeight: visibleRows,
///     selectionMode: .single,
///     canBeFocused: !isDisabled
/// )
/// handler.singleSelection = singleSelectionBinding
/// focusManager.register(handler, inSection: sectionID)
/// ```
///
/// ## Navigation Keys
///
/// | Key | Action |
/// |-----|--------|
/// | Up | Move focus up (wrap to end) |
/// | Down | Move focus down (wrap to start) |
/// | Home | Jump to first item |
/// | End | Jump to last item |
/// | PageUp | Move up by viewport height |
/// | PageDown | Move down by viewport height |
/// | Enter/Space | Toggle selection at focused index |
///
/// Multi-selection (`Set`-bound) lists additionally follow the macOS
/// keyboard-selection model, adapted to what terminals can deliver:
///
/// | Key | Action |
/// |-----|--------|
/// | Shift+Up/Down/Home/End/PageUp/PageDown | Extend the selection from the anchor (where the terminal reports Shift — Terminal.app strips it from Up/Down) |
/// | Ctrl+V | Toggle extend mode: plain movement keys extend the selection, in ANY terminal |
/// | Ctrl+A | Select all |
///
/// A `Table` with a `sortOrder` binding adds Ctrl+S (sort by the next sortable
/// column, wrapping) and Ctrl+D (reverse the direction) — the keyboard route to
/// a header click.
///
/// Every chord above is rebindable — see ``RowShortcuts`` — and a reorderable
/// list adds Ctrl+R to pick the focused row up, after which the movement keys
/// move its landing slot and Return/Escape place it or put it back.
/// | Escape | Exit extend mode, else clear a non-empty selection; otherwise falls through (page navigation is never blocked) |
///
/// The module split (step C2): a table in TUITables drives this class, so
/// what the table reaches, and what witnesses the class's protocols, is
/// `package`. A class's stored property that another module can see keeps a
/// run-time exclusivity check on every access, its own module's included
/// (CONTRIBUTING.md, "Crossing a module boundary"), so such a property is
/// private storage under a `package` accessor, not `@inlinable`. Four are
/// `package` and stored: ``tableRowMemo`` and ``returningRows``, which a
/// table reads (and the first changes in place) for every row it draws, and
/// ``reorder`` and ``outlineActivation``. A release `Stress` already checked
/// every access to each before the step (d6bf4600d: `swift_beginAccess` at
/// the property's field offset, in this module's own functions), and the
/// optimiser decides per property, all or nothing, so widening them adds no
/// check where they are used, and both modules read them in place rather
/// than through a call. Each says so, with its count. Do not copy them for a
/// property with no such check. Nor, without measuring, for one with it: a
/// widened stored property also gets a getter, setter and `modify` of its
/// own, for its property descriptor, each with a check of its own (nothing
/// calls them, but they are code), while private storage under an accessor
/// is usually statically enforced. Of twelve such properties of this class
/// that step C2 tried both ways, ten lost every check; ``reorder`` and
/// ``outlineActivation`` kept theirs, in their accessors, which this module
/// then called where it had read them in place, so they are stored.
package final class ItemListHandler<SelectionValue: Hashable>: PersistedFocusable, ScrollableOffsetState {
    /// The unique identifier for this focusable element.
    package var focusID: String { get { _focusID } set { _focusID = newValue } }

    /// ``focusID``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _focusID: String

    /// ``PersistedFocusable``: answers to `focusID` from now on.
    package func repoint(focusID: String) { self.focusID = focusID }

    /// The total number of items in the list.
    ///
    /// Shrinking the count immediately re-bounds ``scrollOffset`` to the last
    /// item. This is the *viewport-independent* half of the scroll clamp, so
    /// it is safe on any pass — unlike ``clampScrollOffset()``, whose
    /// `maxOffset` depends on the offered viewport and is therefore gated to
    /// render passes by the owning views. Without it, a measure pass that
    /// syncs a freshly-shrunk count (rows removed by an async reload) leaves
    /// a scrolled-near-the-end offset pointing past the data, and range /
    /// `data[index]` math downstream traps.
    package var itemCount: Int { get { _itemCount } set { _itemCount = newValue } }

    /// ``itemCount``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _itemCount: Int {
        didSet {
            let bound = max(0, itemCount - 1)
            if scrollOffset > bound {
                scrollOffset = bound
            }
        }
    }

    /// The number of visible items in the viewport.
    ///
    /// Callers set this to the number of rows that are *actually*
    /// shown at the current ``scrollOffset`` — i.e. the content
    /// area minus a line for each scroll indicator that is present
    /// (see ``contentHeight``). Every ``ScrollableOffsetState``
    /// predicate (``hasContentBelow``, ``visibleRange``,
    /// ``rowsBelow``, ``maxOffset``) is derived from it, so keeping
    /// it equal to the rows on screen is what makes the indicators
    /// line up exactly with the content area.
    package var viewportHeight: Int { get { _viewportHeight } set { _viewportHeight = newValue } }

    /// ``viewportHeight``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _viewportHeight: Int

    /// How many rows a Shift-accelerated Up/Down moves the focus cursor. Set from
    /// `environment.shiftStepMultiplier` during render (default 5); a plain arrow
    /// moves one. See ``View/shiftStepMultiplier(_:)``.
    var shiftStepMultiplier: Int = 5

    /// What the scrollbar extent estimator worked out about these rows' heights,
    /// carried across frames while `signature` — a hash of everything that
    /// shapes row heights (row count, widths/limits, precision) — holds, and
    /// `rows`, the rows' data where every row's height is kept
    /// (``ScrollExtentEstimator/keepsEveryHeight(count:precision:)``) and the
    /// rows can be compared: an off-screen row that grew changes none of the
    /// signature's inputs, and its kept height placed the thumb for the row as
    /// it was. `nil` where the sample is kept, whose staleness only bends the
    /// middle of the travel, or where the rows cannot be compared.
    ///
    /// See ``ScrollExtentProfile`` for the contract. It spares the same 64 rows
    /// every frame under the approximate mode, and EVERY row under the exact one
    /// — each of which costs a wrap (a Table) or a row materialisation (a List)
    /// to ask.
    package var extentProfileCache: (signature: Int, rows: AnyEquatableBox?, profile: ScrollExtentProfile)? {
        get { _extentProfileCache }
        set { _extentProfileCache = newValue }
    }

    /// ``extentProfileCache``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _extentProfileCache: (signature: Int, rows: AnyEquatableBox?, profile: ScrollExtentProfile)?

    /// The vertical scrollbar a `List` drew last time, with everything it was
    /// drawn from — `ScrollViewHandler.verticalScrollbarMemo`'s twin, kept the
    /// same way (see `_ListCore.listScrollbarCells`). A list's bar neither
    /// pulses nor lifts, so it has no runs; but every one of its cells is a full
    /// SGR spelling, and it was drawn afresh on every frame for inputs that had
    /// not moved: 3.5% of a `kitchensink` frame.
    var verticalScrollbarMemo: ScrollbarMemo<ClaimingColumn>?

    /// How many times ``verticalScrollbarMemo`` answered — for the test that
    /// pins it answering.
    var verticalScrollbarMemoHits = 0

    /// When this list or table first drew, for a flash of its indicators on
    /// appearing (`scrollIndicatorsFlash`); stamped by ``syncFrameInputs``.
    package var indicatorFlash = ScrollIndicatorFlash()

    /// A `Table`'s composed row lines, kept across frames.
    ///
    /// Here, rather than in the render cache, for the reason `TableRowMemo.swift`
    /// gives at length: the cache drops everything beneath an identity whose
    /// state was written, which is the very frame a live table's data arrives
    /// on. This store is keyed on the row's own inputs instead, so it does not
    /// need the sweep to be correct — and a `List` does not use it, because a
    /// `List`'s rows are views whose closures can capture anything.
    ///
    /// `package` and stored, not under an accessor: every access to it is
    /// dynamically enforced already, at least 6 `swift_beginAccess` sites in a
    /// release `Stress` before step C2 (d6bf4600d; see this class's note on the
    /// module split). A table in TUITables asks and changes it for every row it
    /// draws, in place; under a getter and setter each change would copy the
    /// store's dictionary.
    package var tableRowMemo = TableRowMemoStore<SelectionValue>()

    /// The chord → action map this list's keys dispatch through, resolved from
    /// `environment.rowShortcuts` during render (see ``RowShortcuts``). Captured
    /// rather than read live: a key event arrives between renders, with no
    /// environment to consult.
    var shortcuts: RowShortcutLookup = .default

    /// What ``shortcuts`` was built from, so it is not built again from the same
    /// pair. Memoised for the reason ``extentProfileCache`` is: the inputs change
    /// almost never and the work is not free.
    ///
    /// `lookup` builds a fresh `Dictionary`, walks every ``RowAction`` twice
    /// (defaults, then overrides) and hashes some fifty chords — to produce a
    /// value that is identical for every list on the page and, for the vast
    /// majority of apps, never changes at all. It ran once per List/Table per
    /// PASS, and the measure pass counts: eight tables in a stack, each measured
    /// and then rendered, paid it sixteen times a frame.
    var shortcutsKey: ShortcutsKey?

    /// The pair ``shortcuts`` is a function of.
    struct ShortcutsKey: Equatable {
        let shortcuts: RowShortcuts
        let commandKey: CommandKeyBinding
    }

    /// The full height of the scrollable content area, in rows —
    /// the space available for visible rows *plus* whichever
    /// scroll indicators are showing.
    ///
    /// When set, ``ensureFocusedItemVisible()`` reserves room for
    /// the indicators so the focused row never lands on an
    /// indicator line. `nil` means the caller manages indicator
    /// reservation itself and ``viewportHeight`` is the literal
    /// visible-row count (the original behaviour, still used by the
    /// handler's own unit tests).
    package var contentHeight: Int? { get { _contentHeight } set { _contentHeight = newValue } }

    /// ``contentHeight``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _contentHeight: Int?

    /// Whether the owning view draws a scrollbar instead of the "N more
    /// above/below" text indicators.
    ///
    /// A scrollbar marks the off-screen rows in its own gutter column, so the
    /// rows fill the *whole* ``contentHeight`` — there is no reserved indicator
    /// line. The scroll-bound arithmetic (``maxOffset``,
    /// ``ensureFocusedItemVisible()``) otherwise reserves a line for an
    /// indicator that a scrollbar list never draws, which over-scrolls the
    /// bottom by one row and leaves a blank remainder (one blank line per
    /// row-height). With this set, that reservation is skipped.
    package var showsScrollbar: Bool { get { _showsScrollbar } set { _showsScrollbar = newValue } }

    /// ``showsScrollbar``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _showsScrollbar = false

    /// Whether the pointer is over the list: under
    /// `.scrollIndicatorPlacement(.overContent)` its indicators are drawn over
    /// the rows while it is.
    package var isPointerOver = false

    /// Whether this frame draws the scrollbar OVER the rows' last column
    /// (`.scrollIndicatorPlacement(.overContent)`, the pointer over the list):
    /// the rows were laid out at the whole width, and nothing in the layout
    /// reserves the bar.
    package var overlaysScrollbar = false

    /// Whether this frame writes the "N more" lines OVER the rows' first and
    /// last lines, as ``overlaysScrollbar`` draws the bar over their last column.
    package var overlaysTextIndicators = false

    /// Whether a drag hovering this control is drawing a landing slot that
    /// NOTHING left the control to make room for — so the rows plus the slot
    /// need one line more than the rows alone.
    ///
    /// True only for a drag that came from elsewhere. A reorder takes its rows
    /// out of the list before opening the slot, and a `.draggable` row of this
    /// list's own is dropped from the drawing for the same reason (see
    /// `_ListCore.decorateForReorder`) — both are one row out, one slot in, no
    /// net change. Set by the owning view every render, because only it knows
    /// where the drag started and whether a slot is open here at all.
    ///
    /// The line is granted as CONTENT, not as height: the control cannot grow
    /// mid-drag without shifting the page under the pointer. So an
    /// exactly-full list overflows by one, which is a state the scroll
    /// machinery already knows how to express — the "▼ N more below" indicator
    /// or the scrollbar appears, and ``maxOffset`` rises by one so the wheel,
    /// the mid-drag navigators and the edge auto-scroll can all reach the
    /// position after the last row. Without it the extent says the rows fit
    /// exactly, ``maxOffset`` is zero, nothing can scroll, and the slot's line
    /// is silently clipped off the bottom — taking a real row with it, and
    /// leaving "drop at the end" impossible to point at.
    ///
    /// Deliberately NOT folded into ``itemCount``: that is the DATA count, and
    /// every piece of reorder index arithmetic — ``reorderInsertionOffset``,
    /// the `externalDropSlot` clamp, the keyboard-move clamps — is defined
    /// against it. A phantom row there would let a drop name an index the data
    /// has no room for.
    package var dropSlotAddsRow: Bool { get { _dropSlotAddsRow } set { _dropSlotAddsRow = newValue } }

    /// ``dropSlotAddsRow``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _dropSlotAddsRow = false

    /// Whether this frame's render spends content lines on "▲/▼ N more"
    /// indicators. Synced by the owning view, because only it knows: a `List`
    /// swaps its indicators for a scrollbar, while a `Table` draws both (the bar
    /// takes a column, the indicators take lines). The reveal budgets rows
    /// against `contentHeight` MINUS these — see ``rowLineBudget``.
    package var drawsScrollIndicators: Bool { get { _drawsScrollIndicators } set { _drawsScrollIndicators = newValue } }

    /// ``drawsScrollIndicators``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _drawsScrollIndicators = true

    /// Whether a "▲/▼ N more" line comes out of the content area this frame.
    ///
    /// The two flags are set together by the views (a bar and the text lines
    /// are alternatives), but both have to be consulted: `showsScrollbar`
    /// alone was the old proxy for "spends no line", and it misses the case
    /// this cannot — indicators hidden outright, which spends nothing either.
    var reservesIndicatorLine: Bool { drawsScrollIndicators && !showsScrollbar }

    /// Whether BOTH "N more" lines come out of the content area at every offset,
    /// whatever is hidden — ``EnvironmentValues/alwaysShowsVerticalTextIndicators``.
    ///
    /// Synced by the owning view beside ``drawsScrollIndicators``, and consulted
    /// wherever a bound is worked out from the content height: the reservation
    /// stops depending on where the viewport is, which is the whole point of
    /// `.visible`, and every one of those bounds has to say so or the view can
    /// scroll a line past its own last row.
    package var alwaysReservesIndicatorLines: Bool { get { _alwaysReservesIndicatorLines } set { _alwaysReservesIndicatorLines = newValue } }

    /// ``alwaysReservesIndicatorLines``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _alwaysReservesIndicatorLines = false

    /// How many lines the "N more" chrome takes out of the content area.
    ///
    /// One number, so the several places that budget against the content height
    /// cannot each decide for themselves — under
    /// ``alwaysReservesIndicatorLines`` it is 2 at every offset, and otherwise it
    /// is at most 1 (the "above" line; the "below" one is discovered by filling,
    /// because whether rows remain past the window is what it depends on).
    var reservedIndicatorLines: Int {
        guard reservesIndicatorLine else { return 0 }
        return alwaysReservesIndicatorLines ? 2 : 1
    }

    /// A closure giving the height in lines of row `i`, for rows that can span
    /// multiple lines — `List` rows are arbitrary views and `Table` cells can
    /// wrap, so both wire this. `nil` (single-line tables, plus the handler's
    /// own unit tests) keeps the original uniform-height arithmetic. When set,
    /// ``ensureFocusedItemVisible()`` accumulates these so a tall focused row
    /// is fully revealed rather than partially scrolled off. It is a
    /// *closure*, not an array, so the owning view answers it lazily — only
    /// for the rows the scroll arithmetic actually touches (a viewport's
    /// worth, not every row) — which is what lets a tall table/list skip
    /// wrapping or rendering its off-screen rows.
    var rowHeight: ((Int) -> Int)?

    /// The section header pinned over the top of the rows when row `i` is the
    /// first drawn, and its height in lines — or `nil` where nothing pins
    /// there. Set every frame by a `List` whose style pins its headers
    /// (decisions A45), `nil` everywhere else. ``ensureFocusedItemVisible()``
    /// keeps the cursor below the header: the lines it covers are lines the
    /// cursor's row is not drawn on.
    var pinnedSectionHeader: ((Int) -> (index: Int, height: Int)?)?

    /// How eagerly the viewport follows the focus cursor — synced from the
    /// environment each render (see ``ScrollFollowMargin``). With the default
    /// `.none`, ``ensureFocusedItemVisible()`` scrolls only when the cursor
    /// reaches a viewport edge; a margin starts the scroll early so that many
    /// lines/rows of context stay visible beyond the cursor.
    var followMargin: ScrollFollowMargin = .none

    /// How many DRAWABLE entries the row area holds this frame.
    ///
    /// ``viewportHeight`` counts ROWS, and the owning view has already taken
    /// the landing slot's line out of it (`contentHeight - dropSlotAddsRow`).
    /// ``extent`` counts ENTRIES, and has already added that same line in. A
    /// bound taken as `extent - viewportHeight` therefore counts one line
    /// twice, in opposite directions, and lands one offset past the end: the
    /// window there holds a row fewer than the area has lines for, so the
    /// frame draws the slot AND a blank the rows should have filled — the
    /// "two blank lines, one of them nowhere near the pointer" report. Adding
    /// the line back here is what makes the two sides speak the same units.
    var viewportEntries: Int { viewportHeight + (dropSlotAddsRow ? 1 : 0) }

    /// The largest valid scroll offset, in rows, **as it applies to where the
    /// viewport currently sits** — see ``resolvedMaxOffset(reaching:)``, which
    /// this asks with ``scrollOffset``. A mover that wants to go somewhere else
    /// must ask about *that* offset, or it will be clamped by a bound computed
    /// for the position it is leaving.
    package var maxOffset: Int { resolvedMaxOffset(reaching: scrollOffset) }

    /// The largest valid scroll offset, in rows, resolved precisely enough to
    /// clamp `offset`.
    ///
    /// With variable-height rows (``rowHeight`` set) the default
    /// `extent - viewportHeight` mixes units — the extent is rows but the
    /// provisional viewport is lines — capping the offset short of the true
    /// bottom (and letting the render-pass clamp scrub back a reveal that had
    /// correctly scrolled a tall focused row into view). Walk back from the
    /// last row instead, accumulating real heights: the answer is the
    /// smallest top row for which everything below fits the content area
    /// (reserving the "above" indicator's line whenever that top isn't row
    /// zero). O(viewport) closure calls, on rows the frame renders anyway.
    ///
    /// The walk is skipped for an `offset` that cannot reach the tail, which is
    /// why this takes a parameter at all: materialising tail rows' heights is
    /// the expensive part on a large lazy list, and an offset short of the
    /// cheap floor below is clamped by neither bound, so which one it is
    /// cannot matter. Asking about the WRONG offset is a real bug, though —
    /// the floor is a strict UNDER-estimate whenever an indicator line is
    /// reserved, so a jump that clamps against it lands a row short of the
    /// bottom and needs a second press to arrive. That is what
    /// ``settledMaxOffset`` and the `offset`-driven clamps exist to prevent.
    package func resolvedMaxOffset(reaching offset: Int) -> Int {
        guard let contentHeight, contentHeight > 0, rowHeight != nil else {
            return max(0, extent - viewportEntries)
        }
        // Every row is at least one line, so at most `contentHeight` rows fit:
        // the true bound is never below this floor, and an offset short of it
        // is inside every candidate answer. Landing exactly ON the floor does
        // need the walk, though — `maxOffset` asks about ``scrollOffset``, and
        // "am I at the bottom?" is answerable only by the exact bound.
        let floor = max(0, extent - contentHeight)
        guard offset >= floor else { return floor }
        return bottomWalk()?.top ?? floor
    }

    /// The walk both bottom bounds share: the smallest top row for which
    /// everything below it fits the content area, how many lines of the budget
    /// that leaves UNUSED, and the height of the row that would not fit.
    ///
    /// The shortfall is the interesting part, and it is why this answers three
    /// things rather than one. Nothing forces a suffix of the row heights to sum
    /// to the budget: three-line rows in a sixteen-line budget make the last
    /// whole-row screenful fifteen lines, and the sixteenth is blank — see
    /// ``fillBottomShortfall()``, which is what spends it.
    ///
    /// The budget the shortfall is measured against is the ACCEPTED top's, never
    /// the candidate the walk rejected — the local `budget(forTop:)` is asked
    /// about a named top for exactly that reason.
    ///
    /// `nil` when there are no row heights to walk (a single-line `Table`, the
    /// handler's own unit tests); the bound is arithmetic there.
    func bottomWalk() -> (top: Int, shortfall: Int, straddlingHeight: Int)? {
        guard let rowHeight, let contentHeight, contentHeight > 0 else { return nil }
        // Reserve the "above" indicator's line only when there IS one — a
        // scrollbar draws no such line and hidden indicators draw nothing at
        // all, so in both cases the rows fill the full height.
        // Under `always` both lines are there at every offset, including at
        // the bottom this walk is finding and at row 0 — so the budget is a
        // constant rather than a question about where the top lands.
        //
        // Asked about a top rather than carried in a running variable, because
        // the two askers mean different tops: the fit test asks about the
        // CANDIDATE (`top - 1`, the row it is trying to admit) and the shortfall
        // about the ACCEPTED one. They differ by a line exactly when the walk
        // stops at top 1 — row 0 did not fit, so the "▲ N more above" line stays
        // and the rows keep only `contentHeight - 1`. Reporting the candidate's
        // budget there made the shortfall a line too large, and
        // ``fillBottomShortfall()`` then clipped a line too FEW off the row it
        // backs up to: the destination overfilled its budget by one, the last row
        // lost its last line, and the window had reached `count` so no
        // "▼ N more below" was drawn to say so.
        func budget(forTop topRow: Int) -> Int {
            alwaysReservesIndicatorLines
                ? max(1, contentHeight - 2)
                : ((!reservesIndicatorLine || topRow == 0) ? contentHeight : contentHeight - 1)
        }
        var used = 0
        var top = extent
        var straddling = 0
        while top > 0 {
            // The row a hovering drag borrows (``dropSlotAddsRow``) sits past
            // the last real one and has no data to measure: it is the slot,
            // one blank line. Asking `rowHeight` for it indexes past the data.
            let height = top - 1 < itemCount ? max(1, rowHeight(top - 1)) : 1
            if used + height > budget(forTop: top - 1) {
                straddling = height
                break
            }
            used += height
            top -= 1
        }
        return (top, max(0, budget(forTop: top) - used), straddling)
    }

    /// The row-activation action — the `primaryAction` of an enclosing
    /// `contextMenu(forSelectionType:menu:primaryAction:)`, or an outline's
    /// disclosure — invoked with the activated row's id on Return/Enter (the
    /// cursor row), and by the owning view on double-click (the clicked row,
    /// with the cursor moved there first). When set, Enter ACTIVATES instead
    /// of toggling selection — Space still toggles — matching the
    /// file-browser convention (and AppKit's action/doubleAction split). `nil`
    /// keeps the original behaviour: Enter and Space both toggle selection.
    package var primaryAction: ((SelectionValue) -> Void)? { get { _primaryAction } set { _primaryAction = newValue } }

    /// ``primaryAction``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _primaryAction: ((SelectionValue) -> Void)?

    /// A parked ``ScrollViewProxy/scrollTo(_:anchor:)`` request, which the
    /// list's or table's next render resolves against its rows
    /// (``scroll(toRow:anchor:)``) — see ``ScrollToTarget``.
    package var pendingScrollTo: ScrollToRequest? {
        get { _pendingScrollTo }
        set { _pendingScrollTo = newValue }
    }

    /// ``pendingScrollTo``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _pendingScrollTo: ScrollToRequest?

    /// What this list keeps of a `.scrollPosition` bound above it: the request
    /// it acted on and the row it last reported (``applyScrollPosition(rowIndex:context:)``).
    var positionTracking = ScrollPositionTracking()

    /// Whether the user has scrolled the list since its last render — the
    /// wheel, the keys, the scrollbar — for a bound `.scrollPosition` to be
    /// told so (``reportScrollPosition(rowID:context:)``).
    var userScrolledSinceRender = false

    /// The collapsed `NavigationSplitView`'s way to its next column, where
    /// this list is in the column on top of one
    /// (``EnvironmentValues/compactColumnAdvance``): choosing a row selects it
    /// and shows the next column, as tapping a row does on iPhone. Set by the
    /// list or table every frame from its environment.
    package var compactColumnAdvance: CompactColumnAdvance? {
        get { _compactColumnAdvance }
        set { _compactColumnAdvance = newValue }
    }

    /// ``compactColumnAdvance``'s storage: private, under the `package`
    /// accessor (CONTRIBUTING.md, "Crossing a module boundary").
    private var _compactColumnAdvance: CompactColumnAdvance?

    /// What → does on the cursor row of a list that is not a tree
    /// (``EnvironmentValues/listRowForwardAction``): a file panel's column
    /// opens the folder there. Set by the list or table every frame from its
    /// environment.
    package var rowForwardAction: ListRowForwardAction? {
        get { _rowForwardAction }
        set { _rowForwardAction = newValue }
    }

    /// ``rowForwardAction``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _rowForwardAction: ListRowForwardAction?

    /// Opens the container's row menu on the cursor row — Shift+F10 or the
    /// Menu key (``KeyEvent/opensContextMenu``) — and answers whether one
    /// opened. `nil` where the container has no menu, so the key falls
    /// through.
    package var openContextMenu: (() -> Bool)? { get { _openContextMenu } set { _openContextMenu = newValue } }

    /// Whether the focus is leaving for the cursor row's own context menu,
    /// which hands it back when it closes: then the cursor stays on that row
    /// rather than going to the selection (``onFocusLost()``). Set by the
    /// list's Shift+F10 as it opens the menu, and spent by the loss.
    package var focusLeavesForRowMenu = false

    /// The cursor row's swipe actions while they are revealed, and the edge
    /// revealed — `nil` while none are. Set by the swipe keys
    /// (``RowAction/revealLeadingSwipeActions``), cleared by the revealed
    /// actions as they slide away, and good only while the cursor stays on
    /// that row.
    package var revealedSwipe: (row: Int, edge: HorizontalEdge)? {
        get { _revealedSwipe }
        set { _revealedSwipe = newValue }
    }
    private var _revealedSwipe: (row: Int, edge: HorizontalEdge)?

    /// Each row's swipe actions, by edge, as its rows reported them
    /// (`RowEditRestrictions.swipeEdges`): what the swipe keys can reveal.
    package var swipeEdges: [Int: [HorizontalEdge: Bool]] { get { _swipeEdges } set { _swipeEdges = newValue } }
    private var _swipeEdges: [Int: [HorizontalEdge: Bool]] = [:]

    /// The row drawn with its actions revealed, by identity: when the reveal
    /// moves, the list drops that row's cached render and the new one's.
    package var swipeRevealedRowIdentity: ViewIdentity? {
        get { _swipeRevealedRowIdentity }
        set { _swipeRevealedRowIdentity = newValue }
    }
    private var _swipeRevealedRowIdentity: ViewIdentity?

    /// The horizontal wheel's swipe in progress (`handleSwipeWheel`).
    package var swipeWheel: SwipeWheelState { get { _swipeWheel } set { _swipeWheel = newValue } }
    private var _swipeWheel = SwipeWheelState()

    /// Presses the revealed actions' first, as the revealed row reported it
    /// (`RowEditRestrictions.swipeFullSwipe`): the wheel's full swipe. `nil`
    /// while none are revealed.
    package var swipeFullSwipe: (@MainActor () -> Void)? { get { _swipeFullSwipe } set { _swipeFullSwipe = newValue } }
    private var _swipeFullSwipe: (@MainActor () -> Void)?

    /// ``openContextMenu``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _openContextMenu: (() -> Bool)?

    /// What a `Table`'s column keys reach — set each frame by a table with a
    /// header, `nil` for a `List` and a table without one. See
    /// ``TableColumnEditing``.
    package var columnEditing: TableColumnEditing? { get { _columnEditing } set { _columnEditing = newValue } }

    /// ``columnEditing``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _columnEditing: TableColumnEditing?

    /// Where a `Table`'s header drew each column on the last frame, by its
    /// customization identifier and its place among the declared columns —
    /// what a header drag that began on an earlier frame lays the columns out
    /// from, and what the column keys measure a width from. The last frame's
    /// only: a move or a resize earlier in the same batch of input has changed
    /// the customization and not this, so a reader lays the columns out again
    /// from the customization (the table's `liveHeaderColumns`).
    package var headerColumns: [(id: String?, declaration: Int, x: Range<Int>)] { get { _headerColumns } set { _headerColumns = newValue } }

    /// ``headerColumns``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _headerColumns: [(id: String?, declaration: Int, x: Range<Int>)] = []

    /// The widest a `Table`'s column may be made, on the last frame: its row
    /// content's width.
    package var headerColumnsWidest: Int { get { _headerColumnsWidest } set { _headerColumnsWidest = newValue } }

    /// ``headerColumnsWidest``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _headerColumnsWidest = 1

    /// The widths a user gave a `Table`'s columns where no customization
    /// records them — a table with no customization binding, or a column with
    /// no identifier — by the table's column key (its identifier, else its
    /// place among the declared columns). The table's own state, as SwiftUI
    /// keeps them in its outline view (decisions B-D4T-7): for as long as the
    /// table is shown, and gone with it.
    package var transientColumnWidths: [String: Int] {
        get { _transientColumnWidths }
        set { _transientColumnWidths = newValue }
    }

    /// ``transientColumnWidths``'s storage: private, under the `package`
    /// accessor (CONTRIBUTING.md, "Crossing a module boundary").
    private var _transientColumnWidths: [String: Int] = [:]

    /// The column picked for the keyboard's customization (``RowAction/customizeColumns``),
    /// by identifier, or `nil` when none is. Persisted with the handler, and
    /// let go with the focus.
    package var columnFocus: String? { get { _columnFocus } set { _columnFocus = newValue } }

    /// ``columnFocus``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _columnFocus: String?

    /// The tree inside this list, when there is one — see
    /// ``OutlineRowActivating``. Left and Right collapse and expand through it.
    ///
    /// `package` and stored, not under an accessor: every access to it is
    /// dynamically enforced already, at least 6 `swift_beginAccess` sites in a
    /// release `Stress` before step C2 (d6bf4600d; see this class's note on the
    /// module split). A list and a table set it on every frame; as private storage
    /// under an accessor it kept its check, in the accessor, and those writes
    /// became calls.
    package var outlineActivation: (any OutlineRowActivating)?

    /// Opens or closes the branch the cursor is on.
    ///
    /// - Parameters:
    ///   - expanded: `true` to open, `false` to close.
    ///   - includingDescendants: Whether to carry that state down the whole
    ///     subtree rather than one level — the Option-held gesture.
    /// - Returns: Whether anything moved. `false` when the list is not a tree,
    ///   when the focused row is a leaf, and when the subtree is already in the
    ///   requested state — the key falls through in each case.
    func setFocusedRowExpanded(_ expanded: Bool, includingDescendants: Bool = false) -> Bool {
        guard let outlineActivation, let id = id(at: focusedIndex) else { return false }
        return outlineActivation.setRowExpanded(
            AnyHashable(id), to: expanded, includingDescendants: includingDescendants)
    }

    /// Right opens the focused branch; Left closes it, and — when there is
    /// nothing to close — leaves the subtree instead of the list.
    func handleDisclosureKey(_ event: KeyEvent) -> Bool {
        if event.key == .right {
            if setFocusedRowExpanded(true, includingDescendants: event.alt) { return true }
            // Nothing opened — a leaf, or a branch already open. In a TREE the
            // key is still the tree's: it is consumed and does nothing, rather
            // than falling through to move the focus sideways out of the
            // outline. Pressing Right on an open folder to see what happens
            // should not land you in the control next to the list.
            //
            // A list that is not a tree keeps its fall-through: it has no use
            // for Right at all, so nothing is taken away — unless what it is in
            // gives the key a use there (``rowForwardAction``).
            if outlineActivation == nil, let rowForwardAction, let id = id(at: focusedIndex) {
                // Keys arrive on the main actor, as `compactColumnAdvance`'s do,
                // so the row's id never leaves it: `nonisolated(unsafe)` only
                // says so to the checker, which cannot see it.
                nonisolated(unsafe) let row = AnyHashable(id)
                return MainActor.assumeIsolated { rowForwardAction(row) }
            }
            return outlineActivation != nil
        }
        if setFocusedRowExpanded(false, includingDescendants: event.alt) { return true }
        return moveFocusOutOfSubtree()
    }

    /// Left's second act, once there is nothing left to close: move the cursor
    /// OUT of the subtree it is in rather than letting the key escape the list.
    ///
    /// The ladder is the one an outline view uses, and each rung answers "where
    /// is 'out' from here?":
    ///
    /// 1. The parent row, when this row has one — up one level.
    /// 2. The first row, when it does not — a root row's "out" is the top of
    ///    the tree, which is where a fold-everything-up gesture lands you.
    /// 3. Nothing, when the cursor is already on the first row. Only then does
    ///    Left leave, so the key reaches the next view exactly once the outline
    ///    has run out of places to go — instead of, as before, on the first
    ///    press that met a leaf.
    ///
    /// - Returns: Whether the cursor moved. `false` on a list that is not a
    ///   tree, so a plain list's Left is untouched.
    private func moveFocusOutOfSubtree() -> Bool {
        guard let outlineActivation, focusedIndex >= 0 else { return false }
        if let id = id(at: focusedIndex),
            let parent = outlineActivation.parentRowID(of: AnyHashable(id))?.base
                as? SelectionValue,
            let parentIndex = index(of: parent)
        {
            focusedIndex = parentIndex
            ensureFocusedItemVisible()
            return true
        }
        guard focusedIndex > 0 else { return false }
        focusedIndex = 0
        ensureFocusedItemVisible()
        return true
    }

    /// Deletes the focused row when the `ForEach` that produced it is
    /// deletable.
    ///
    /// ``onDelete`` is called with the row's LIST index, which the installer
    /// translates into an offset in whichever collection that row came from —
    /// the same number in a flat `List { ForEach … }`, and not the same number
    /// inside a `Section`, whose header and preceding sections lie in between.
    ///
    /// - Returns: Whether a row was deleted. `false` leaves Delete / Backspace
    ///   to fall through, so a plain list never swallows either.
    func deleteFocusedRow() -> Bool {
        guard let onDelete, focusedIndex >= 0, focusedIndex < itemCount,
            // Which rows this one can be deleted among — `nil` for a row no
            // deletable `ForEach` produced (a header, a hand-written row, a row
            // of a list whose OTHER section is the editable one). Refusing here
            // is the point: the alternative is an offset that lands in a
            // collection the user was not pointing at.
            let span = deletableSpan(of: focusedIndex),
            // `.deleteDisabled()` on the row. Returning FALSE rather than true:
            // a refused row must leave Delete alone entirely, so it falls
            // through to whatever else wants the key — exactly as it does in a
            // list that is not deletable at all. Swallowing it would make a
            // locked row silently eat a shortcut.
            !deleteDisabledRows.contains(focusedIndex)
        else { return false }
        let row = focusedIndex
        onDelete(IndexSet(integer: row))
        focusedIndex = cursorRow(afterDeleting: row, from: span)
        ensureFocusedItemVisible()
        return true
    }

    /// Where the cursor stands once the row at `deleted` has left `span`.
    ///
    /// The row below slides up into the slot, so the cursor keeps THAT row —
    /// clamped to the span's new end as well as the list's, because deleting
    /// a section's last row must leave the cursor on that section's new last
    /// row rather than on whatever chrome follows it. Both bounds are one less
    /// than they look because the delete has not reached the numbers yet:
    /// ``itemCount`` refreshes next render, and `span` is this frame's.
    ///
    /// The case that clamp alone gets wrong is a span of ONE row, which has no
    /// new last row: `span.upperBound - 2` is then `span.lowerBound - 1`, the
    /// row ABOVE the span — a section's HEADER, which carries no selection
    /// value, answers nothing to Return or Space, and would wear the focus
    /// ring. (In a flat `List`, where the span is the whole list, that row
    /// does not exist and the `max(0,)` hid it; inside a `Section` it is
    /// always chrome.) So an emptied span falls through to the nearest row the
    /// cursor can actually stand on.
    private func cursorRow(afterDeleting deleted: Int, from span: Range<Int>) -> Int {
        let lastRowOfSpan = min(span.upperBound, itemCount) - 2
        guard lastRowOfSpan < span.lowerBound else {
            return max(0, min(deleted, lastRowOfSpan))
        }
        return nearestLandableRow(afterDeleting: deleted)
    }

    /// The nearest row the cursor can stand on once the row at `deleted` is
    /// gone — looking down from the emptied slot first, then up — numbered the
    /// way the list will be numbered AFTER the delete, which is this way with
    /// every row from `deleted` on slid up by one.
    ///
    /// That shift is the whole subtlety: ``selectableIndices`` and
    /// ``selectionDisabledRows`` were published by the render that drew the
    /// row being deleted, so they still answer in the OLD numbering, and the
    /// question about the row that will be at `index` has to be asked at
    /// `index + 1` from `deleted` on.
    ///
    /// Answers the emptied slot itself when nothing can be landed on at all —
    /// a list whose every remaining row is chrome — because there is nowhere
    /// better, and the next Up/Down finds a row if one appears.
    ///
    /// Through ``ItemListHandler/isLandable(_:)``, deliberately, so this asks
    /// exactly what `moveFocus(by:wrap:)` asks: a `.selectionDisabled()` row is
    /// walked past here too, not merely a header or a footer. Narrowing it to
    /// ``selectableIndices`` alone is the plausible simplification, and
    /// `ListEditingCursorLandingTests` pins it against precisely that.
    private func nearestLandableRow(afterDeleting deleted: Int) -> Int {
        let lastRow = itemCount - 2
        guard lastRow >= 0 else { return 0 }
        func willBeLandable(_ index: Int) -> Bool {
            isLandable(index < deleted ? index : index + 1)
        }
        if deleted <= lastRow, let below = (deleted...lastRow).first(where: willBeLandable) {
            return below
        }
        let highestAbove = min(deleted, lastRow + 1) - 1
        if highestAbove >= 0, let above = (0...highestAbove).last(where: willBeLandable) {
            return above
        }
        return max(0, min(deleted, lastRow))
    }

    /// The list rows the row at `index` may be deleted among — the rows of the
    /// `ForEach` that produced it — or `nil` when no deletable `ForEach` did.
    ///
    /// `lowerBound` is the row its collection's element 0 draws at, so
    /// `row - lowerBound` is the offset ``onDelete`` wants.
    ///
    /// With no resolver installed the whole list is one span, which is exactly
    /// what a `Table` and a flat `List { ForEach … }` are: there a row's index
    /// IS its offset, and a resolver would answer `0..<itemCount` for every row.
    func deletableSpan(of index: Int) -> Range<Int>? {
        guard let deletableRowSpan else { return 0..<itemCount }
        return deletableRowSpan(index)
    }

    /// LIST ROWS carrying `.deleteDisabled()`, republished each frame by the
    /// `List` from what the drawn rows reported.
    ///
    /// List rows, not offsets into the row's own collection: this is compared
    /// against ``focusedIndex``, which is a list row. The two are the same
    /// number in a flat list and are not inside a `Section` — and with two
    /// Sections the per-collection offsets collide outright, which is why
    /// `RowEditRestrictions` stamps the list row.
    ///
    /// Absence means allowed. A row that never rendered cannot appear here, and
    /// does not need to: the only row Delete can name is the focused one, and
    /// the focus machinery keeps that on screen.
    var deleteDisabledRows: Set<Int> = []

    /// List rows carrying `.moveDisabled()`. Same publication and the same
    /// reasoning as ``deleteDisabledRows`` — a drag can only grab a row it can
    /// point at.
    var moveDisabledRows: Set<Int> = []

    /// List rows carrying `.selectionDisabled()`. Same publication
    /// as ``deleteDisabledRows`` — reported by the row as it renders, absent
    /// means allowed, and a row that has never been on screen has never had
    /// the chance to report. Unlike the other two, this restriction also
    /// governs navigation: ``moveFocus(by:wrap:)`` will not land the cursor on
    /// a row named here, so a `.selectionDisabled()` row that has rendered at
    /// least once is skipped by Up/Down/Page Up/Page Down, in addition to
    /// refusing Enter/Space and a click (``toggleSelectionAtFocusedIndex()``).
    package var selectionDisabledRows: Set<Int> { get { _selectionDisabledRows } set { _selectionDisabledRows = newValue } }

    /// ``selectionDisabledRows``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _selectionDisabledRows: Set<Int> = []

    /// The `.onDelete(perform:)` action from an editable `ForEach`, if any:
    /// pressing Delete / Backspace on the focused row invokes it with that
    /// row's LIST index. `nil` keeps Delete inert so it falls through to page
    /// navigation. See ``handleKeyEvent(_:)`` and ``DynamicViewContentActions``.
    ///
    /// A list row rather than a collection offset because a list can hold
    /// several editable `ForEach`es — one per `Section` — and only the
    /// installer knows which collection a given row belongs to. It does the
    /// subtraction; see ``deletableSpan(of:)``.
    var onDelete: ((IndexSet) -> Void)?

    /// Which rows a given row can be deleted among, and so which collection its
    /// offset addresses. Installed by `_ListCore` every frame; `nil` means the
    /// whole list, which is a `Table`'s and a flat `List`'s shape. See
    /// ``deletableSpan(of:)``.
    var deletableRowSpan: ((Int) -> Range<Int>?)?

    /// The `.onMove(perform:)` reorder action from an editable `ForEach`, if
    /// any: dragging a row with the mouse commits through it on release with
    /// `(source rows, destination row)`. `nil` makes rows non-draggable.
    /// See ``RowReorder`` and `_ListCore`'s mouse handler.
    ///
    /// List rows rather than collection offsets, for the same reason as
    /// ``onDelete``: a list can hold several editable `ForEach`es, one per
    /// `Section`, and only the installer knows which collection a row belongs
    /// to. It does the subtraction; see ``movableSpan(of:)``.
    package var onMove: ((IndexSet, Int) -> Void)? { get { _onMove } set { _onMove = newValue } }

    /// ``onMove``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _onMove: ((IndexSet, Int) -> Void)?

    /// Which rows a given row can be moved among, and so which collection a
    /// reorder's offsets address. Installed by `_ListCore` every frame; `nil`
    /// means the whole list, which is a `Table`'s and a flat `List`'s shape.
    /// See ``movableSpan(of:)``.
    var movableRowSpan: ((Int) -> Range<Int>?)?

    /// The rows that move together with a given row: the rows of the element
    /// it draws, for a `ForEach` whose rows are several views each (decisions
    /// B15) — a reorder picks all of them up and lands them only between
    /// elements. Installed by `_ListCore` every frame; `nil` means every row
    /// moves alone, which is a `Table`'s shape and every other list's. See
    /// ``reorderGroup(of:)``.
    var reorderGroupSpan: ((Int) -> Range<Int>)?

    /// A `Table`'s keyboard sort gestures, if it has a `sortOrder` binding:
    /// invoked with ``RowAction/sortNextColumn`` or
    /// ``RowAction/reverseSortOrder``, and it applies the same `toggleSort` a
    /// header CLICK applies. `nil` for a `List`, and for a `Table` with nothing
    /// to sort, which is what leaves those chords to the app.
    ///
    /// Set every frame beside ``onMove``, at BOTH `_TableCore` viewports: it
    /// closes over that frame's binding, while the handler persists at one
    /// identity across frames and across a switch between the two paths.
    package var onSort: ((RowAction) -> Void)? { get { _onSort } set { _onSort = newValue } }

    /// ``onSort``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _onSort: ((RowAction) -> Void)?

    /// The state of an in-flight mouse reorder drag, or `nil`. See
    /// ``ItemListHandler/dragReorder(toContentY:)`` for the state machine.
    ///
    /// `package` and stored, not under an accessor: every access to it is
    /// dynamically enforced already, at least 36 `swift_beginAccess` sites in a
    /// release `Stress` before step C2 (d6bf4600d; see this class's note on the
    /// module split). TUILists reads it in place on every frame (List's and a
    /// table's row composition); as private storage under an accessor it kept its
    /// check, in the accessor, and those reads became calls.
    package var reorder: RowReorder?

    /// What a reorder drag shows, synced from `environment.rowReorderFeedback`
    /// during render; read at event time, when the environment is out of reach.
    var reorderFeedback: RowReorderFeedback = .live

    /// Whether a KEYBOARD move shuffles the data as it goes instead of
    /// previewing `.dimmed`. Set by a view whose row composer draws no slot —
    /// the multi-line `Table` — because a dimmed preview it never draws left
    /// Ctrl-R moving nothing visible while the handler parked the cursor
    /// beside a slot that was not there. See ``effectiveReorderFeedback``.
    var keyboardMoveIsLive = false

    /// Whether the reorder in flight was started from the KEYBOARD (see
    /// ``ItemListHandler/beginKeyboardMove()``) rather than by a drag.
    package var isKeyboardMove: Bool { get { _isKeyboardMove } set { _isKeyboardMove = newValue } }

    /// ``isKeyboardMove``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _isKeyboardMove = false

    /// The row the last left release landed on — the identity half of the
    /// multi-click question. See ``completesMultiClick(on:clickCount:)``.
    var lastClickedRow: Int?

    /// Whether a dragged row can actually be floated at the pointer — there has
    /// to be a drag-and-drop session to draw it above the frame. Captured at
    /// render; see ``effectiveReorderFeedback``.
    var canFloatDraggedRow = false

    /// Where each visible row sits in the rendered content, republished every
    /// render (see ``RowBand``). A drag reads the CURRENT bands rather than the
    /// press-frame copy its closure captured, because under
    /// ``RowReorderFeedback/live`` the rows genuinely move underneath the cursor
    /// — and a wheel tick can scroll them under any mode.
    var visibleRowBands: [RowBand] = []

    /// The ``scrollOffset`` ``visibleRowBands`` were published against.
    ///
    /// A band says "this LINE holds that row", which stops being true the
    /// moment the viewport scrolls — the line is still there, a different row
    /// is on it. Keeping the offset alongside is what lets
    /// ``carryReorderTargetThroughAutoScroll()`` tell how far the rows have
    /// moved under a pointer that has not.
    var visibleRowBandsOffset: Int = 0

    /// Backing storage for ``drawnOffset``; see there.
    var drawnWindowOffset: Int?

    /// One visible row's extent within the list's rendered content, in lines
    /// measured from the first content line (i.e. below the border and padding,
    /// and below the "N more above" indicator when one is drawn).
    struct RowBand: Equatable, Sendable {
        /// Which of the list's rows this is.
        var rowIndex: Int
        /// The row's first line.
        var yStart: Int
        /// How many lines it occupies (clipped rows count what's shown).
        var height: Int
        /// Whether this is a content row — a real, selectable row. Section
        /// headers and the reorder drop slot are not.
        var isContent: Bool
        /// Where a reorder drop on this line would put the dragged row, or `nil`
        /// for a line that is not a drop target: a section header, or — while a
        /// reorder is in flight — any row outside the span the rows in hand may
        /// land in (see ``ItemListHandler/reorderSpan``). That second case is
        /// what keeps a drag inside its own `ForEach`: one `nil` here confines
        /// the pointer clamp, the landing slot and the `.live` shuffle at once.
        ///
        /// A line's position in the order currently DRAWN, which is a
        /// prospective final index — see ``dropTarget(atContentY:)``. Outside a
        /// non-`.live` drag that is simply ``rowIndex``; during one the list has
        /// closed up behind the dragged row and opened a slot elsewhere, so the
        /// two part company (``reorderDrawnPosition(of:)``).
        ///
        /// It is separate from ``rowIndex`` for two reasons, then: that, and the
        /// one line that is a drop target without being a row at all — the
        /// reorder slot, which the pointer rests on after every step of a drag.
        /// Reading that line as "off the rows" is what made a `.cursor` drag
        /// cancel its own gap.
        var dropIndex: Int?
    }

    /// The selection mode (single or multi).
    let selectionMode: SelectionMode

    /// Whether this element can currently receive focus.
    package var canBeFocused: Bool { get { _canBeFocused } set { _canBeFocused = newValue } }

    /// ``canBeFocused``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _canBeFocused: Bool

    /// The currently focused item index (keyboard cursor).
    package var focusedIndex: Int { get { _focusedIndex } set { _focusedIndex = newValue } }

    /// ``focusedIndex``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _focusedIndex: Int = 0

    /// The identity of the row last drawn over a raised background — the
    /// focused, selected row of a `List` — or `nil` when there was none. Kept
    /// so the frame that moves the raise can clear both rows' cached renders:
    /// the raise reaches the row's content through its environment, which no
    /// memo below the row compares (``BackgroundProminence``).
    package var raisedProminenceRow: ViewIdentity? { get { _raisedProminenceRow } set { _raisedProminenceRow = newValue } }

    /// ``raisedProminenceRow``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _raisedProminenceRow: ViewIdentity?

    /// The row a drag is over that takes it onto itself — a table row's
    /// `.dropDestination(for:action:)` — drawn as a selected row is meanwhile.
    package var rowDropTarget: Int? { get { _rowDropTarget } set { _rowDropTarget = newValue } }

    /// ``rowDropTarget``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _rowDropTarget: Int?

    /// Whether the row at `index` is drawn as selected: it is, or a drag it
    /// would take is over it (``rowDropTarget``).
    package func drawsSelected(at index: Int) -> Bool {
        rowDropTarget == index || isSelected(at: index)
    }

    /// Type select: the characters typed so far, and when the last of them
    /// came — a gap of a second starts a new prefix (``typeSelect(_:)``).
    var typeSelected = TypeSelectBuffer()

    /// A prefix typed since the last render, for the next render to find a row
    /// for: the rows' text is the render's to give (``typeSelect(_:)``).
    var pendingTypeSelect: String?

    /// The anchor row for range selection (macOS semantics): the last row
    /// plainly clicked, modifier-toggled, or Space-toggled. Shift-clicks and
    /// keyboard range extension both select the whole span between the anchor
    /// and the cursor, re-pivoting around it.
    var selectionAnchor: Int?

    /// Whether extend mode (`v`) is active: plain movement keys extend the
    /// selection from the anchor instead of just moving the cursor. The
    /// portable stand-in for Shift+movement — most terminals don't deliver
    /// Shift on Up/Down (Terminal.app strips it) and none distinguish
    /// Shift+Space from Space, so a mode toggled by a plain printable key is
    /// the only gesture guaranteed to work everywhere. Exited by `v`, Escape,
    /// Space/Enter, any click, or focus loss.
    var isExtendingSelection = false

    /// The scroll offset (first visible item index).
    ///
    /// Moving it retires ``drawnOffset``: that answer describes the frame the
    /// rows were last drawn in, and once the viewport has moved there is no
    /// drawn origin again until something draws. Leaving it behind is not a
    /// stale-by-a-bit problem but a wrong-sign one — the app drains a burst of
    /// auto-repeated keys before it renders, and `pageDelta(_:)` subtracting a
    /// several-page-old origin turned the second Page Down of a held key into
    /// a scroll UP, pinning the viewport one page from the top.
    package var scrollOffset: Int { get { _scrollOffset } set { _scrollOffset = newValue } }

    /// ``scrollOffset``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _scrollOffset: Int = 0 {
        didSet {
            if scrollOffset != oldValue { drawnWindowOffset = nil }
        }
    }

    /// How many LINES of the top visible row (``scrollOffset``) are scrolled
    /// off the top edge — the sub-row position that makes line-step
    /// scrolling (``ScrollStepUnit/line``) line-precise while
    /// ``scrollOffset`` / ``maxOffset`` / ``extent`` stay row-based (O(1) for
    /// any list size). Always `0` for single-line rows and at the very bottom
    /// (``maxOffset`` is the last row-aligned top). Clamped each render by
    /// ``clampTopClip()``.
    ///
    /// Under whole-row steps (``ScrollStepUnit/row``) a scroll STEP always leaves this at `0`
    /// (``scrollFine(by:)``), but a reveal or a centred anchor may still set
    /// it: those position the viewport on a row the user chose, and forcing
    /// them onto a row boundary moves the row off the position they computed.
    package var scrollTopClipLines: Int { get { _scrollTopClipLines } set { _scrollTopClipLines = newValue } }

    /// ``scrollTopClipLines``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _scrollTopClipLines: Int = 0

    /// How the scroll target behaviour in force applies to this list — synced
    /// from `environment.scrollTargetBehavior` during render (line steps, with
    /// no behaviour); read at event time by ``scrollFine(by:)`` and
    /// ``userScrollStep(_:)``, when the environment is no longer reachable.
    var scrollTargeting = ListScrollTargeting.free

    /// What one scroll step moves through: ``ScrollStepUnit/line`` (the
    /// default) or whole rows (``ScrollStepUnit/row``, under `.viewAligned`).
    var scrollStepUnit: ScrollStepUnit {
        get { scrollTargeting.unit }
        set { scrollTargeting.unit = newValue }
    }

    /// Grab point within the thumb during a scrollbar drag (``ScrollableOffsetState``).
    package var scrollbarDragGrab: Int? { get { _scrollbarDragGrab } set { _scrollbarDragGrab = newValue } }

    /// ``scrollbarDragGrab``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _scrollbarDragGrab: Int?

    /// Held arrow/track auto-repeat action (``ScrollableOffsetState``).
    package var scrollbarRepeat: ScrollbarRepeat? { get { _scrollbarRepeat } set { _scrollbarRepeat = newValue } }

    /// ``scrollbarRepeat``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _scrollbarRepeat: ScrollbarRepeat?

    /// Wheel-chaining grace state (``ScrollableOffsetState``).
    package var wheelEdgeHold: WheelEdgeHold { get { _wheelEdgeHold } set { _wheelEdgeHold = newValue } }

    /// ``wheelEdgeHold``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _wheelEdgeHold = WheelEdgeHold()

    /// Overscroll excursion + allowance (``ScrollableOffsetState``), resolved
    /// from the environment each render.
    package var overscrollState: ScrollOverscrollState { get { _overscrollState } set { _overscrollState = newValue } }

    /// ``overscrollState``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _overscrollState = ScrollOverscrollState()

    /// The glide in flight (``ScrollableOffsetState``): a `scrollTo` or a
    /// bound `.scrollPosition` request made inside `withAnimation`, a row at a
    /// time (`ItemListHandler+Glide.swift`).
    package var glide: ScrollGlide? { get { _glide } set { _glide = newValue } }

    /// ``glide``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _glide: ScrollGlide?

    /// The animation the cursor's page keys — Page Up/Down, Home, End — glide
    /// the viewport with, or `nil` to jump: `scrollKeyboardAnimation(_:)`,
    /// captured at render (``syncFrameInputs(environment:reorderFeedback:keyboardMoveIsLive:rowHeight:)``)
    /// because event time has no environment.
    package var keyboardAnimation: Animation? { get { _keyboardAnimation } set { _keyboardAnimation = newValue } }

    /// ``keyboardAnimation``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _keyboardAnimation: Animation?

    /// What the list's scrolling is doing, for `onScrollPhaseChange`
    /// (`ScrollPhaseReporting`): `.interacting` from a user's scroll until it
    /// has been quiet a quarter of a second, `.animating` while a request
    /// glides, as a `ScrollView`'s.
    package var phase: ScrollPhase { get { _phase } set { _phase = newValue } }

    /// ``phase``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _phase = ScrollPhase.idle

    /// When the user last scrolled, on ``phaseNow``'s clock.
    package var lastUserScrollNanos: UInt64 { get { _lastUserScrollNanos } set { _lastUserScrollNanos = newValue } }

    /// ``lastUserScrollNanos``'s storage: private, under the `package`
    /// accessor (CONTRIBUTING.md, "Crossing a module boundary").
    private var _lastUserScrollNanos: UInt64 = 0

    /// The phase each `onScrollPhaseChange` observer was last told.
    package var reportedPhases: [ScrollPhase?] { get { _reportedPhases } set { _reportedPhases = newValue } }

    /// ``reportedPhases``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _reportedPhases: [ScrollPhase?] = []

    /// The clock the phase is timed on: the monotonic one the frame clock
    /// reads. Replaceable so a test can step it.
    package var phaseNow: () -> UInt64 { get { _phaseNow } set { _phaseNow = newValue } }

    /// ``phaseNow``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _phaseNow: () -> UInt64 = { MonotonicClock.nowNanoseconds }

    /// Drag auto-scroll drive flag (``ScrollableOffsetState``).
    package var isAutoScrolling: Bool { get { _isAutoScrolling } set { _isAutoScrolling = newValue } }

    /// ``isAutoScrolling``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _isAutoScrolling = false

    /// The content Y the reorder drag last saw, so the drop target can be
    /// recomputed when edge auto-scroll moves the rows under a still pointer.
    var lastReorderContentY: Int?

    /// Where a drag from OUTSIDE this list would land, while one is hovering
    /// — a data index, since nothing has been taken out of this list.
    ///
    /// Draws the same gap a `.cursor` reorder shows, because it means the same
    /// thing: let go here and the rows arrive at this place.
    package var externalDropSlot: Int? { get { _externalDropSlot } set { _externalDropSlot = newValue } }

    /// ``externalDropSlot``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _externalDropSlot: Int? {
        didSet {
            // The remembered pointer position belongs to the slot: when the slot
            // goes, so does it.
            if externalDropSlot == nil {
                lastExternalDropContentY = nil
                externalDropResolvedOffset = nil
            }
        }
    }

    /// Whether a drop from outside at a slot would be taken, for a
    /// destination that takes a payload at some slots and not at others — a
    /// hierarchical table, whose loops take drops among their own rows — or
    /// `nil` where every slot takes it. A slot it refuses opens no gap
    /// (``setExternalDropSlot(_:)``). Set by the destination each frame, for
    /// the drag in hand.
    package var externalDropTakes: ((Int) -> Bool)? {
        get { _externalDropTakes }
        set { _externalDropTakes = newValue }
    }

    /// ``externalDropTakes``' storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _externalDropTakes: ((Int) -> Bool)?

    /// The content-space line the incoming drag last hovered, so an auto-scroll
    /// tick can re-resolve the slot with no mouse event to go on. See
    /// ``hoverExternalDrop(atContentY:)``, which is the only thing that should
    /// write it.
    var lastExternalDropContentY: Int?

    /// The scroll offset the slot was last resolved at — by the auto-scroll
    /// retarget, or by a hover that had a band to read — or `nil` when the
    /// standing answer is one the retarget should replace.
    ///
    /// That retarget exists for one reason: the rows move under a motionless
    /// pointer, so the slot the pointer named goes stale. It follows that it
    /// must not run again while the rows sit still — and there it is worse than
    /// useless, because the question it asks is answered by bands that its own
    /// previous answer helped lay out. On a list whose rows exactly fill it,
    /// the slot's line pushes the last row out of view, which changes which row
    /// is last, which changes the answer, which puts the line back: the gap
    /// flips between two places on alternate frames with the pointer perfectly
    /// still.
    ///
    /// So a hover that landed ON a band writes the current offset here rather
    /// than clearing it: it has answered from the pointer's own position, and
    /// the retarget can only replace that with a derived one. Clearing it on
    /// every newly-named line (which is what this did until 2026-08-29) did not
    /// avoid the flip, only its frequency — the render after each mouse movement
    /// still overrode the pointer, so the gap sat one line above the cursor on
    /// the bottom row of a full list.
    ///
    /// `nil` only for a hover that landed on no band at all. The pointer that
    /// starts auto-scroll is by definition on chrome, and there the hover's own
    /// rule ("past the rows means append") is an answer about the end of the
    /// data rather than about anywhere near the cursor — exactly what the
    /// retarget is for.
    var externalDropResolvedOffset: Int?

    /// This list's own pictures, stamped by each render of it, for the one
    /// write of the drop gap a render makes AFTER drawing: the auto-scroll
    /// retarget, which runs as the rows are published (see ``HandlerDrawing``).
    ///
    /// What the retarget moves is drawn on the next frame. A list that does not
    /// hold the focus — the one a drag from elsewhere is aimed at — is stored
    /// by the row around it, as it was drawn before the move, and was then
    /// served with the gap where the retarget had just moved it from.
    package var drawing: HandlerDrawing? { get { _drawing } set { _drawing = newValue } }

    /// ``drawing``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _drawing: HandlerDrawing?

    /// Rows whose picture is still flying home, drawn BLANK where they belong.
    ///
    /// A cancelled reorder puts its rows back the instant the button comes up,
    /// while the preview takes a fifth of a second to walk back to them — so
    /// for that fifth of a second the same rows were on screen twice, once in
    /// the list and once in the air above it.
    ///
    /// Blank in place, NOT held out of the list. Taking them out for the
    /// duration would change the list's length after the gesture is over,
    /// which moves the very rows the user is looking at (and can change what
    /// the list can scroll to). Their space is theirs; they simply have nothing
    /// drawn in it until the picture lands. So this is a question the RENDERER
    /// asks and the layout never does — no window, band, budget or index
    /// arithmetic reads it.
    ///
    /// Cleared by the owning view on any frame with no flight in the air, which
    /// makes it self-limiting: a path that sets it without starting a flight
    /// loses it on the very next render rather than blanking a row for ever.
    ///
    /// `package` and stored, not under an accessor: every access to it is
    /// dynamically enforced already, at least 8 `swift_beginAccess` sites in a
    /// release `Stress` before step C2 (d6bf4600d; see this class's note on the
    /// module split). A table in TUITables asks it for every row it draws.
    package var returningRows: IndexSet = []

    /// Drops any blanking left over from a flight that has already landed.
    ///
    /// Called by the owning view every render — both of them, on every path,
    /// which is why it is a method rather than the two lines it replaces: the
    /// rule is "a row blanks itself only while a picture is walking back to
    /// it", and a path that forgot to say so left a row blank for good.
    package func syncReturningRows(with session: DragAndDropSession?) {
        if session?.returnFlight == nil { returningRows = [] }
    }

    /// Set when Escape cancels a drag whose button is still down: the release
    /// that follows must be swallowed rather than read as a click.
    package var reorderCancelled: Bool { get { _reorderCancelled } set { _reorderCancelled = newValue } }

    /// ``reorderCancelled``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _reorderCancelled = false

    /// The drag session, captured at render, so a cancel can take the floating
    /// preview down without waiting for the release that ends the gesture.
    weak var dragSession: DragAndDropSession?

    /// Whether the user may scroll (``ScrollableOffsetState``), synced from
    /// `environment.isScrollEnabled` each render. Selection movement is NOT
    /// gated by it — moving a cursor is not adjusting a scroll position, and the
    /// reveal that keeps the cursor on screen is a framework guarantee.
    package var isScrollEnabled: Bool { get { _isScrollEnabled } set { _isScrollEnabled = newValue } }

    /// ``isScrollEnabled``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _isScrollEnabled = true

    /// The scrollbar cell under the pointer (``ScrollableOffsetState``).
    package var hoveredBarCell: Int? { get { _hoveredBarCell } set { _hoveredBarCell = newValue } }

    /// ``hoveredBarCell``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _hoveredBarCell: Int?

    /// The first row of the section with actions that the pointer is over, or
    /// `nil`: that section's actions are drawn (owner ruling B78-VISIBILITY).
    var hoveredSectionRow: Int?

    /// The rows of each section with actions in the last frame drawn, header
    /// to footer — what ``hoverSections(atContentY:)`` finds the pointer in.
    var sectionActionSpans: [Range<Int>] = []
    /// Bound `.anchorPosition` override, captured each render so a USER scroll
    /// can release it to `.window` at event time. See
    /// `ScrollableOffsetState.releaseAnchorOnUserScroll()`.
    package var anchorPositionBinding: Binding<ScrollAnchor<AnyHashable>?>? { get { _anchorPositionBinding } set { _anchorPositionBinding = newValue } }

    /// ``anchorPositionBinding``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _anchorPositionBinding: Binding<ScrollAnchor<AnyHashable>?>?

    /// The anchor mode the view DECLARED (from `defaultScrollAnchor`), synced
    /// each render. Read by ``anchorOnSelection(at:)`` to scope the §1.2
    /// shadow-switch to the edge modes the spec names.
    var declaredAnchorMode: ScrollAnchorMode = .window

    /// The anchor mode the view declared for the OPENING frame (from
    /// `defaultScrollAnchor(_:for: .initialOffset)`), synced each render beside
    /// ``declaredAnchorMode``.
    ///
    /// `nil` means none was stated, and then the opening frame uses
    /// ``declaredAnchorMode`` like every frame after it — which is exactly what
    /// a view using the unlabelled modifier gets, and what makes the role split
    /// inert for everything written before it.
    var declaredOpeningAnchorMode: ScrollAnchorMode?

    /// Whether this scrollable has rendered a frame yet.
    ///
    /// The opening frame is placed by ``declaredOpeningAnchorMode`` and every
    /// frame after it by ``declaredAnchorMode`` — see
    /// ``ScrollAnchorMode/governing(opening:standing:hasOpened:)``. Set on
    /// render passes only: a measure must not spend the opening frame.
    var hasOpened = false

    /// The declared anchor as an EDGE, for the shared user-scroll path
    /// (``ScrollableOffsetState/declaredEdgeAnchor``). Row and Window name no
    /// edge, so they answer `nil`.
    package var declaredEdgeAnchor: ScrollAnchor<AnyHashable>? {
        switch declaredAnchorMode {
        case .top: return .top
        case .bottom: return .bottom
        case .row, .window: return nil
        }
    }

    /// The screen ROW a bound `.row` anchor is held at (0 = first visible row),
    /// and the key it was adopted for. Row-based, like ``scrollOffset``: for
    /// single-line rows it is the screen line; for taller rows it is the
    /// anchored row's index from the top of the viewport. See
    /// ``applyRowAnchorHold()`` (in `ItemListHandler+Anchor.swift`).
    var anchorHeldRow = 0
    var anchorHeldKey: AnyHashable?
    /// Last resolved ordinal of the held anchor key — an O(1) fast path so the
    /// per-frame hold doesn't rescan the whole list once the row settles.
    var anchorHeldOrdinal: Int?

    /// The bound anchor as of the last render, so a *change* can be detected
    /// and jumped to (§3.2's `anchor(to:)`). Outer optional = "never seen yet";
    /// inner = the binding's own `nil`. See ``applyAnchorHold()``.
    var lastBoundAnchor: ScrollAnchor<AnyHashable>??

    /// Last render's ``maxOffset``, against which "is this view at the bottom?"
    /// is judged for the Bottom follow.
    ///
    /// The test cannot use the CURRENT `maxOffset`: by the time the hold runs,
    /// `itemCount` has already been re-synced to the new data, so an append has
    /// moved `maxOffset` out from under an offset that was at the tail a moment
    /// ago, and the view would read as "not at the bottom" exactly when it
    /// should follow. Last frame's bound is the one the user's offset was
    /// actually formed against — including any scrolling they did between
    /// renders, which is what makes scrolling away release the follow.
    ///
    /// Starting at 0 makes the first frame glued by construction (offset 0 ≥ 0),
    /// which is how a declared `.bottom` list opens at its tail.
    var bottomFollowBound = 0

    /// Whether the change this frame renders was made under a transaction that
    /// turns a scroll view's own offset adjustments off
    /// (`Transaction.scrollContentOffsetAdjustmentBehavior`). Synced each render
    /// by `syncFrameInputs`; read by ``applyAnchorHold()``.
    var offsetAdjustmentSuspended = false

    /// What the list keeps in place when the rows above its top row change
    /// (``ScrollWindowHold``), synced each render by `syncFrameInputs`; and
    /// the one the last frame was drawn under, so a frame that takes up
    /// ``ScrollWindowHold/topRow`` after one that did not only keeps track of
    /// the row — the rows may have moved under one remembered before then.
    var windowHold = ScrollWindowHold.topRow
    var lastWindowHold = ScrollWindowHold.offset

    /// The row at the top of the viewport when the last frame was drawn — the
    /// first row at or below ``scrollOffset`` with an id, a section's header
    /// having none — with its ordinal then, the id of the row after it, which
    /// takes its place if it leaves the data, and the id of the row before it,
    /// which with it tells a change above from a sort. What
    /// ``ScrollWindowHold/topRow`` holds: see ``holdTopRow()``.
    var heldTopID: SelectionValue?
    var heldTopNextID: SelectionValue?
    var heldTopPreviousID: SelectionValue?
    var heldTopOrdinal = 0

    /// The ``scrollOffset`` the held row was remembered at, and whether this
    /// frame found it where it was — together, whether remembering it again
    /// would read anything new.
    var heldTopOffset = 0
    var heldTopVerified = false

    /// ``itemCount`` when the held row's neighbours were read: a frame that
    /// finds the row in place with a different count reads them again, as a
    /// row inserted or removed beside it leaves it in place
    /// (``rememberTopRow()``).
    var heldTopItemCount = 0

    /// How many more frames ``holdTopRow()`` waits for rows this list moved
    /// itself through ``onMove`` — a move chord, a drop, a live drag's step,
    /// which placed the cursor on the row it moved and revealed it — to reach
    /// the data; `0` when it is not waiting. The frame that finds the rows
    /// moved under the top row holds nothing, and spends the wait.
    ///
    /// A wait of frames, not one frame: an `onMove` that applies the move
    /// later (`Task { await store.move(…) }`) draws the key's frame with the
    /// rows unmoved, and the moved rows a frame after, which were held — the
    /// cursor landed on the old top row (the SCROLLANCHOR review, S4).
    ///
    /// And no longer than ``movedRowsWaitNanos`` of the frame clock
    /// (``awaitMovedRows(atNanos:)``): only frames that find the top row in
    /// place spend the wait, so a move below the top row, which leaves it in
    /// place, left a list that drew nothing more waiting for good — and a
    /// change above the top row seconds later, by anything else, was taken
    /// for the move and not held (lane SCROLLB's review).
    var movedRowsPendingFrames = 0

    /// When the wait for a move of the list's own ends, on the frame clock:
    /// stamped by the first frame after the move. `nil` until then.
    var movedRowsWaitEndsAtNanos: Int64?

    /// The frames ``movedRowsPendingFrames`` starts at.
    static var movedRowsWaitFrames: Int { 3 }

    /// The longest the wait lasts on the frame clock: as many frames of three
    /// 1/60 s ticks, 150 ms.
    static var movedRowsWaitNanos: Int64 {
        AnimationClock.nanoseconds(atTick: Int64(movedRowsWaitFrames * AnimationClock.standardFrameTicks))
    }

    /// Ends the wait for a move of the list's own (``movedRowsPendingFrames``)
    /// once ``movedRowsWaitNanos`` have passed on the frame clock since the
    /// first frame after the move, at `now`. Asked only while one is awaited.
    func awaitMovedRows(atNanos now: Int64) {
        guard let ends = movedRowsWaitEndsAtNanos else {
            movedRowsWaitEndsAtNanos = now &+ Self.movedRowsWaitNanos
            return
        }
        if now >= ends { movedRowsPendingFrames = 0 }
    }

    /// Last glued frame's ``itemCount``, so the Bottom follow can tell a frame
    /// where the tail actually ADVANCED (rows arrived — carry the focus cursor
    /// along) from a steady glued frame (nothing changed — leave the cursor
    /// alone, or the arrow keys are dead; see ``followBottomEdge()``). Counts
    /// rather than offsets, because a list shorter than its viewport appends
    /// without ever moving the offset. Starts at -1 so the first glued frame
    /// always reads as an advance (the opening placement carries the cursor).
    var bottomFollowItemCount = -1

    /// The row the Bottom follow last parked the focus cursor on, or `nil` when
    /// it has never carried it.
    ///
    /// How the follow tells its own cursor move from the user's: finding the
    /// cursor somewhere else means they moved it, and their place in the list
    /// outranks the newest row. See ``followBottomEdge()``.
    var bottomFollowCursor: Int?

    /// The last row index the Bottom follow saw, so a cursor walked back onto
    /// the tail re-engages the follow even though rows have arrived since (the
    /// CURRENT tail is one of the new rows, which the user has never seen).
    var bottomFollowTail = -1

    /// Whether this list holds the focus, as of the last render.
    ///
    /// Set by the owning view alongside the rest of the per-frame wiring. The
    /// Bottom follow reads it: an unfocused list has no cursor anyone is
    /// looking at, so it scrolls without moving one — anchoring a log view must
    /// not put a highlight on a row the user never chose.
    var isFocusEngaged = false

    /// Binding for single selection mode (optional ID).
    ///
    /// The getter is `@inline(__always)` for ``isSelected(at:)``, which every
    /// drawn row of a list or table asks (through ``drawsSelected(at:)``):
    /// once the storage went private behind it (module split, step C2),
    /// release builds called this getter there out of line (why the optimiser
    /// declines is not established). The attribute reaches callers in this
    /// module only. Reading `_singleSelection` directly in `isSelected`
    /// instead is not the same: that read spans `Binding.wrappedValue`'s
    /// getter, and a release build then checks every access to both
    /// selections' storage at run time (`swift_beginAccess`).
    package var singleSelection: Binding<SelectionValue?>? {
        @inline(__always) get { _singleSelection }
        set { _singleSelection = newValue }
    }

    /// ``singleSelection``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _singleSelection: Binding<SelectionValue?>?

    /// Binding for multi-selection mode (Set of IDs).
    ///
    /// The getter is `@inline(__always)` for ``isSelected(at:)``, as
    /// ``singleSelection``'s is.
    package var multiSelection: Binding<Set<SelectionValue>>? {
        @inline(__always) get { _multiSelection }
        set { _multiSelection = newValue }
    }

    /// ``multiSelection``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _multiSelection: Binding<Set<SelectionValue>>?

    /// Maps item indices to their IDs for selection management.
    ///
    /// Entries are `nil` for non-selectable rows (e.g. section headers/footers in List).
    ///
    /// Eager backing where the list knows every row's answer as it hands them
    /// over and not every row is content: a `Section` of one `ForEach`, a
    /// `ForEach` whose ids the selection cannot all hold, tests. A large flat
    /// windowed `List` and every `Table` (whose rows are all content) leave
    /// this empty and supply ``idAt`` instead, so neither materialises an id
    /// per off-screen row — and so does a list with a flattened row still to
    /// be asked its answer (hand-written rows, alone or beside a loop, flat or
    /// in a `Section`), which hands this over unsettled (below). Read ids
    /// through ``id(at:)`` / ``index(of:)``, never this array directly.
    ///
    /// May be handed over UNSETTLED, with ``selectableIndices``, by
    /// ``answerRowsWhenAsked(idAt:settling:)``: then the first read of either
    /// settles both, and so does a write, before it lands.
    package var itemIDs: [SelectionValue?] {
        get {
            settleRowAnswers()
            return settledItemIDs
        }
        set {
            settleRowAnswers()
            settledItemIDs = newValue
        }
    }

    /// ``itemIDs``' storage, once settled.
    private var settledItemIDs: [SelectionValue?] = []

    /// Lazy id resolver used in place of ``itemIDs`` by the windowed `List` path
    /// and by `Table`.
    ///
    /// When set, ``id(at:)`` resolves a row's id on demand — per frame only the
    /// visible window and the focused row are asked — so a 50k-row list pays
    /// O(1) for handler setup instead of building a 50k-entry ``itemIDs``.
    /// (User-initiated selection gestures ask for more: a range extension
    /// resolves its span, select-all every row — but never per-frame.) `nil`
    /// for the eager paths, which use ``itemIDs`` — except one that hands its
    /// answers over unsettled (``answerRowsWhenAsked(idAt:settling:)``), whose
    /// ids are asked here one row at a time for the same reason.
    package var idAt: ((Int) -> SelectionValue?)? { get { _idAt } set { _idAt = newValue } }

    /// ``idAt``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _idAt: ((Int) -> SelectionValue?)?

    /// The set of indices that can be selected and focused.
    ///
    /// Headers and footers have non-selectable indices (not in this set).
    /// Only content rows have indices in `selectableIndices`.
    /// When empty, all items are considered selectable (backward compatibility) —
    /// which is exactly what the all-content windowed `List` wants, so it leaves
    /// this empty rather than allocating a full `Set(0..<count)`.
    ///
    /// Settled with ``itemIDs`` — see there.
    var selectableIndices: Set<Int> {
        get {
            settleRowAnswers()
            return settledSelectableIndices
        }
        set {
            settleRowAnswers()
            settledSelectableIndices = newValue
        }
    }

    /// ``selectableIndices``' storage, once settled.
    private var settledSelectableIndices: Set<Int> = []

    /// This frame's ``itemIDs`` and ``selectableIndices`` while nothing has
    /// read them yet — see ``answerRowsWhenAsked(idAt:settling:)``.
    private var unsettledRowAnswers: (() -> RowAnswers)?

    /// The first and the last row ``idAt`` names, once asked, while the answers
    /// are unsettled — see ``firstLandingRow(orElse:)``. `.some(nil)` is "no
    /// row is named".
    private var unsettledNamedRowBounds: (first: Int??, last: Int??) = (nil, nil)

    /// Creates an item list handler.
    ///
    /// - Parameters:
    ///   - focusID: The unique focus identifier.
    ///   - itemCount: The total number of items.
    ///   - viewportHeight: The number of visible items.
    ///   - selectionMode: Single or multi-selection mode.
    ///   - canBeFocused: Whether this element can receive focus.
    package init(
        focusID: String,
        itemCount: Int,
        viewportHeight: Int,
        selectionMode: SelectionMode,
        canBeFocused: Bool = true
    ) {
        self._focusID = focusID
        self._itemCount = itemCount
        self._viewportHeight = viewportHeight
        self.selectionMode = selectionMode
        self._canBeFocused = canBeFocused
    }
}

// MARK: - Item ID Resolution

extension ItemListHandler {
    /// The id of the row at `index`, or `nil` for a non-selectable / out-of-range
    /// row. Resolves through the lazy ``idAt`` when present — a windowed
    /// `List`, a `Table`, and a list that handed its answers over unsettled
    /// (see ``itemIDs``) — else the eager ``itemIDs`` (a `Section` of one
    /// `ForEach`, a `ForEach` whose ids the selection cannot all hold,
    /// tests). Per frame only the visible window and the focused row are
    /// asked (selection gestures ask for their span on the way in, never
    /// per-frame).
    ///
    /// What one row costs: an array read from ``itemIDs``; through ``idAt`` a
    /// key-path read or a cast, except that a `.tag(_:)`-carrying looped row
    /// is BUILT to read its tag, and among flattened rows an untagged
    /// hand-written row's ordinal is checked against the answers of the
    /// looped rows beside it (`FlattenedRowIDs`), in order up to the first
    /// that answers it — every one of them where none does, a build per
    /// tagged one.
    package func id(at index: Int) -> SelectionValue? {
        guard index >= 0 else { return nil }
        if let idAt {
            guard index < itemCount else { return nil }
            return idAt(index)
        }
        guard index < itemIDs.count else { return nil }
        return itemIDs[index]
    }

    /// The index of the row whose id equals `id`, or `nil`.
    ///
    /// Backed by ``itemIDs`` (O(total) hash-free scan) for the eager paths. The
    /// windowed path scans `0..<itemCount` through ``idAt`` — O(total) too, but
    /// only ever invoked on focus-lost under an active selection, never per
    /// frame, so it stays off the hot path — and by a hold, past where
    /// ``index(of:near:)`` looked first.
    func index(of id: SelectionValue) -> Int? {
        if let idAt {
            for index in 0..<itemCount where idAt(index) == id { return index }
            return nil
        }
        return itemIDs.firstIndex(of: id)
    }

    /// The index of the row whose id equals `id`, looked for outward from
    /// `origin` first — a change usually moves a row a few places — and then
    /// everywhere (``index(of:)``). What a hold asks on the frames whose rows
    /// moved under it (``holdTopRow()``, the `.row` anchor's): from the first
    /// row, a list scrolled deep and fed rows at its top read every id above
    /// the held row on every frame that brought some — and an id can cost a
    /// build of its row (``id(at:)``).
    ///
    /// What that comes to: a row moved by k places, k up to 64, is found in
    /// about 2k id reads. One moved further — a "load earlier" of a hundred
    /// rows — costs 129 reads and then the scan from the first row, which stops
    /// at it: O(the row's position), not O(k). An id that is nowhere — the top
    /// row deleted (a delete chord on the top row), or its id changed — costs
    /// 129 reads and a scan of every id: O(n), each read maybe a build of its
    /// row, wherever the list is scrolled.
    func index(of id: SelectionValue, near origin: Int) -> Int? {
        for distance in 0...64 {
            for candidate in distance == 0 ? [origin] : [origin - distance, origin + distance]
            where self.id(at: candidate) == id {
                return candidate
            }
        }
        return index(of: id)
    }

    /// ``itemIDs`` and ``selectableIndices``, together.
    typealias RowAnswers = (itemIDs: [SelectionValue?], selectableIndices: Set<Int>)

    /// Sets ``itemIDs`` and ``selectableIndices`` together, dropping any
    /// answers ``answerRowsWhenAsked(idAt:settling:)`` left unsettled rather
    /// than settling them first — what a list hands over on each frame it
    /// knows them.
    func answerRows(_ answers: RowAnswers) {
        unsettledRowAnswers = nil
        (settledItemIDs, settledSelectableIndices) = answers
    }

    /// Hands over ``itemIDs`` and ``selectableIndices`` unsettled: `answers`
    /// runs the first time either is read (or written), and on a frame nothing
    /// reads them it never runs. Replaces any answers still unsettled.
    ///
    /// For a list whose rows' ids are costly to learn all at once, of which a
    /// frame needs only a few. One row's id is not free either: it can cost a
    /// build of that row, or of looped rows beside it (see ``id(at:)``).
    /// `idAt` becomes ``idAt``, which is what ``id(at:)`` and ``index(of:)``
    /// ask, so a frame asks about the rows it draws and the row it focuses;
    /// and until the answers settle, the keys that move the cursor ask it too,
    /// a row at a time, where the cursor may land (see
    /// ``firstLandingRow(orElse:)``), and so does a bottom-anchored follow for
    /// the last row. It must name exactly the rows `answers` would: a row it
    /// answers `nil` for is one `answers` leaves out of a non-empty
    /// ``selectableIndices``. Only select-all, of the handler's own readers,
    /// settles the rest. The answers are the ones `answers` would have given
    /// at hand-over; settling later asks the same rows the same questions.
    func answerRowsWhenAsked(
        idAt: @escaping (Int) -> SelectionValue?, settling answers: @escaping () -> RowAnswers
    ) {
        self.idAt = idAt
        unsettledRowAnswers = answers
        unsettledNamedRowBounds = (nil, nil)
    }

    /// Runs the unsettled answers, if there are any, into their storage.
    private func settleRowAnswers() {
        guard let answers = unsettledRowAnswers else { return }
        unsettledRowAnswers = nil
        (settledItemIDs, settledSelectableIndices) = answers()
    }

    /// Whether ``itemIDs`` and ``selectableIndices`` were handed over unsettled
    /// and nothing has settled them since — for the tests that pin which
    /// readers settle them. Asking settles nothing.
    var rowAnswersAreUnsettled: Bool { unsettledRowAnswers != nil }

    // MARK: Where the cursor may land

    /// The unsettled answers' ``idAt``, when there are unsettled answers to
    /// ask — `nil` when the landing set should be read whole.
    private var unsettledIDAt: ((Int) -> SelectionValue?)? {
        unsettledRowAnswers == nil ? nil : idAt
    }

    /// `selectableIndices.min() ?? fallback` — the first row the cursor can
    /// land on — answered without settling unsettled answers.
    ///
    /// Unsettled, it is the first row ``idAt`` names, or `fallback` if none is
    /// named: exactly the settled answer. When every row is named the settled
    /// set is EMPTY (all content) and the answer is `fallback`, which the
    /// callers pass as the first row; when none is, the set is empty too and
    /// both answer `fallback`; otherwise the set holds exactly the named rows.
    func firstLandingRow(orElse fallback: Int) -> Int {
        guard let idAt = unsettledIDAt else { return selectableIndices.min() ?? fallback }
        if let known = unsettledNamedRowBounds.first { return known ?? fallback }
        let first = (0..<itemCount).first { idAt($0) != nil }
        unsettledNamedRowBounds.first = .some(first)
        return first ?? fallback
    }

    /// `selectableIndices.max() ?? fallback`, answered the same way — see
    /// ``firstLandingRow(orElse:)``.
    func lastLandingRow(orElse fallback: Int) -> Int {
        guard let idAt = unsettledIDAt else { return selectableIndices.max() ?? fallback }
        if let known = unsettledNamedRowBounds.last { return known ?? fallback }
        let last = (0..<itemCount).reversed().first { idAt($0) != nil }
        unsettledNamedRowBounds.last = .some(last)
        return last ?? fallback
    }

    /// `!selectableIndices.isEmpty` — whether a move has to check each row it
    /// lands on — answered without settling: unsettled, always `true`, since
    /// ``isInLandingSet(_:)`` then answers every row as the settled set would,
    /// and where every row is landable the checked move lands exactly where
    /// the unchecked one does.
    var landingSetMayRestrict: Bool {
        unsettledIDAt != nil || !selectableIndices.isEmpty
    }

    /// `selectableIndices.isEmpty || selectableIndices.contains(index)`,
    /// answered without settling for a row of the list: a row ``idAt`` names,
    /// or any row where none is named — where the settled set is empty, which
    /// reads as "no restriction".
    func isInLandingSet(_ index: Int) -> Bool {
        guard let idAt = unsettledIDAt, (0..<itemCount).contains(index) else {
            return selectableIndices.isEmpty || selectableIndices.contains(index)
        }
        if idAt(index) != nil { return true }
        let fallback = -1
        return firstLandingRow(orElse: fallback) == fallback
    }
}

// MARK: - Focus Lifecycle

extension ItemListHandler {
    package func onFocusLost() {
        // Extend mode is a transient interaction state of THIS focus tenure —
        // arrows silently extending the selection after tabbing away and back
        // would be a surprise.
        isExtendingSelection = false

        // A row in hand is the same: the keys that would place it have gone
        // with the focus, so put it back rather than leaving it stranded.
        if isKeyboardMove { cancelKeyboardMove() }

        // …and so is a picked column: the keys that move it went too — unless
        // the focus went to the column menu, which Return opened on the
        // picked column and which hands the focus back when it closes. That
        // menu is the mode's own: ending the mode there left the user, back
        // at the table, in a mode they had not left, and Escape — still meant
        // to let the column go — clearing the selection instead.
        if columnEditing?.menuIsOpen() != true { columnFocus = nil }

        // A row's own menu, opened on the cursor row, is the cursor's: the
        // focus comes back to it when the menu closes.
        if focusLeavesForRowMenu {
            focusLeavesForRowMenu = false
            return
        }

        // When focus is lost, put the cursor on the selection (if any) so that
        // when focus returns, the user sees it: on the selected row, or for a
        // multi-selection on the first selected row in the rows' order —
        // unless the cursor is on a selected row already, which shows it as
        // well as any. Not the first of the selection `Set`: a `Set`'s order
        // is the process's hash seed, so which of several selected rows the
        // cursor came back to differed from one run to the next.
        switch selectionMode {
        case .single:
            if let selection = singleSelection?.wrappedValue,
                let index = index(of: selection)
            {
                focusedIndex = index
            }
        case .multi:
            guard let selection = multiSelection?.wrappedValue, !selection.isEmpty else { break }
            func selected(_ index: Int) -> Bool { id(at: index).map(selection.contains) ?? false }
            if !selected(focusedIndex), let index = (0..<itemCount).first(where: selected) {
                focusedIndex = index
            }
        }

        // Deliberately NOT revealing that index here. A list the user has just
        // left must not scroll itself: clicking a checkbox beside a table the
        // user had arrowed away from its selection would yank the rows out from
        // under the click — dozens of rows, whenever cursor and selection had
        // parted company, which is exactly why it looked intermittent.
        // ``onFocusReceived()`` reveals it when focus comes back, which is when
        // the comment above actually cares.
    }

    package func onFocusReceived() {
        // Ensure the focused item is visible when focus is received
        ensureFocusedItemVisible()
    }
}

// Its indicators drawn over the rows follow the pointer — see the protocol.
extension ItemListHandler: ScrollIndicatorPointerTracking {
    /// Decides whether this frame draws the indicators over the rows —
    /// ``overlaysScrollbar`` and ``overlaysTextIndicators`` — as a `List` and a
    /// `Table` both do: under `.scrollIndicatorPlacement(.overContent)`, with
    /// the pointer over the control and the rows overflowing. Nothing is
    /// reserved for them, so only the drawing learns of it.
    ///
    /// - Parameters:
    ///   - overflowing: Whether the rows overflow the content area.
    ///   - contentHeight: The content area's height, in lines: the "N more"
    ///     lines need ``ResolvedScrollIndicators/minimumTextHeight`` of them.
    ///   - environment: The control's environment.
    package func resolveOverlaidIndicators(overflowing: Bool, contentHeight: Int, environment: EnvironmentValues) {
        let overlaid = environment.overlaidVerticalScrollIndicators(overflowing: overflowing, hovered: isPointerOver)
        overlaysScrollbar = overlaid.bar
        overlaysTextIndicators = overlaid.text && contentHeight >= ResolvedScrollIndicators.minimumTextHeight
    }
}
