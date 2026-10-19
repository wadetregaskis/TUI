//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationToolbarItems.swift
//
//  The toolbar items a sheet or a full-screen cover hosts: declared anywhere
//  in its content, drawn at its own edges — a row along its top, its button
//  row along its bottom — in rows reserved from the frame before, as the
//  window's bars are.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Items

/// The toolbar items a sheet or a full-screen cover hosts at its edges
/// (decisions D5C, B-D5C-3's fuller version): the items a `.toolbar` anywhere
/// in the presented content declares, and its `.toolbarVisibility` statements
/// for the two rows.
///
/// A presentation keeps one for its life (TUIkitPresentation's presenter, in
/// its state), and draws round its content:
///
/// - ALONG ITS TOP, every placement but those of the button row, laid out as
///   the window's top bar lays them out, with no title;
/// - ALONG ITS BOTTOM, the button row: ``ToolbarItemPlacement/destructiveAction``
///   items leading, the bottom bar's placements, and
///   ``ToolbarItemPlacement/cancellationAction`` then
///   ``ToolbarItemPlacement/confirmationAction`` trailing — the confirmation
///   button its default button, the cancellation one its cancel button.
///
/// The rows' heights have to be known before the content is laid out, and the
/// content is what declares their items, so they are LAST frame's answer, as
/// the window's bars' are (the A28 study's policy P2): the frame is drawn at
/// the rows reserved, and a change is adopted the next frame, which is asked
/// for. A presentation's first frame has no last frame: it seeds the rows
/// from a measure of its content, so a sheet opens with its rows.
@MainActor
package final class PresentationToolbarItems {
    /// The items the content declared this walk, in declaration order.
    private(set) var entries: [WindowChromeState.ToolbarEntry] = []

    /// Their identities, so an item a walk renders twice is declared once.
    private var identities: Set<ViewIdentity> = []

    /// The rows the content's `.toolbarVisibility` hid this walk.
    private var hiddenRows: Set<WindowChromeState.Edge> = []

    /// The rows of the top row and the button row this frame is laid out
    /// with: last frame's answer.
    private(set) var reserved = (top: 0, bottom: 0)

    /// Whether the content's declarations are being found by the
    /// presentation's first frame's seed, a measuring render.
    private(set) var isSeeding = false

    /// Whether the rows have been seeded.
    private var isSeeded = false

    package init() {}

    /// Forgets the rows, for a presentation presented again: its first frame
    /// seeds them afresh.
    package func startOver() {
        isSeeded = false
        reserved = (0, 0)
    }

    /// Forgets the last walk's items and statements.
    private func begin(seeding: Bool) {
        entries.removeAll(keepingCapacity: true)
        identities.removeAll(keepingCapacity: true)
        hiddenRows.removeAll(keepingCapacity: true)
        isSeeding = seeding
    }

    /// Records an item the content declared — once per identity.
    func declare(_ entry: WindowChromeState.ToolbarEntry) {
        guard identities.insert(entry.identity).inserted else { return }
        entries.append(entry)
    }

    /// Records a `.toolbarVisibility(_:for:)` the content declared for one of
    /// the rows: the top row for the window toolbar's placements, the button
    /// row for the bottom bar's. The one closest to the content wins.
    func declare(_ visibility: Visibility, for edge: WindowChromeState.Edge) {
        switch visibility {
        case .hidden: hiddenRows.insert(edge)
        case .visible: hiddenRows.remove(edge)
        case .automatic: break
        }
    }

    /// The items of the top row (`.top`) or the button row (`.bottom`), less
    /// a hidden row's.
    private func entries(_ edge: WindowChromeState.Edge) -> [WindowChromeState.ToolbarEntry] {
        guard !hiddenRows.contains(edge) else { return [] }
        return entries.filter { $0.placement.isPresentationButtonRow == (edge == .bottom) }
    }
}

// MARK: - Hosting

