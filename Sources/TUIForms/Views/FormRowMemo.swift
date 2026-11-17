//  🖥️ TUI — A Terminal UI framework for Swift
//  FormRowMemo.swift
//
//  A form's rows a loop over comparable data made are memoised by their
//  element, as a `ForEach`'s rows are anywhere else (`ForEach.makeChild`), so
//  a frame that changes one of them, or none, runs and measures that one and
//  serves the others (PERFCASE-F7). Before, the form read its content into
//  rows afresh every pass and drew each one through views nothing could
//  compare, so every toggle of a form ran its body and was measured a dozen
//  times a frame, whatever the frame changed.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// `StateStorage` property index for `_FormLayout`'s walk version (file
/// scope: a generic type cannot hold static storage).
private enum FormWalkStateIndex {
    /// The version of what the form's content walk read
    /// (``_FormWalkVersionKeeper``). Negative: the form's content is drawn at
    /// its own identity. Range -230, claimed in ``StateStorage/StateKey``'s
    /// table (-230 is the windowed form's kept widths).
    static let walkVersion = -231
}

/// Where the walk's mark is kept in the render cache, beside anything else
/// kept at the walk's identity (`RenderCache.store(…slot:)`).
private let formWalkMarkSlot = 0x2F0A_7C51

/// One version of what a form's content walk read: the same from frame to
/// frame while nothing the walk read changed, and a new one when something
/// did. A class, so its identity is the version, as `DataVersion.Token`'s is:
/// an entry holding it keeps it alive, so no later version can reuse its
/// address.
///
/// The form reads its content at a place of its own (``_FormContentWalk``),
/// and a loop's closure, a view of the app's own read through its body and
/// that view's `@State` are evaluated, observed and kept there — not where the
/// rows are drawn, which is a cousin of it. A write to what the walk read
/// clears the walk's place and everything above it, the form included, but
/// not the rows drawn beside it: a row memoised by its element alone would be
/// served with a title its loop's closure read from somewhere the write
/// changed. So the rows are memoised under this version too, and it changes
/// whenever the walk's place has been cleared (``_FormLayout/walkVersion(context:)``).
///
/// A walk's place cleared is every memoised row cleared, or missed for its new
/// version, so a form cleared on every pass — one in a page that reads a clock,
/// scrolled each tick — would build each row's memo and serve none of it:
/// 1,020 rows' pictures and 7,000 sizes stored a frame on `app-shapes/grouped-form`,
/// all cleared at the next. A version taken on the third pass in a row that
/// renews it does not memoise (``memoisesRows``): those rows are drawn afresh,
/// as before the memo, until a pass finds the mark again. Not the second: every
/// page's second pass may be the clear its first asked for, having learned that
/// a type reads (`RenderCache.noteReads`), and a form that opens memoises.
final class _FormWalkVersion: Equatable, Sendable {
    /// Whether the rows drawn under this version are memoised.
    let memoisesRows: Bool

    init(memoisesRows: Bool) { self.memoisesRows = memoisesRows }

    static func == (lhs: _FormWalkVersion, rhs: _FormWalkVersion) -> Bool { lhs === rhs }
}

/// The current walk version of one form, kept with its state. A class, so the
/// version can be replaced without writing the state box, which would clear
/// the form.
@MainActor
final class _FormWalkVersionKeeper {
    var current = _FormWalkVersion(memoisesRows: true)
    /// The pass ``current`` was decided in: a form asked again in the same
    /// pass (its windowed columns, once a measure and once the draw) is
    /// handed the same version.
    var decidedPass: UInt32?
    /// How many passes in a row, up to that one, renewed the version: two,
    /// and the rows of a third that renews it are not memoised.
    var renewals = 0
}

/// A memoised row's key: the loop element it was made from, the label column
/// it is laid out against, what of its place in that column it was read with,
/// and the walk it was read in. What is drawn around the row — a frame to the
/// content width, the control column's indent for a button — is outside the
/// memo, and not in the key.
struct _FormLoopRowKey<Element: Equatable>: Equatable {
    let element: Element
    let pillar: Int
    let leadingInset: Int
    let hidesLabel: Bool
    let walk: _FormWalkVersion
}

/// A row made by a loop inside another loop: keyed by both elements, as its
/// closure may have read either.
struct _FormNestedLoopElement: Equatable {
    let outer: AnyEquatableBox
    let inner: AnyEquatableBox

    init(outer: any Equatable, inner: any Equatable) {
        self.outer = AnyEquatableBox(outer)
        self.inner = AnyEquatableBox(inner)
    }
}

