//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+Anchor.swift
//
//  How a `ScrollView` honours the EDGE anchor modes of
//  `Documentation/Layout and scrolling/Scroll anchoring.md` §1.1 — Bottom (follow-the-log) and Top —
//  from the declared `defaultScrollAnchor` and, equally, from a bound
//  `.anchorPosition`, which §3.2 defines as the code-side `anchor(to:)`.
//
//  Both are POSITIONAL policies: engagement is "the offset is already at that
//  edge", never a stored flag, so scrolling away releases them by construction
//  and scrolling back re-engages. The one thing that must be remembered across
//  frames is a *newly written* bound edge — see `adoptWrittenAnchor`.
//
//  And the third role, `ScrollAnchorRole.alignment`: where content shorter
//  than the viewport is drawn in it — see `alignmentShift`.
//
//  And what a framework scroller leaves to the page: the anchors, a bound
//  `.scrollPosition`, the scroll observers, an indicator flash and the
//  overscroll settings are the app's, for its own scroll views — see
//  `pageAnchorPosition(_:)` and its siblings.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - What a framework scroller leaves to the page

extension _ScrollViewCore {
    /// The settings an app states for ITS scroll views, as this view takes
    /// them: from the environment, or — for a framework scroller
    /// (``ScrollView/asChrome()``: a tall inline menu's column, a sheet's, a
    /// dialog body's) — none.
    ///
    /// They reach a framework scroller because nothing between the page and
    /// it resets them: a `.defaultScrollAnchor(.bottom)` or an
    /// `.anchorPosition($anchor)` on a page held a tall inline menu's column at
    /// its last item and wrote the menu's anchor into the app's binding; a
    /// `.scrollPosition($position)` sought the menu to the app's row; and an
    /// `onScrollGeometryChange` / `onScrollPhaseChange` on the page heard
    /// whichever scroller drew first claim it, a menu's included (scroll lane
    /// review 3, the class of e85278da0). The framework scroller reads none of
    /// them and passes them on untouched, so its content still reads them for
    /// its own scrollables, as the other settings ``ScrollView/asChrome()``
    /// lists. One accessor per setting, so every site that reads one asks
    /// this view rather than the environment.
    func pageAnchorPosition(_ environment: EnvironmentValues) -> AnchorPositionBinding? {
        isChrome ? nil : environment.anchorPosition
    }

    /// See ``pageAnchorPosition(_:)``: the declared `defaultScrollAnchor`
    /// modes, or none (`.window`, the default) for a framework scroller.
    func pageDeclaredAnchorModes(
        _ environment: EnvironmentValues
    ) -> (standing: ScrollAnchorMode, opening: ScrollAnchorMode?) {
        isChrome ? (.window, .window) : environment.declaredAnchorModes
    }

    /// See ``pageAnchorPosition(_:)``: the `.scrollPosition` binding.
    func pageScrollPosition(_ environment: EnvironmentValues) -> ScrollPositionBinding? {
        isChrome ? nil : environment.scrollPositionBinding
    }

    /// See ``pageAnchorPosition(_:)``: what the view keeps in place when the
    /// content above its top row changes — or the default, the top row, for a
    /// framework scroller.
    func pageWindowHold(_ environment: EnvironmentValues) -> ScrollWindowHold {
        isChrome ? .topRow : environment.scrollWindowHold
    }

    /// See ``pageAnchorPosition(_:)``: the scroll observers this view may
    /// claim.
    func pageScrollObservers(_ environment: EnvironmentValues) -> ScrollObservers {
        isChrome ? ScrollObservers() : environment.scrollObservers
    }

    /// See ``pageAnchorPosition(_:)``: how strongly this view's indicators
    /// flash on this frame (`scrollIndicatorsFlash`), or `nil` — always, for
    /// a framework scroller: a page's flash lit a tall menu's, a dialog
    /// body's and a framed container's bar each time one appeared (lane
    /// SCROLLB's review).
    func pageIndicatorFlash(_ handler: ScrollViewHandler, context: RenderContext) -> Double? {
        isChrome ? nil : handler.indicatorFlash.strength(context: context)
    }

