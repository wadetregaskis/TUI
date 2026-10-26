//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuColumnLayout.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// Renders `items` as a menu: a bordered column of rows, sized to hug its
/// widest, scrolling inside `capHeight` if it cannot fit.
///
/// The shared body of every TUI menu — the `.contextMenu` popover, a pop-up
/// ``Menu``, and an inline one — so all three sit on the same grid and answer
/// to the same width arithmetic.
///
/// - Parameters:
///   - items: The menu's rows: `Button`s, `Toggle`s and `Divider`s, plus
///     whatever heading the caller puts above them.
///   - context: The context to lay out in; its `availableWidth` is the ceiling.
///   - capHeight: The height the menu must fit into, or 0 for no cap. A taller
///     menu scrolls inside it.
///   - borderColor: The frame's stroke, or `nil` for the palette's border colour.
///     A presented menu passes the breathing accent here — see
///     ``presentMenuPopover(items:over:controller:sectionID:itemsIndex:anchor:dismiss:context:)``.
///
/// This is the INLINE menu's assembly. A pop-up goes through
/// ``renderMenuPopup(_:context:controller:)`` instead, which hands the same
/// rows to the `Picker` drop-down's renderer — see
/// `Documentation/Controls and presentation/Unifying the menu implementations.md`.
@MainActor
func renderMenuColumn(
    _ items: some View, context: RenderContext, capHeight: Int, borderColor: Color? = nil
) -> FrameBuffer {
    let menuView = menuColumnFrame(items, borderColor: borderColor)
    let plan = planMenuColumn(menuView, context: context, capHeight: capHeight)
    // The arm drawn is recorded at this identity, as an `if`/`else` records its
    // branch, and a flip drops everything the menu drew before it: a menu
    // squeezed short of its rows and then given them back must not keep the
    // squeezed arm's scroll position, nor come back to it. Without the drop
    // that position outlived the scroll view wherever an ancestor was served
    // from the cache, which keeps everything under it alive, and a menu
    // squeezed again came back scrolled where an uncached one starts at the
    // top (the focus and mouse storm's trial 3, once columns share their
    // height). Recorded here rather than by a `ConditionalView`, whose branch
    // identity put every view in every menu one level deeper — hashed and
    // compared through that level in every lookup and prune below it, which
    // cost the menus scenario 4.4% — where only the rare squeezed arm needs an
    // identity of its own. Nothing else records a branch here: the menu is a
    // border, padding and a style round a `VStack`, and no `if`.
    if !context.isMeasuring, let storage = context.stateStorage,
        storage.recordConditionalBranch(context.identity, isTrueBranch: plan.scrolls)
    {
        storage.invalidateDescendants(of: context.identity)
    }
    guard plan.scrolls else {
        return renderToBuffer(menuView, context: plan.sized)
    }
    // Taller than its budget: scroll inside it. The scroll goes INSIDE the
    // border, not around it — a ScrollView's "N more above/below" indicators
    // replace its first and last visible rows, which around the border would
    // eat the border itself. The content renders at its full height inside the
    // viewport, which is what lets the reveal bring an off-screen item back
    // (`ScrollViewReveal`). Its rows are the focus stops, never the scroller.
    let scrolled = ScrollView(.vertical) { menuColumnBody(items) }
        .withoutFocusStop()
        .asChrome()
        .frame(height: max(1, capHeight - 2))
        .bordered(
            style: nil, colour: borderColor.map(AnimatedColor.init), width: 1, keepsSelectionInside: false)
    return renderToBuffer(
        scrolled, context: plan.sized.withAvailableHeight(capHeight).withBranchIdentity("scrolled"))
}

/// The size ``renderMenuColumn(_:context:capHeight:borderColor:)`` comes back
/// as, without drawing a cell.
///
/// It can answer from the plan alone because the plan is what decides the
/// menu's size: the width is its hug clamped to the space, and the height is
/// either the content's or the cap it scrolls inside. Nothing downstream of
/// that adds a row or a column — the border is already inside the measured
/// view, and the scrolled arm is framed to exactly the cap.
///
/// It matters because a menu was drawn to be measured. Two-pass layout measures
/// a stack's children before it renders them, so an inline `Menu` in a page
/// rendered its whole column twice a frame and threw one away — and each of
/// those renders measures the column again first, for the hug. Four walks of
/// the tree to put one menu on screen; this makes it three.
/// `MenuMeasureParityTests` renders the matrix and compares, because "the same
/// plan" is a claim about code that has to be checked against what it draws.
@MainActor
func measureMenuColumn(
    _ items: some View, context: RenderContext, capHeight: Int, borderColor: Color? = nil
) -> ViewSize {
    let menuView = menuColumnFrame(items, borderColor: borderColor)
    let plan = planMenuColumn(menuView, context: context, capHeight: capHeight)
    guard !plan.scrolls else { return ViewSize.fixed(plan.width, capHeight) }
    // ``MenuColumnPlan/drawnHeight`` has already accounted for any reflow: the
    // plan had to know the drawn height to decide whether the menu scrolls at
    // all, so the one walk that answers it serves both questions.
    return ViewSize.fixed(plan.width, plan.drawnHeight)
}

