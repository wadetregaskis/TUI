//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollOverscroll.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Allowance

/// How far past an edge a scrollable may be pushed — §1.5 of
/// `Documentation/Layout and scrolling/Scroll anchoring.md`.
///
/// Overscroll is the empty space a deliberate push reveals beyond the content:
/// scroll up at the top and the content slides down, leaving blank rows above
/// it. It exists for two reasons. It gives the last row breathing space instead
/// of pinning it hard against the frame, and — because pushing *into* it is
/// unambiguous, while merely landing on the edge is not — it is the signal that
/// separates a deliberate push from a graze (§1.3's sticky edges).
public enum ScrollOverscroll: Sendable, Hashable {
    /// No overscroll: the content stops exactly at the edge. The default.
    case none

    /// A fixed number of rows (a `List`/`Table`) or lines (a `ScrollView`).
    case rows(Int)

    /// The viewport's own height, less `minus` rows/lines — the idiom for "you
    /// may scroll until only a couple of rows are left on screen".
    /// `.viewport(minus: 0)` allows a full viewport, so the content can be
    /// pushed entirely out of sight.
    case viewport(minus: Int)

    /// The allowance in rows/lines for a viewport of `viewportHeight`.
    func resolved(viewportHeight: Int) -> Int {
        switch self {
        case .none: return 0
        case .rows(let count): return max(0, count)
        case .viewport(let minus): return max(0, viewportHeight - max(0, minus))
        }
    }
}

// MARK: - Live state

/// A scrollable's live overscroll: how far it is currently pushed past an edge,
/// and the allowance bounding that.
///
/// The excursion is kept **separate from `scrollOffset`** rather than widening
/// the offset's range, which was measured to trap rather than merely misdraw:
/// `_ListCore`'s `(0..<scrollOffset)` is a fatal range when negative and
/// indexes past the data when over-max, and `ScrollView`'s
/// `lines.dropFirst(scrollOffset)` traps on a negative count. Keeping the offset
/// in `[0, maxOffset]` means no data-indexing consumer needs auditing at all,
/// the "N more" indicators ignore the excursion for free (they read the offset),
/// and the sticky-edge detector reads the excursion directly instead of
/// inferring a push from a clamped offset.
public struct ScrollOverscrollState: Sendable, Equatable {
    /// Rows/lines past an edge: **negative** past the top (blank space above the
    /// content), **positive** past the bottom. Zero whenever the content sits
    /// against its edges, which is always unless an allowance is configured or
    /// `.scrollBounceBehavior(.always)` gives one.
    public internal(set) var excursion: Int = 0

    /// The resolved allowance above the content, in rows/lines.
    var top: Int = 0

    /// The resolved allowance below the content, in rows/lines.
    var bottom: Int = 0

    /// Whether any overscroll is permitted at all — the fast "this feature is
    /// off" test every hot path takes first.
    var isAllowed: Bool { top > 0 || bottom > 0 }

    /// Whether a push past the top, or past the bottom, springs back: the
    /// bounce `ScrollBounceBehavior.always` gives an end the app gave no
    /// allowance of its own (decisions B31). An allowance the app asked for
    /// stays where it was pushed, as ever.
    var springsTop = false
    var springsBottom = false

    /// Whether a user step pushed the excursion, or held it against its
    /// limit, since a render pass last settled it — what keeps a sprung one
    /// out while the steps keep coming. Set at event time, where there is no
    /// clock; the render that settles it stamps its own frame's.
    var pushedSinceSettle = false

    /// When a sprung excursion takes its next step back, on the frame clock;
    /// `nil` while none is pushed.
    var springStepAtNanos: Int64?

    public init() {}

    /// Re-resolves the allowance for the current viewport, and pulls an existing
    /// excursion back inside it (the terminal may have shrunk under a
    /// `.viewport`-relative allowance).
    ///
    /// `springs`: whether an end with no allowance of its own gets the sprung
    /// one (``sprungAllowance(viewportHeight:)``) — `ScrollBounceBehavior.always`.
    package mutating func resolve(
        top: ScrollOverscroll, bottom: ScrollOverscroll, viewportHeight: Int, springs: Bool = false
    ) {
        springsTop = springs && top == .none
        springsBottom = springs && bottom == .none
        let sprung = springs ? Self.sprungAllowance(viewportHeight: viewportHeight) : 0
        self.top = springsTop ? sprung : top.resolved(viewportHeight: viewportHeight)
        self.bottom = springsBottom ? sprung : bottom.resolved(viewportHeight: viewportHeight)
        excursion = max(-self.top, min(self.bottom, excursion))
    }

    /// How far a `.always` bounce may push: two lines, or one where the
    /// content area is under eight, so a push never hides more than a quarter
    /// of a small view (decisions B-SCROLLB-2).
    static func sprungAllowance(viewportHeight: Int) -> Int {
        viewportHeight >= 8 ? 2 : 1
    }