    /// See ``pageAnchorPosition(_:)``: the overscroll allowances
    /// (`.scrollOverscroll`) and the bounce (`.scrollBounceBehavior(.always)`)
    /// this view takes — none for a framework scroller. A page's `.always`
    /// pushed a tall menu's column, a dialog body or a framed container two
    /// lines past its end, and a page's allowance as far as it said, where
    /// the wheel had passed on to the scroller around it (lane SCROLLB's
    /// review).
    func pageOverscrollAllowances(
        _ environment: EnvironmentValues, overflowing: Bool
    ) -> (top: ScrollOverscroll, bottom: ScrollOverscroll, springs: Bool) {
        isChrome ? (.none, .none, false) : environment.overscrollAllowances(overflowing: overflowing)
    }
}

extension _ScrollViewCore {

    /// Bottom edge affinity (defaultScrollAnchor(.bottom), §5c/§6c): being
    /// AT the bottom is the engagement — no stored flag. If last frame's
    /// numbers say the offset sits at (or past) the tail — BOTH of them,
    /// content and viewport, which is what `tailAsLastDrawn` records — the
    /// view is glued: the frame renders at the previous tail, the post-render
    /// re-glue lands on the real new maximum, and `coverSnappedViewport`
    /// re-renders — O(window) — when the band's margin doesn't already
    /// cover the difference (it does for the common one-row append).
    /// Scrolling up breaks the condition (offset < max) and appends stop
    /// moving the view; any scroll that lands back at the bottom
    /// re-engages. Vertical only.
    ///
    /// The OPENING frame is glued by definition, not by those numbers: that is
    /// the initial at-the-tail placement. It used to follow from them — a view
    /// that has never been drawn has a content height of 0, so an offset of 0
    /// is its maximum — until every app's first frame began to run a measuring
    /// walk first (to size the app header), which records the real height. The
    /// render after it then saw an offset of 0 far short of the maximum, and a
    /// bottom-anchored view opened at its TOP in every app. Tests rendering the
    /// view directly never ran that walk; `HeadlessApp` does.
    ///
    /// Deliberately NO pre-render tail estimate: this used to measure the
    /// whole content tree every glued frame to pre-position the offset, and
    /// that estimate systematically disagreed with the post-render reply
    /// total (they come from different estimators), so the coverage
    /// re-render fired EVERY frame — a full measure plus two band renders
    /// per frame, 23% of the scrollfollow profile in the second render
    /// alone.
    func isGluedToBottom(handler: ScrollViewHandler, context: RenderContext) -> Bool {
        // The EFFECTIVE anchor, not just the declaration: a bound
        // `.anchorPosition` of `.bottom` must follow the tail even with no
        // `defaultScrollAnchor` (that is §3.2's `anchor(to:)`), and a bound
        // `.window` / `.top` / `.row` must override a declared `.bottom` — a
        // release the user made by scrolling away has to actually stop the
        // follow, or `.window` would be a read-out with no behaviour behind it.
        // The OPENING frame consults the `.initialOffset` anchor and every
        // frame after it the `.sizeChanges` one — the same value for any view
        // that used the unlabelled modifier. See `ScrollAnchorMode.governing`.
        let modes = pageDeclaredAnchorModes(context.environment)
        let declared = ScrollAnchorMode.governing(
            opening: modes.opening, standing: modes.standing, hasOpened: handler.hasOpened)
        let followsBottom = !context.isMeasuring
            && ScrollAnchorMode.effective(
                boundAnchor: pageAnchorPosition(context.environment)?.wrappedValue,
                declared: declared) == .bottom
        // A pending scrollTo supersedes the glue this frame: the explicit
        // programmatic scroll is exactly the "scrolling away releases the
        // follow" interaction, expressed in code.
        // A change made under `.scrollContentOffsetAdjustmentBehavior =
        // .disabled` is not followed; the view then sits short of the new tail,
        // which is the follow released, as a user scroll releases it. The
        // opening placement is not an adjustment and is kept.
        let suspended =
            handler.hasOpened && context.environment.transaction.disablesScrollContentOffsetAdjustment
        return followsBottom && handler.pendingScrollTo == nil && !suspended
            && (!handler.hasOpened || handler.scrollOffset >= handler.tailAsLastDrawn)
    }