/// The menu's rows, styled and padded — everything inside the border.
///
/// The items are `Button`s (SwiftUI's API, which TUI matches), but a menu's
/// rows must not LOOK like buttons — `_MenuItemButtonStyle` draws them as menu
/// rows, the same idiom as the Picker drop-down. A `Toggle` in a POP-UP menu is
/// one of those buttons too (`_ToggleCore`); in an inline menu, whose rows are
/// page focus stops, it stays the ordinary control.
///
/// A `Section` among the items is drawn as a menu draws one
/// (``_MenuSectionedItems``): between separators, under a header that is no
/// row.
@MainActor
private func menuColumnBody(_ items: some View) -> some View {
    VStack(alignment: .leading, spacing: 0) { _MenuSectionedItems(items: items) }
        .buttonStyle(_MenuItemButtonStyle())
        .padding(.horizontal, 1)
}

/// ``menuColumnBody(_:)`` in its border — the whole menu, as one view.
@MainActor
private func menuColumnFrame(_ items: some View, borderColor: Color?) -> some View {
    menuColumnBody(items)
        .bordered(
            style: nil, colour: borderColor.map(AnimatedColor.init), width: 1, keepsSelectionInside: false)
}

/// Where a menu column sits and how big it is — the one owner of the hug
/// arithmetic, so the measure and the render cannot answer differently.
private struct MenuColumnPlan {
    /// The width the menu draws at.
    var width: Int
    /// The height the column actually draws at ``width``.
    ///
    /// The hug height where nothing was squeezed, and the RE-MEASURED height
    /// where it was. A hugging row is measured against the menu's whole
    /// interior, while a drawn one gets that interior less the hint column
    /// beside it, and a label can wrap into the difference — so where the hug
    /// wanted every cell it was offered, its height is a lower bound and not the
    /// number anything should be decided from.
    ///
    /// Deciding from it is exactly what went wrong: the overflow probe was gated
    /// on the hug height, so a menu whose rows reflowed PAST the cap while
    /// hugging under it never asked the question, took the non-scrolling arm, and
    /// had its trailing rows clipped away with no scrollbar and no way to reach
    /// them.
    var drawnHeight: Int
    /// The context it draws in: clamped to `width`, with the row width and the
    /// menu verb handed down, in a measure generation of its own.
    var sized: RenderContext
    /// Whether the content is taller than the cap, so the menu scrolls inside
    /// its border rather than hugging.
    var scrolls = false
}

/// The width a row of a menu `menuWidth` cells wide is actually drawn into — the
/// one owner of that arithmetic, because it is the number every row pads its own
/// label to and a row that believes a cell it does not have is clipped there.
///
/// The chrome is 6 cells, not 4: `.bordered()` is a `ContainerView`, which insets
/// its content by one cell on each side on top of its two border columns, and
/// ``menuColumnBody(_:)``'s `.padding(.horizontal, 1)` adds two more. Getting
/// this wrong told the rows they had two cells they did not, which the border
/// then clipped — invisible while a row was just a left-aligned label, fatal
/// once a row has something at its trailing edge.
///
/// - Parameters:
///   - menuWidth: The width the whole menu, border included, draws at.
///   - scrollbarColumn: Whether a `ScrollView`'s vertical bar has taken a
///     trailing column out of the interior as well — true only on the scrolled
///     arm, and only when that arm's bar is the reserving kind. Ask
///     ``EnvironmentValues/verticalScrollIndicators(overflowing:)``, which is
///     what the `ScrollView` resolves its own bar from, rather than deriving it
///     again here.
private func menuRowWidth(menuWidth: Int, scrollbarColumn: Bool) -> Int {
    max(1, menuWidth - 6 - (scrollbarColumn ? 1 : 0))
}