extension PresentationToolbarItems {
    /// The presented content drawn by `draw` — handed a context and the cap on
    /// its height, both less the rows reserved — with the rows at its edges.
    ///
    /// `seed` draws the content in the context it is handed and throws the
    /// picture away: on the first frame, in a measuring context, whose only
    /// output is the items the content declares — the run loop's first-frame
    /// walk, for a presentation. A measuring render rather than a measure,
    /// because a measure need not visit every view (a stack may measure its
    /// children by any route), and the seed must see every `.toolbar`. The
    /// rows are the content's width, or as wide as they need, up to what the
    /// presentation is offered; their controls follow the content's in the
    /// presentation's focus section.
    @MainActor
    package func hosting(
        context: RenderContext, capHeight: Int, seed: (RenderContext) -> Void,
        draw: (RenderContext, Int) -> FrameBuffer
    ) -> FrameBuffer {
        if !context.isMeasuring, !isSeeded {
            begin(seeding: true)
            var seeding = context
            seeding.isMeasuring = true
            // Nothing memoised: a throwaway walk's measures and pictures would
            // otherwise be served to the drawn one, in the same pass.
            seeding.renderCache = nil
            seeding.environment.renderCache = nil
            seed(seeding)
            reserved = needed(context: context)
            isSeeded = true
        }
        begin(seeding: false)
        let rows = reserved.top + reserved.bottom
        var inner = context
        inner.availableHeight = max(0, context.availableHeight - rows)
        let content = draw(inner, max(0, capHeight - rows))
        guard !context.isMeasuring else { return content }

        let top = entries(.top)
        let bottom = entries(.bottom)
        let natural = (top: naturalSize(top, context: context), bottom: naturalSize(bottom, context: context))
        let width = min(
            max(0, context.availableWidth), max(content.width, natural.top.width, natural.bottom.width))
        var buffer = FrameBuffer()
        var drawn = Set<ViewIdentity>()
        if reserved.top > 0 {
            buffer.appendVertically(row(top, index: 0, width: width, height: reserved.top, drawn: &drawn, context: context))
        }
        buffer.appendVertically(content)
        if reserved.bottom > 0 {
            buffer.appendVertically(
                row(bottom, index: 1, width: width, height: reserved.bottom, drawn: &drawn, context: context))
        }
        retainUndrawn(drawn: drawn, context: context)

        // This walk's rows become the next frame's.
        let wanted = (top: natural.top.height, bottom: natural.bottom.height)
        if wanted != reserved {
            reserved = wanted
            context.requestAnimation(
                token: "presentation-toolbar-adoption", frameTicks: AnimationClock.standardFrameTicks)
        }
        return buffer
    }

    /// The rows this walk's items want, as the seed takes them.
    @MainActor
    private func needed(context: RenderContext) -> (top: Int, bottom: Int) {
        (naturalSize(entries(.top), context: context).height, naturalSize(entries(.bottom), context: context).height)
    }

    /// The row of `entries` at its natural size — its items side by side, its
    /// spacers at their least — or zero with none.
    @MainActor
    private func naturalSize(_ entries: [WindowChromeState.ToolbarEntry], context: RenderContext) -> ViewSize {
        guard !entries.isEmpty else { return ViewSize(width: 0, height: 0) }
        return measureChild(
            _ToolbarBarRow(entries: entries, title: "", subtitle: "", isPresentation: true),
            proposal: .unspecified, context: rowContext(0, context: context).askingIdealWidth())
    }

    /// The row of `entries`, drawn in `height` rows at `width`.
    @MainActor
    private func row(
        _ entries: [WindowChromeState.ToolbarEntry], index: Int, width: Int, height: Int,
        drawn: inout Set<ViewIdentity>, context: RenderContext
    ) -> FrameBuffer {
        var rowContext = rowContext(index, context: context)
        rowContext.availableWidth = width
        rowContext.hasExplicitWidth = true
        rowContext.availableHeight = height
        for entry in entries { drawn.insert(entry.identity) }
        let buffer = TUIkitView.renderToBuffer(
            _ToolbarBarRow(entries: entries, title: "", subtitle: "", isPresentation: true), context: rowContext)
        return buffer.fittedAsChrome(toRows: height, width: width, background: "")
    }

    /// The context a row is drawn in: an identity of its own under the
    /// presentation's.
    private func rowContext(_ index: Int, context: RenderContext) -> RenderContext {
        context.withChildIdentity(type: PresentationToolbarItems.self, index: index)
    }

    /// Keeps the `@State` of the items the content declared and the rows did
    /// not draw: a hidden row's, a row not yet adopted, as the window keeps a
    /// hidden bar's (`retainUndrawnItems`).
    private func retainUndrawn(drawn: Set<ViewIdentity>, context: RenderContext) {
        guard let storage = context.stateStorage else { return }
        for entry in entries where !drawn.contains(entry.identity) {
            storage.markActive(entry.identity)
            storage.retainSubtree(entry.identity)
        }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The toolbar items the sheet or cover this content is presented in
    /// hosts at its edges, or `nil` outside one (a popover's content draws its
    /// `.toolbar`'s items round the view it is attached to).
    package var presentationToolbar: PresentationToolbarItems? {
        get { self[featureObject: .presentationToolbar] as? PresentationToolbarItems }
        set { self[featureObject: .presentationToolbar] = newValue }
    }
}