    /// Adopts a bound anchor the app just *wrote*: `.top` jumps to the top,
    /// `.bottom` to the tail. §3.2 promises that writing an edge into the
    /// binding is `anchor(to:)`, and only the CHANGE can mean that — holding
    /// the edge unconditionally every frame would nail an unbound
    /// `.defaultScrollAnchor(.top)` view to the top and make it unscrollable.
    /// After the jump the edge is held positionally, exactly as a declared one
    /// is (bottom re-glues while the offset sits at `maxOffset`; top needs
    /// nothing, since no data change moves an offset of 0).
    ///
    /// Render passes only, and before the glue is evaluated: `.bottom` sets
    /// `seekingTail` rather than an offset, so the post-render re-glue lands on
    /// the real tail instead of a pre-render estimate of it.
    func adoptWrittenAnchor(handler: ScrollViewHandler, context: RenderContext) {
        guard !context.isMeasuring else { return }
        let bound = pageAnchorPosition(context.environment)?.wrappedValue
        guard handler.lastBoundAnchor != .some(bound) else { return }
        let isFirstSighting = handler.lastBoundAnchor == nil
        handler.lastBoundAnchor = .some(bound)
        // A first sighting is the view appearing, not the app writing: leave the
        // initial placement to the declared anchor's own machinery.
        guard !isFirstSighting else { return }
        switch bound {
        case .top: handler.scrollOffset = 0
        case .bottom: handler.seekingTail = true
        default: break
        }
    }

    /// What this frame's first drawing of the content does about the row at
    /// the top of the viewport (``ScrollContentWindow/topRowHold``), under
    /// ``ScrollWindowHold/topRow``: holds it in place — moving the offset by
    /// however far the content above it moved it — unless something else
    /// places the frame, and keeps track of it either way.
    ///
    /// Something else places it at the top (an offset of 0 shows the rows
    /// inserted above, as SwiftUI's does, measured: that is positional
    /// engagement with the top edge, as following the tail is with the
    /// bottom), while following the tail (the follow places it), for a seek
    /// or a `.scrollPosition` request this frame (they aim at a line of the
    /// content as it now is), and for a change made under
    /// `Transaction.scrollContentOffsetAdjustmentBehavior = .disabled`. A
    /// designated row is the stack's own to hold, and wins over this.
    ///
    /// - Parameters:
    ///   - glued: Whether the frame follows the tail.
    ///   - placed: Whether a seek or a position request placed the frame.
    func topRowHold(
        handler: ScrollViewHandler, glued: Bool, placed: Bool, context: RenderContext
    ) -> TopRowHold {
        guard !context.isMeasuring else { return .off }
        let hold = pageWindowHold(context.environment)
        defer { handler.lastWindowHold = hold }
        guard hold == .topRow, axes.contains(.vertical) else { return .off }
        let holds =
            handler.lastWindowHold == .topRow && !glued && !placed && handler.scrollOffset > 0
            && !context.environment.transaction.disablesScrollContentOffsetAdjustment
        return holds ? .holding : .tracking
    }