    /// Records a user step that pushed into the excursion, or against its
    /// limit: a sprung one waits until the steps stop.
    mutating func notePush() {
        pushedSinceSettle = true
    }

    /// Springs a sprung excursion back toward the content: held while the
    /// user's steps keep coming, then a line a frame once they have been quiet
    /// for ``ScrollPhase/quietNanos`` (B27's quiet). Timed from the render
    /// that saw the last step, as a step has no clock, so it can trail an
    /// observed phase's return to idle, timed from the step's event, by up to
    /// a frame. Returns when the next frame is owed, on the frame clock, or `nil` when
    /// none is: no excursion, or one the app's own allowance holds.
    ///
    /// Asked on render passes with an excursion only, so a scrollable at its
    /// edges, or pushed into an allowance the app asked for, pays a test.
    package mutating func settleSpring(nowNanos now: Int64) -> Int64? {
        guard excursion < 0 ? springsTop : excursion > 0 && springsBottom else {
            springStepAtNanos = nil
            return nil
        }
        if pushedSinceSettle || springStepAtNanos == nil {
            pushedSinceSettle = false
            springStepAtNanos = now &+ Int64(ScrollPhase.quietNanos)
        }
        guard let due = springStepAtNanos, now >= due else { return springStepAtNanos }
        excursion += excursion < 0 ? 1 : -1
        guard excursion != 0 else {
            springStepAtNanos = nil
            return nil
        }
        let next = now &+ AnimationClock.nanoseconds(atTick: Int64(AnimationClock.standardFrameTicks))
        springStepAtNanos = next
        return next
    }
}

extension ScrollableOffsetState {
    /// Re-resolves this frame's overscroll allowance (§1.5) after the vertical
    /// bounce behaviour, and on a render pass springs a `.always` bounce back
    /// once the user's steps have stopped (decisions B31), asking for the
    /// frames that takes. Every scrollable's one call, so the rule cannot
    /// drift between them.
    ///
    /// - Parameters:
    ///   - viewportHeight: The content area the allowance is resolved in, in
    ///     the lines the excursion is drawn in.
    ///   - allowances: The allowances this scrollable takes, and whether an
    ///     end given none springs: `EnvironmentValues.overscrollAllowances(overflowing:)`,
    ///     or none at all for a framework scroller (`_ScrollViewCore.pageOverscrollAllowances`).
    @MainActor
    package func settleOverscroll(
        viewportHeight: Int, allowances: (top: ScrollOverscroll, bottom: ScrollOverscroll, springs: Bool),
        context: RenderContext
    ) {
        overscrollState.resolve(
            top: allowances.top, bottom: allowances.bottom, viewportHeight: viewportHeight,
            springs: allowances.springs)
        guard overscrollState.excursion != 0, !context.isMeasuring,
            let due = overscrollState.settleSpring(nowNanos: context.environment.frameNowNanos)
        else { return }
        context.requestWake(token: "overscroll-spring-\(context.identity.path)", atNanos: due)
    }
}

// MARK: - Rendering the excursion

extension ScrollOverscrollState {
    /// Slides `lines` by the excursion, blank-filling the gap it opens and
    /// clipping the far side, so the count is unchanged.
    ///
    /// Callers pass the **content** lines only. `ScrollView` gets this effect
    /// from `replacingLines` on its finished viewport buffer because it appends
    /// its scrollbar as a whole column afterwards; the row-based views cannot,
    /// because they merge a bar cell into each line as they build it and stitch
    /// the "N more" indicators in at top and bottom. Both are chrome — they
    /// describe where the content sits — so they must not travel with it, which
    /// is why `List` and `Table` collect their row lines separately, slide them
    /// here, and only then assemble.
    package func slid(_ lines: [String], blank: String) -> [String] {
        guard excursion != 0, !lines.isEmpty else { return lines }
        let gap = min(abs(excursion), lines.count)
        return excursion < 0
            ? Array(repeating: blank, count: gap) + lines.dropLast(gap)
            : Array(lines.dropFirst(gap)) + Array(repeating: blank, count: gap)
    }