/// Sizes `menuView` to its own content and prepares the context it draws in.
@MainActor
private func planMenuColumn(
    _ menuView: some View, context: RenderContext, capHeight: Int
) -> MenuColumnPlan {
    // Size the menu to its own content before rendering it. Laying it out
    // against the whole screen made a menu of three short items span the
    // terminal: `Divider` MEASURES as one cell but RENDERS at the width it is
    // offered, and a VStack takes its width from what its children actually
    // drew — so one separator inflated the popover to whatever it was handed.
    // Measuring first (where the divider claims its true one cell and the
    // buttons hug their labels) yields the natural hug width; rendering at that
    // width then makes the divider span exactly the menu's interior, which is
    // the separator look we want anyway.
    //
    // Measured through the SAME context the render uses, so `@State` and focus
    // slots resolve to the same identities either way (362c8839).
    let natural = measureChild(
        menuView,
        proposal: ProposedSize(
            width: context.availableWidth, height: capHeight > 0 ? capHeight : nil),
        context: context)
    let menuWidth = max(1, min(natural.width, context.availableWidth))
    var sized = context.withAvailableWidth(menuWidth)
    // Now that the width is known, hand it to the rows so their highlight reads
    // as a bar across the menu rather than a tag around the label. Deliberately
    // AFTER the measure: a row that knew its width up front would report it, and
    // the menu would size itself from its own guess.
    //
    // Without the scrollbar column: whether there IS one is not known until the
    // overflow probe below has run, and the probe needs a row width to run at.
    // The scrolled arm re-states it.
    sized.environment.menuRowWidth = menuRowWidth(menuWidth: menuWidth, scrollbarColumn: false)
    // For the Return verb: a row of an open pop-up is a row of a menu too.
    sized.environment.isInsideMenu = true
    // Everything from here down is a DIFFERENT question from the hug above, and
    // the measure memo has to be told so: it keys on identity, widths, view type
    // and view bytes, and on this arm `menuWidth == context.availableWidth`, so
    // the hug and the draw are one key. It answered the draw with the hug — at
    // `_ButtonCore`, whose size comes from the `ButtonStyle` it reads out of the
    // environment, so no amount of moving the row width into a view's value can
    // separate them. See ``RenderContext/measureGeneration``; 20 stale serves on
    // one walk of the Example without this line.
    sized = sized.invalidatingMeasureMemo()

    // Two questions remain, and ONE walk answers both: how tall the column
    // actually draws, and whether that clears the cap.
    //
    // The hug height answers neither on its own. It is a lower bound: a hugging
    // row is measured against the menu's whole interior while a drawn one gets
    // that interior less the hint column beside it, so a label with a space in
    // it wraps into the difference and the column comes out taller than the hug
    // said. And it cannot answer the cap question in either direction, because a
    // measure is CLAMPED to the context's `availableHeight` — for an inline menu
    // the cap IS that height — so a hug that comes back exactly at the cap might
    // have been truncated and one below it demonstrably was not.
    //
    // So the walk is against a budget ONE ROW past the cap, in the context the
    // rows are actually drawn in. A report at `capHeight + 1` was clamped, which
    // is precisely "it does not fit"; anything at or below the cap is the
    // column's own drawn height, which is the other thing wanted. (Where this
    // used to offer `max(capHeight * 64, 4096)` it was a ceiling wearing a
    // generous canvas's clothes, and cost a walk 4,096 rows deep to learn one
    // bit. How FAR past the cap the content goes is nobody's business here: the
    // scrolled arm frames its viewport at the cap and its `ScrollView` measures
    // its own content with no limit at all.)
    //
    // Skipped when nothing can have moved: an unclamped menu gave every row at
    // least the width it asked for, so nothing reflows, and a hug strictly under
    // the cap was not truncated either — the hug height IS the drawn height and
    // the answer is already known. That is the common case (a handful of rows in
    // a terminal-sized slot), and it is what keeps this off the ordinary path.
    //
    // The gate used to be `natural.height >= capHeight` alone, and that is the
    // bug: a menu whose rows reflowed PAST the cap while hugging under it never
    // asked, took the non-scrolling arm, and had its trailing rows clipped away
    // with no scrollbar and no way to reach them. Six rows at width 26 against a
    // twelve-row cap: the hug is eight rows and the draw is fourteen.
    let wasSqueezed = natural.width >= context.availableWidth
    guard capHeight > 0, wasSqueezed || natural.height >= capHeight else {
        return MenuColumnPlan(width: menuWidth, drawnHeight: natural.height, sized: sized)
    }
    let drawnHeight = measureChild(
        menuView, proposal: ProposedSize(width: menuWidth, height: nil),
        context: sized.withAvailableHeight(capHeight + 1)
    ).height
    let fits = MenuColumnPlan(
        width: menuWidth, drawnHeight: min(drawnHeight, capHeight), sized: sized)
    guard drawnHeight > capHeight else { return fits }
    var scrolls = fits
    scrolls.scrolls = true
    // The scrolled arm slips a `ScrollView` between the padding and the border,
    // and a vertical scrollbar is a COLUMN out of its viewport for the bar's
    // whole height — so a row there gets one cell less than the hugging arm's
    // chrome accounts for. Told otherwise, every row drew one cell too wide and
    // the border clipped the last of them: a menu whose rows carry key
    // equivalents lost the entire hint the moment it began to scroll, because a
    // one-character shortcut is one cell of hint behind one cell of gap.
    //
    // `overflowing: true` because taking this arm IS the overflow — `drawnHeight`
    // cleared the cap. A subtree under `.scrollIndicators(.hidden)` or
    // `.scrollIndicatorStyle(.text)` reserves no column and comes back false,
    // which is the same answer the `ScrollView` will reach.
    let scrollbarColumn = scrolls.sized.environment
        .verticalScrollIndicators(overflowing: true).bar
    guard scrollbarColumn else { return scrolls }
    scrolls.sized.environment.menuRowWidth = menuRowWidth(
        menuWidth: menuWidth, scrollbarColumn: true)
    // …and, having changed what a row measures to, say so, or the `ScrollView`'s
    // own extent walk can be answered from the probe just above, which asked the
    // same rows at the wider chrome. See ``RenderContext/measureGeneration``.
    scrolls.sized = scrolls.sized.invalidatingMeasureMemo()
    return scrolls
}