/// What a memoised row is built from on a miss.
struct _FormRowSource {
    let row: _FormRow
    let pillar: Int
}

/// `row` in the form's row memo, keyed by its loop element (``_FormLoopRowKey``):
/// served from the cache while the key is the same, and drawn as
/// ``unmemoizedRowView(_:pillar:)`` draws it when not. The memo is the one a
/// `ForEach` row has (`_MemoizedRow`), with its contract: a row is a pure
/// function of its element and of what its own views observe.
@MainActor
func memoizedRowView(_ element: any Equatable, row: _FormRow, pillar: Int, walk: _FormWalkVersion) -> AnyView {
    func memoized<Element: Equatable>(_ element: Element) -> AnyView {
        AnyView(
            _MemoizedRow(
                element: _FormLoopRowKey(
                    element: element, pillar: pillar, leadingInset: row.leadingInset, hidesLabel: row.hidesLabel,
                    walk: walk),
                source: _FormRowSource(row: row, pillar: pillar),
                build: { source in unmemoizedRowView(source.row, pillar: source.pillar) }))
    }
    return memoized(element)
}

/// What a form measures a row's width under while it finds its content width:
/// for a row it memoises, a place of its own below the form's, by the row's
/// position, so the size kept for it is its own rather than the last row's
/// measured at the form's one place; for any other row, the form's context, as
/// before.
enum _FormRowWidth {}

@MainActor extension _FormLayout {
    func rowWidthContext(
        _ row: _FormRow, ordinal: Int, walk: _FormWalkVersion?, context: RenderContext
    ) -> RenderContext {
        guard walk?.memoisesRows == true, row.loopElement != nil else { return context }
        let rowContext = context.withChildIdentity(type: _FormRowWidth.self, index: ordinal)
        // A memo's measure marks nothing alive, and the size it keeps here —
        // below the branches the row's views take, not at this place itself —
        // would be swept at the pass's end: kept for as long as the form asks
        // for the row (as `ForEach`'s list rows mark theirs, `makeListRowContent`).
        rowContext.renderCache?.retainSubtree(rowContext.identity)
        return rowContext
    }

    /// The version of what this form's content walk read (``_FormWalkVersion``):
    /// the one kept, while the mark it left at the walk's place last pass is
    /// still there, and a new one when the mark has gone — cleared by a write
    /// to something the walk read, or above it, or by the cache being emptied.
    /// A new one on the third pass in a row to take one does not memoise.
    /// `nil` outside a render loop, where nothing is memoised.
    func walkVersion(context: RenderContext) -> _FormWalkVersion? {
        guard let cache = context.renderCache, let stateStorage = context.stateStorage else { return nil }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: FormWalkStateIndex.walkVersion)
        let box: StateBox<_FormWalkVersionKeeper> = stateStorage.storage(for: key, default: _FormWalkVersionKeeper())
        stateStorage.markActive(context.identity)
        let keeper = box.value
        let walk = context.withChildIdentity(type: _FormContentWalk.self).identity
        cache.markActive(walk)
        let marked = cache.lookupEntryRechecking(
            identity: walk, view: keeper.current, contextWidth: 0, contextHeight: 0, gradientFrame: nil,
            surfaceBackground: nil, effectScope: .none, animationMustBeCurrent: false, rebuild: {},
            recheckingUnder: nil, depth: 0, slot: formWalkMarkSlot)
        let renewed = marked == nil
        let memoises: Bool
        let pass = stateStorage.currentPass
        if keeper.decidedPass == pass {
            // Asked again in the pass (a windowed form's measure, then its
            // draw; a walk made again for what effects wrote): whether it
            // memoises is the pass's, but a mark a write cleared in between
            // still renews the version.
            memoises = keeper.current.memoisesRows
            if renewed, keeper.renewals == 0 { keeper.renewals = 1 }
        } else {
            // Renewed three times running: the rows are cleared pass after
            // pass, and a memo would only be built to be thrown away. Found
            // again after that: memoised from here on, under a version of its
            // own.
            memoises = !(renewed && keeper.renewals >= 2)
            keeper.decidedPass = pass
            keeper.renewals = renewed ? keeper.renewals + 1 : 0
        }
        if renewed || memoises != keeper.current.memoisesRows {
            keeper.current = _FormWalkVersion(memoisesRows: memoises)
            cache.store(
                identity: walk, view: keeper.current, buffer: FrameBuffer(), contextWidth: 0, contextHeight: 0,
                gradientFrame: nil, surfaceBackground: nil, recorded: (effects: [], scope: .none, lease: nil),
                slot: formWalkMarkSlot)
        }
        return keeper.current
    }
}