    /// Keeps an eagerly drawn page roughly where it was when a change of the
    /// viewport's width reflows it.
    ///
    /// A windowed stack holds the row at the top across any change above it
    /// (``topRowHold(handler:glued:placed:context:)``). Content drawn whole — a
    /// `VStack` of sections, as most pages are — has no rows to hold: its
    /// offset stays where it was in lines, as SwiftUI's does, so a window made
    /// narrower wrapped the text above the view onto more lines and slid what
    /// was being read off the bottom, and one made wider slid it off the top.
    /// Here the offset scales with the content's height across the reflow, so
    /// the same part of the page stays in view, near enough: text above it that
    /// rewraps keeps its share of the height.
    ///
    /// Only for a reflow — the width changed since the last frame drawn — and
    /// only where the default hold applies: at the top a view stays at the top,
    /// a view following its tail follows it, a seek or a position request
    /// placed the frame itself, and ``ScrollWindowHold/offset`` or a change
    /// made under `Transaction.scrollContentOffsetAdjustmentBehavior =
    /// .disabled` keeps the offset as it is.
    ///
    /// Records the height `drawing` gives the content as it goes, as every
    /// render does: a sliced reply's from its metadata, estimate and all.
    func recordContentHeight(
        of drawing: ScrollContentDrawing, handler: ScrollViewHandler, contentWidth: Int, placed: Bool,
        context: RenderContext
    ) {
        let heightBefore = handler.contentHeight
        handler.contentHeight = drawing.slice?.totalHeight ?? drawing.buffer.height
        handler.contentHeightIsEstimate = drawing.slice?.totalIsEstimate ?? false
        guard !context.isMeasuring else { return }
        defer { handler.lastContentWidth = contentWidth }
        guard drawing.slice == nil, !placed, axes.contains(.vertical), let lastWidth = handler.lastContentWidth,
            lastWidth != contentWidth, heightBefore > 0, handler.contentHeight != heightBefore,
            handler.scrollOffset > 0, pageWindowHold(context.environment) == .topRow,
            !context.environment.transaction.disablesScrollContentOffsetAdjustment
        else { return }
        let scaled = Double(handler.scrollOffset) * Double(handler.contentHeight) / Double(heightBefore)
        handler.scrollOffset = Int(scaled.rounded())
    }

    /// What a later drawing of the content in the same frame — drawn again
    /// where a focus snap, a re-glue or a reader of this view's space moved
    /// the offset — does about the row at the top: keeps track of it whenever
    /// the frame's first drawing did anything about it, so that the next
    /// frame holds the row this one ends up showing. That is what the anchored
    /// walk takes its anchor from (`rebindingAnchor`): remembered at the first
    /// drawing, a snap several screens long was walked again from there on the
    /// next frame, by estimate.
    func redrawnTopRowHold(handler: ScrollViewHandler, context: RenderContext) -> TopRowHold {
        !context.isMeasuring && axes.contains(.vertical) && handler.lastWindowHold == .topRow ? .tracking : .off
    }

    /// How many lines down the viewport this frame draws content SHORTER than
    /// it: the ``ScrollAnchorRole/alignment`` anchor's `y` of the room left
    /// over, rounded down to a line — `0` for content that fills the viewport,
    /// for a view with no alignment anchor, and for one that does not scroll
    /// vertically.
    ///
    /// SwiftUI places short content this way, and its unlabelled
    /// `.defaultScrollAnchor(.bottom)` states this role too (measured): three
    /// rows of a chat sit at the bottom of its view. Not quantised to the edges
    /// as the other two roles are — those choose a policy, and this a place.
    ///
    /// The shift is a slide of the drawn viewport (`applyOverscroll`), not an
    /// offset: content that fits has a scroll offset of 0 and a maximum of 0,
    /// and both stay so. That keeps every piece of arithmetic that maps the
    /// offset to a row — a seek, the reveal, the follow, the reported position
    /// — exactly as it is, and the slide carries the hit regions, the layers
    /// and the animated runs down with the lines, so what is clicked is what
    /// is drawn there. The geometry reports it as SwiftUI does, as a top inset
    /// with the offset above it (`scrollGeometry`).
    func alignmentShift(
        handler: ScrollViewHandler, viewportHeight: Int, context: RenderContext
    ) -> Int {
        // The room first: content that overflows — most of what a scroll view
        // holds — pays no environment read.
        let room = viewportHeight - handler.contentHeight
        guard room > 0, axes.contains(.vertical), !isChrome,
            let anchor = context.environment.scrollAnchor(for: .alignment), anchor.y > 0
        else { return 0 }
        return min(room, Int((anchor.y * Double(room)).rounded(.down)))
    }
}