    /// Where a row that occupied `yStart..<yStart + height` in the unslid
    /// content lands afterwards, clipped to `0..<lineCount` — or `nil` when the
    /// slide pushed it off entirely — and how many of the row's own lines that
    /// clip took off its TOP.
    ///
    /// Row hit-testing indexes the *drawn* lines, so a range that does not move
    /// with its row sends clicks to the wrong one. Clipping rather than
    /// translating keeps a partially-visible row clickable over the part of it
    /// that is actually on screen.
    ///
    /// `cutAbove` is that clip's own size, reported rather than left to be
    /// re-derived: anything positioned in the row's coordinates — its hit
    /// regions, its overlays, its claims — starts at the row's first DRAWN line,
    /// and a consumer measuring from the row's top instead lands it that many
    /// lines low (§67).
    package func slidRange(
        yStart: Int, height: Int, lineCount: Int
    ) -> (yStart: Int, height: Int, cutAbove: Int)? {
        guard excursion != 0 else { return (yStart, height, 0) }
        let moved = yStart - excursion
        let clippedStart = max(0, moved)
        let clippedEnd = min(lineCount, moved + height)
        guard clippedEnd > clippedStart else { return nil }
        return (clippedStart, clippedEnd - clippedStart, clippedStart - moved)
    }

    /// Whether this slide pushes any of the content rows `top..<bottom` off a
    /// viewport whose content shows on rows `shownTop..<shownBottom`, all in the
    /// same content coordinates.
    ///
    /// The slide opens its blank rows at one edge and pushes as many rows out at
    /// the other: a push past the top (a negative excursion) loses the LAST
    /// `-excursion` shown rows, a push past the bottom the FIRST `excursion`. The
    /// shown band stops short of any "N more" line, which is chrome drawn over
    /// the slid content rather than content that slides.
    ///
    /// Asked by a reveal that has just placed a control: an excursion that hides
    /// it has to go, and one that does not may stay.
    func pushesOff(top: Int, bottom: Int, shownTop: Int, shownBottom: Int) -> Bool {
        guard excursion != 0 else { return false }
        let lostTop = excursion < 0 ? shownBottom + excursion : shownTop
        let lostBottom = excursion < 0 ? shownBottom : shownTop + excursion
        return top < lostBottom && bottom > lostTop
    }
}

// MARK: - Environment

private struct ScrollOverscrollTopKey: EnvironmentKey {
    static let defaultValue: ScrollOverscroll = .none
}

private struct ScrollOverscrollBottomKey: EnvironmentKey {
    static let defaultValue: ScrollOverscroll = .none
}

extension EnvironmentValues {
    /// How far past its top a scrollable may be pushed. See
    /// ``TUIkit/View/scrollOverscroll(top:bottom:)``.
    public var scrollOverscrollTop: ScrollOverscroll {
        get { self[ScrollOverscrollTopKey.self] }
        set { self[ScrollOverscrollTopKey.self] = newValue }
    }

    /// How far past its bottom a scrollable may be pushed. See
    /// ``TUIkit/View/scrollOverscroll(top:bottom:)``.
    public var scrollOverscrollBottom: ScrollOverscroll {
        get { self[ScrollOverscrollBottomKey.self] }
        set { self[ScrollOverscrollBottomKey.self] = newValue }
    }
}

extension View {
    /// Lets the scrollables in this subtree be pushed past their edges, revealing
    /// blank space beyond the content.
    ///
    /// Each end is specified independently, because they are usually wanted for
    /// different reasons — a log view might allow a generous bottom overscroll so
    /// the newest line isn't jammed against the frame, and none at the top.
    ///
    /// ```swift
    /// ScrollView { LogLines(entries) }
    ///     .scrollOverscroll(top: .none, bottom: .viewport(minus: 1))
    /// ```
    ///
    /// Only a **user** gesture pushes into the allowance, and only once the
    /// content has actually reached the edge: a wheel tick that merely lands on
    /// the edge is spent getting there, and the next one pushes past. That is
    /// what makes a deliberate push distinguishable from a graze. Programmatic
    /// movement (`scrollTo`, a bound `ScrollPosition`, a reveal) never
    /// overscrolls, and never leaves an excursion behind. A reveal with nothing to
    /// move keeps the push, unless the push is what hides the control being
    /// revealed; a written `anchorPosition` edge keeps it too, because a push
    /// past an edge writes that binding itself.
    ///
    /// A view whose content already fits its viewport can still be pushed — the
    /// allowance is not conditional on there being anything to scroll — unless
    /// ``View/scrollBounceBehavior(_:axes:)`` says `.basedOnSize`. A push stays
    /// where it was put; only an end given no allowance under `.always` bounces
    /// back (see ``ScrollBounceBehavior``).
    ///
    /// The "N more above/below" indicators count content, so they ignore the
    /// excursion entirely: pushing past the bottom does not invent rows below.
    ///
    /// - Parameters:
    ///   - top: The allowance above the content. Defaults to ``ScrollOverscroll/none``.
    ///   - bottom: The allowance below it. Defaults to ``ScrollOverscroll/none``.
    /// - Returns: A view whose scrollables permit that overscroll.
    public func scrollOverscroll(
        top: ScrollOverscroll = .none, bottom: ScrollOverscroll = .none
    ) -> some View {
        environment(\.scrollOverscrollTop, top)
            .environment(\.scrollOverscrollBottom, bottom)
    }
}
