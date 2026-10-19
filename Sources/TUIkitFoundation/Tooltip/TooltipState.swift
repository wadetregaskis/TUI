//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TooltipState.swift
//
//  The one tooltip a frame may show, and how it became the candidate.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - TooltipState

/// The help text a frame may show, and where it came from.
///
/// One per `TUIContext`, published to the environment each frame — the same
/// shape as `StatusBarState`, and a service rather than a singleton for the
/// same reason: two renders sharing one would read each other's tooltips.
///
/// ## Two slots, with different lifetimes
///
/// A hover candidate is set by an `.entered` mouse event and survives until
/// `.exited`, because the pointer stays where it is between frames — or, when
/// the page moved under the pointer because the status bar took a tooltip's
/// rows, until the pointer itself moves (`held`). A focus
/// candidate is republished by whichever view holds the focus on every walk of
/// the scene, and is **dropped at the end of a frame whose last walk did not
/// publish it again**, or as soon as the focus moves off the view that
/// published it: its absence has to be the default, or a view that lost the
/// focus would leave its help text behind.
///
/// Dropped at the END of the frame, not cleared at the top of each walk as it
/// was until 2026-10-12, because two readers come before the focused control
/// publishes again. The status bar's rows are sized before the walk
/// (`RenderLoop.resolveStatusBarTooltip`), so a slot cleared at the top of the
/// walk never reached the bar: `?` showed nothing in the default presentation.
/// And a frame runs the per-walk reset twice (the frame opens with one, and the
/// walk itself with another: `RenderLoop.beginSceneRender`), so a deadline
/// saved from the slot as it was cleared was saved from an empty slot by the
/// second, and ``TooltipTrigger/onFocus`` restarted its delay every frame and
/// never showed.
///
/// Keeping them apart is what makes "hover wins over focus" a one-line rule
/// rather than a race between two publishers. The pointer is a deliberate act
/// aimed at one thing; focus is where the keyboard happens to be.
public final class TooltipState: @unchecked Sendable {

    /// What made a tooltip a candidate.
    public enum Source: Sendable, Equatable {
        /// The pointer is over the view's hit region.
        case hover
        /// The view holds the keyboard focus.
        case focus
    }

    /// A tooltip that could be shown.
    struct Candidate {
        /// The help text, already localized.
        var text: String
        /// The view's hit region this frame, for a popover to anchor to. The
        /// RECT is not stored: only the dispatcher knows where the compositor
        /// finally put the region, and it knows it after this is published.
        var handlerID: HitTestRegion.HandlerID?
        /// The focus identity of the control that published a focus candidate;
        /// `nil` for a hover candidate. What lets the run loop drop the
        /// candidate the moment the focus moves (``syncFocus(focusID:)``),
        /// rather than at the end of the walk that proves it gone.
        var focusID: String?
        /// The identity of the view that published a hover candidate, which
        /// outlives its per-frame handler id and its text: a toggle's help
        /// that changes as it is clicked (Hide Sidebar, then Show Sidebar) is
        /// still the candidate of the view under the pointer
        /// (``hoveredViewDrew(owner:text:)``). `nil` where the publisher
        /// named none.
        var owner: String?
        /// The frame clock when this became the candidate — the re-entry test,
        /// not the deadline.
        var sinceNanos: Int64
        /// The earliest moment it may be drawn: entry plus the hover delay, or
        /// `sinceNanos` for a focus candidate, which waits on the key instead.
        ///
        /// The DEADLINE rather than the delay, because the delay is a subtree
        /// setting (``EnvironmentValues/tooltipDelay``) and only the view that
        /// carries the help can read it. Resolving against a delay fetched
        /// somewhere else is how the two halves of one number drift apart.
        var showAtNanos: Int64
        /// Whether this candidate shows on its own, without the help key.
        ///
        /// Set from ``TooltipTrigger/revealsOnFocus`` — a subtree setting, so it
        /// rides on the candidate for the same reason ``style`` does. A hover
        /// candidate always shows on its own and leaves this `false`; only the
        /// focus slot consults it.
        var revealsItself = false
        /// How to present it — read from the environment of the view that
        /// carries the help, not from the root's. `tooltipStyle` is a subtree
        /// setting, so a panel asking for a popover inside an app that uses the
        /// bar is answered by the panel; the run loop has only the root
        /// environment and could not tell.
        var style: TooltipStyle
    }

    /// The pointer's candidates: every view with help whose hover observer
    /// heard the pointer enter and not yet leave, outermost first. Nested
    /// views with help each hear it (`MouseEventDispatcher.resolveHover`),
    /// and the dispatcher keeps this in its order
    /// (``observersHovered(_:)``).
    private var hoveredViews: [Candidate] = []

    /// The pointer's candidate: of the views with help it is over, the
    /// innermost — the most specific, as AppKit shows the tooltip of the
    /// deepest view under the pointer. Until the hover observers nested
    /// (2026-10-18) only the outermost one heard the pointer at all.
    var hovered: Candidate? { hoveredViews.last }

    /// A hover candidate kept through the status bar's own reflow, and shown
    /// in preference to ``hovered``: the pointer has not moved, but the page
    /// has, under it, because the bar took or gave back a tooltip's rows.
    ///
    /// The bar grows upwards for a status-bar tooltip, so a page laid out in
    /// the middle of the window (as a `WindowGroup` lays out one that does
    /// not fill it) moves with it, and the view under a resting pointer
    /// slides out from under it. Taken as the pointer leaving, that took the
    /// tooltip away, gave the row back, slid the view under the pointer again
    /// and restarted its delay: help on screen for one frame in every delay,
    /// or, once a walk's change to the bar asked for its frame, for one frame
    /// and not again (decisions-HELP A-HELP-1). So the hover transitions such
    /// a reshape makes (``beginReshape(movedByTooltip:presentations:)``) are not hover
    /// changes to the tooltip: the candidate the exit would have dropped is
    /// held here until the pointer moves and does not land on its view again
    /// (``notePointerMoved()``), or until no pointer could rest on its view
    /// any more (``endReshape(pointerOnTooltipRows:reaching:)``). ``hovered``
    /// goes on recording what the pointer is over, and is the candidate again
    /// once this goes.
    ///
    /// On a page that fills the window the bar's new rows do not move the
    /// page: they cover its last visible rows, and the view under the pointer
    /// with them. A pointer resting on the rows the bar took for its tooltip
    /// still rests on the tooltip's own view, so the candidate is held there
    /// too, though no pointer could reach the view: let go, it gave the rows
    /// back, the view came back under the pointer, and its delay began again.
    /// Held there while what is presented over the page is what was when the
    /// hold began (``heldPresentations``): a sheet, an alert, a popover or a
    /// menu that comes up over the page takes the hover from every view on
    /// it, the covered one too, and a sheet docked under the page takes the
    /// rows the bar covers.
    private var held: Candidate?

    /// Whether the reshape under way is the status bar's own reflow; see
    /// ``held``.
    private var reshapeIsTooltipReflow = false

    /// How many surfaces are presented over the page for the reshape under
    /// way; see ``beginReshape(movedByTooltip:presentations:)``.
    private var reshapePresentations = 0

    /// How many surfaces were presented over the page when ``held`` began, as
    /// ``reshapePresentations`` said it: while the pointer rests on the rows
    /// the bar covers, the held view counts as reachable only while as many
    /// are. A covered row has no region to probe, so the probe that lets a
    /// held view go when a sheet's backdrop comes over it
    /// (``endReshape(pointerOnTooltipRows:reaching:)``) cannot see it; found
    /// by the BUGS13 lane's review, which left a covered row's help in the bar
    /// over a sheet a key presented.
    ///
    /// A count of the surfaces, not the focus section in front, which the
    /// first fix compared: a sheet docked live beside the page is never a
    /// modal section, so the help stayed in the bar over it (the lane's second
    /// review), and a pane inside a modal taking the focus let a help held in
    /// that modal go though nothing new was presented.
    private var heldPresentations = 0

    /// The pointer's candidate as a frame shows it: the one ``held`` through
    /// the bar's reflow, or else the one the pointer is over.
    private var pointerCandidate: Candidate? { pointerSilenced ? nil : held ?? hovered }

    /// Whether a key has sent the pointer's tooltip away until the pointer
    /// moves (``noteKeyPress()``).
    private var pointerSilenced = false

    /// The focused view's candidate: the one the focused control last
    /// published. Kept across walks; see the type's discussion.
    private(set) var focused: Candidate?

    /// Whether the walk under way has published ``focused`` again: what
    /// ``endFrame()`` asks of the frame's last walk.
    private var focusRepublished = false

    /// Whether the keyboard has asked for the focused view's tooltip.
    ///
    /// A focus candidate does **not** show on its own — it is revealed by the
    /// help key (`?` by default). That is the whole reason this framework needs
    /// no `focus(id:reason:)`: the design this implements had focus auto-show
    /// the tooltip, which meant it had to know whether the focus arrived from a
    /// click, because popping a tooltip up under every click is intolerable. A
    /// key press is unambiguously the keyboard asking, so the question does not
    /// arise and a shared API did not have to change.
    ///
    /// Cleared when the focused view changes, so the reveal does not follow the
    /// cursor around the page.
    private(set) var keyboardRevealed = false

    /// The focus identity `keyboardRevealed` was granted for.
    private var revealedFocusID: String?

    /// The key that reveals the focused view's tooltip. `?` by default, `nil` to
    /// claim no key at all.
    ///
    /// Settable for the same reason `StatusBarState.quitShortcut` is: the
    /// framework claiming a bare letter has to be something an app can take
    /// back. An app can also simply bind the key itself — a status-bar item, an
    /// `.onKeyEvent`, or a `.keyboardShortcut` all run before this does.
    ///
    /// ## Known caveat: a focused text control swallows `?`
    ///
    /// `?` is punctuation, and `InputHandler`'s layer 0 gives a focused
    /// `TextField`, `SecureField`, `TextEditor` or `DatePicker` first refusal on
    /// every printable key — so inside one, `?` is typed and this is never
    /// reached. That is the correct precedence (a help key must not stop the
    /// reader typing a question mark) and it is a real hole: the controls whose
    /// help most needs explaining are exactly the ones the key cannot reach.
    /// Their tooltips are still available by hovering, and an app that wants a
    /// keyboard route inside a text field should set this to a key text input
    /// does not consume.
    ///
    /// The alternative was an F-key, declined by the project owner because F-keys
    /// are frequently claimed system-wide and would fail differently and less
    /// visibly.
    public var helpKey: Key? = .character("?")

    public init() {}

    // MARK: - Publishing

    /// Records that the pointer has entered a view carrying help text.
    ///
    /// - Parameters:
    ///   - text: The localized help text.
    ///   - owner: The view's identity, across frames (``Candidate/owner``).
    ///   - handlerID: The view's hit region, for a popover to anchor to.
    ///   - nowNanos: The frame's monotonic clock, which the hover delay is
    ///     measured from.
    package func hovering(
        _ text: String, owner: String? = nil, handlerID: HitTestRegion.HandlerID?, nowNanos: Int64,
        style: TooltipStyle = .statusBar, delaySeconds: Double = 0
    ) {
        // Re-entering the SAME region must not restart the delay: the
        // dispatcher synthesises `.entered` whenever the cursor crosses a
        // boundary, and a region that was re-registered at a different id this
        // frame is still the same view under the pointer. Compared on the text
        // rather than the id for exactly that reason — ids are per-frame.
        // The view held through the bar's reflow, under the pointer again, is
        // the same candidate too, its delay already served (``held``).
        // So is the view it was published for, with help that has changed
        // since.
        func isSame(_ candidate: Candidate) -> Bool {
            candidate.text == text || (owner != nil && candidate.owner == owner)
        }
        if var held, isSame(held) {
            held.text = text
            hoveredViews.removeAll(where: isSame)
            hoveredViews.append(held)
            self.held = nil
            return
        }
        if let index = hoveredViews.firstIndex(where: isSame) {
            hoveredViews[index].text = text
            return
        }
        hoveredViews.append(
            Candidate(
                text: text, handlerID: handlerID, owner: owner, sinceNanos: nowNanos,
                showAtNanos: nowNanos &+ Int64(max(0, delaySeconds) * 1_000_000_000),
                style: style))
    }

    /// Keeps the pointer's candidates in step with the hover observers the
    /// pointer is over, `handlerIDs`, outermost first: one whose observer it
    /// is not over goes, and the rest take that order, so the innermost is
    /// ``hovered``. Called by the dispatcher whenever it resolves the hover.
    ///
    /// The order is the dispatcher's, not the order the views were entered
    /// in: a reshape can exit and enter a container again (its rectangle
    /// changed) while the pointer stays in a view inside it, which would put
    /// the container last. A candidate an exit never reached — its view gone
    /// while the pointer was not reported — goes too, where it used to stay
    /// until another view replaced it. One published with no handler id is
    /// kept, ahead of the rest.
    ///
    /// - Parameters:
    ///   - handlerIDs: The observers the pointer is over, outermost first.
    ///   - renamed: The observers a reshape carried on under another id —
    ///     a view's region is filed under the id its registration got that
    ///     frame, which can change while the view stays under the pointer
    ///     (the dispatcher tells them apart by their rectangles): each
    ///     candidate's id is followed first.
    package func observersHovered(
        _ handlerIDs: [HitTestRegion.HandlerID],
        renamed: [HitTestRegion.HandlerID: HitTestRegion.HandlerID] = [:]
    ) {
        guard !hoveredViews.isEmpty else { return }
        if !renamed.isEmpty {
            for index in hoveredViews.indices {
                if let id = hoveredViews[index].handlerID, let now = renamed[id] { hoveredViews[index].handlerID = now }
            }
        }
        let rank = Dictionary(handlerIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = hoveredViews.filter { $0.handlerID.map { rank[$0] != nil } ?? true }
        hoveredViews = kept.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.handlerID.flatMap { rank[$0] } ?? -1
                let right = rhs.element.handlerID.flatMap { rank[$0] } ?? -1
                return (left, lhs.offset) < (right, rhs.offset)
            }
            .map(\.element)
    }

    /// Records that the pointer has left the view it was over.
    ///
    /// Takes that view's candidate out of the pointer's candidates: with
    /// nested help (a container and a child), leaving the child fires
    /// `.exited` for it while the pointer is still inside the container, whose
    /// candidate is then ``hovered`` again, its delay served. An exit for a
    /// view that is not a candidate does nothing.
    ///
    /// Moved out from under the pointer by the status bar's own rows, the
    /// candidate is held rather than dropped (``held``).
    ///
    /// - Parameters:
    ///   - text: The help text the view had when the pointer entered it.
    ///   - owner: The view's identity, which finds its candidate however its
    ///     text has changed since.
    package func leaving(_ text: String, owner: String? = nil) {
        guard
            let index = hoveredViews.lastIndex(where: {
                $0.text == text || (owner != nil && $0.owner == owner)
            })
        else { return }
        if reshapeIsTooltipReflow, held == nil, index == hoveredViews.count - 1 {
            held = hoveredViews[index]
            heldPresentations = reshapePresentations
        }
        hoveredViews.remove(at: index)
    }

    /// Takes the help a hovered view drew this frame, where it has changed
    /// since the pointer entered it: a toggle clicked under the pointer
    /// explains what it does now, not what it did. The delay already served
    /// stands, as it does for a view re-registered under a resting pointer.
    package func hoveredViewDrew(owner: String, text: String) {
        for index in hoveredViews.indices where hoveredViews[index].owner == owner {
            hoveredViews[index].text = text
        }
        if held?.owner == owner, held?.text != text { held?.text = text }
    }

    // MARK: - A page moving under a resting pointer

    /// Opens the frame's reshape: the dispatcher re-resolving the hover
    /// against the frame's regions under a resting pointer
    /// (`MouseEventDispatcher.setRegions`).
    ///
    /// - Parameters:
    ///   - movedByTooltip: Whether this frame's status-bar tooltip changed the
    ///     rows the bar takes from the page, so that the page may have moved
    ///     under the pointer because of the tooltip (``held``).
    ///   - presentations: How many surfaces the frame presents over the page
    ///     — sheets, docked or not, covers, alerts, popovers, menus
    ///     (`WindowChromeState.presentationsOverPage`) — `0` when the page is
    ///     in front (``heldPresentations``).
    package func beginReshape(movedByTooltip: Bool, presentations: Int) {
        reshapeIsTooltipReflow = movedByTooltip
        reshapePresentations = presentations
    }

    /// Closes the frame's reshape, and lets go of a ``held`` candidate whose
    /// view no pointer could rest on now: gone from the screen, or behind
    /// something that takes the hover, such as a sheet's backdrop. The hover
    /// machine reports neither for a view the pointer is not over. Kept while
    /// the pointer rests on the rows the bar took for its tooltip, which
    /// covered the view the pointer was on (``held``), as long as nothing
    /// else has been presented over the page since the hold began, nor has
    /// what was presented gone (``heldPresentations``).
    ///
    /// - Parameters:
    ///   - pointerOnTooltipRows: Whether the pointer rests on the rows the
    ///     bar took from the page for the tooltip it shows
    ///     (`WindowChromeState.tooltipRows`).
    ///   - reaching: Whether a pointer on the region a handler registered
    ///     this frame would be heard by that handler
    ///     (`MouseEventDispatcher.reachesHoverObserver`).
    package func endReshape(pointerOnTooltipRows: Bool, reaching: (HitTestRegion.HandlerID) -> Bool) {
        reshapeIsTooltipReflow = false
        guard let held else { return }
        if pointerOnTooltipRows {
            if heldPresentations == reshapePresentations { return }
        } else if let id = held.handlerID, reaching(id) {
            return
        }
        self.held = nil
    }

    /// Lets go of a ``held`` candidate: the pointer has moved to another
    /// cell, and not onto the held view, or the hover machine's `.entered`
    /// would have taken it back (``hovering(_:handlerID:nowNanos:style:delaySeconds:)``).
    /// Called by the dispatcher once a move has run the hover machine.
    ///
    /// - Returns: Whether one was let go: the frame that takes it away is
    ///   owed, and nothing else may ask for it.
    package func notePointerMoved() -> Bool {
        let wasSilenced = pointerSilenced
        pointerSilenced = false
        guard held != nil else { return wasSilenced && hovered != nil }
        held = nil
        return true
    }

    /// Drops the pointer's candidate, held through the bar's reflow or not:
    /// the pointer has left the terminal's window
    /// (`MouseEventDispatcher.pointerLeft()`). The focused view's tooltip is
    /// not the pointer's and stays.
    ///
    /// - Returns: Whether one went: the frame that takes it away is owed.
    package func pointerLeft() -> Bool {
        let had = held ?? hovered != nil
        held = nil
        hoveredViews = []
        pointerSilenced = false
        return had
    }

    /// Sends the pointer's tooltip away until the pointer moves to another
    /// cell (``notePointerMoved()``), as a key press does on a Mac.
    ///
    /// A tooltip is help for the view the pointer rests on, and a reader who
    /// has started typing or moving the focus is not reading it: kept, the
    /// help of a toolbar button the pointer happened to rest on stayed in the
    /// status bar while the keyboard worked somewhere else entirely. The
    /// focused view's tooltip is not the pointer's and stays, as does the help
    /// key's reveal, which this does not reach.
    ///
    /// - Returns: Whether a tooltip the pointer had, shown or pending, went:
    ///   the frame that takes it away is owed.
    package func noteKeyPress() -> Bool {
        guard !pointerSilenced, held ?? hovered != nil else { return false }
        pointerSilenced = true
        return true
    }

    /// Records the focused view's help text for this walk.
    ///
    /// - Parameters:
    ///   - focusID: The focus identity of the control publishing it.
    ///   - revealsItself: Whether the subtree asked for
    ///     ``TooltipTrigger/onFocus``, so this shows without the help key.
    func focusing(
        _ text: String, focusID: String, handlerID: HitTestRegion.HandlerID?, nowNanos: Int64,
        style: TooltipStyle = .statusBar, delaySeconds: Double = 0,
        revealsItself: Bool = false
    ) {
        // Continuing to hold the focus keeps the ORIGINAL deadline; taking it
        // starts a new one. A candidate a moved focus left behind is already
        // gone (`syncFocus`), so one still here is this control's own from an
        // earlier walk. Compared on the text, as `hovering` compares, so help
        // text that changes under the focus is new help with a new wait.
        var deadline = nowNanos &+ Int64(max(0, delaySeconds) * 1_000_000_000)
        if let focused, focused.text == text { deadline = focused.showAtNanos }
        focused = Candidate(
            text: text, handlerID: handlerID, focusID: focusID, sinceNanos: nowNanos,
            showAtNanos: deadline, revealsItself: revealsItself, style: style)
        focusRepublished = true
    }

    /// Opens a walk of the scene. Called by the run loop at the top of every
    /// walk, beside the status bar's own per-walk resets.
    ///
    /// Clears nothing: the focus candidate stays readable until the walk's
    /// focused control publishes it again, because the status bar is sized
    /// from it before the walk begins. Whether that happens is what
    /// ``endFrame()`` asks.
    package func beginWalk() {
        focusRepublished = false
    }

    /// Closes the frame: a focus candidate its last walk did not publish again
    /// belongs to a control that has gone or no longer carries help, and goes
    /// with it. The last walk, because it is the one drawn.
    package func endFrame() {
        if !focusRepublished { focused = nil }
    }

    // MARK: - The keyboard reveal

    /// Toggles the focused view's tooltip, returning whether anything changed.
    ///
    /// `false` means there was nothing to reveal — no focused view carries help
    /// text — and the caller should let the key fall through to whatever else
    /// wants it rather than swallow it.
    @discardableResult
    package func toggleKeyboardReveal(focusID: String?) -> Bool {
        if keyboardRevealed, revealedFocusID == focusID {
            keyboardRevealed = false
            revealedFocusID = nil
            return true
        }
        guard focused != nil else { return false }
        keyboardRevealed = true
        revealedFocusID = focusID
        return true
    }

    /// Drops the focus candidate and the reveal when they belong to a view the
    /// focus has left.
    ///
    /// Called at the top of each walk with the current focus identity, so a
    /// focus moved by a key between frames takes its tooltip with it in the
    /// frame that shows the move. Kept until the end of a walk proved it gone,
    /// the candidate of a control the reader had tabbed off would have been
    /// drawn in the status bar once more, on the frame that shows the focus
    /// on another control. Not folded into ``beginWalk()``: that marks the
    /// walk, while this is a comparison against something outside this type.
    package func syncFocus(focusID: String?) {
        if let focused, focused.focusID != focusID { self.focused = nil }
        guard keyboardRevealed, revealedFocusID != focusID else { return }
        keyboardRevealed = false
        revealedFocusID = nil
    }

    // MARK: - Resolution

    /// The tooltip to draw this frame, or `nil`.
    ///
    /// - Parameter nowNanos: The frame's monotonic clock.
    /// - Returns: The text, its source, the region to anchor a popover to, and
    ///   how to present it.
    package func resolved(nowNanos: Int64) -> Resolved? {
        if let pointer = pointerCandidate {
            guard nowNanos >= pointer.showAtNanos else { return nil }
            return Resolved(
                text: pointer.text, source: .hover, handlerID: pointer.handlerID,
                style: pointer.style)
        }
        guard let focused, keyboardRevealed || focused.revealsItself else { return nil }
        // The help key IS the wait — a press has already taken longer than any
        // delay — so only a trigger-granted reveal serves the deadline out.
        guard keyboardRevealed || nowNanos >= focused.showAtNanos else { return nil }
        return Resolved(
            text: focused.text, source: .focus, handlerID: focused.handlerID,
            style: focused.style)
    }

    /// Where the panel for `text` comes in the order the panels of
    /// ``TooltipTrigger/always`` are placed: 0 for the view under the pointer,
    /// 1 for the focused one, 2 for the rest, which go in reading order.
    ///
    /// The slots are consulted with no delay and no help key: the panel is up
    /// already, and the rank only decides who keeps it when the page is too
    /// dense for all of them. Pointing at a view, or focusing it, is then how
    /// a reader brings back a panel that lost its place.
    package func placementRank(of text: String) -> Int {
        if hovered?.text == text { return 0 }
        if focused?.text == text { return 1 }
        return 2
    }

    /// The tooltip a frame is drawing.
    package struct Resolved {
        package var text: String
        var source: Source
        var handlerID: HitTestRegion.HandlerID?
        package var style: TooltipStyle
    }

    /// When a tooltip that is not yet showing would appear, as a monotonic
    /// deadline — `nil` when nothing is waiting on one.
    ///
    /// The run loop is demand-driven, so a tooltip whose delay expires between
    /// frames appears only if something else happens to redraw. This is what
    /// `HelpModifier` schedules a one-shot wake against.
    ///
    /// Both slots, because ``TooltipTrigger/onFocus`` waits out the same delay
    /// and nothing redraws for a focus that is merely still held. Hover first,
    /// matching ``resolved(nowNanos:)`` — the slot that would not be shown even
    /// once its own deadline passed is not worth waking for.
    package func pendingDeadlineNanos(nowNanos: Int64) -> Int64? {
        if let pointer = pointerCandidate {
            return pointer.showAtNanos > nowNanos ? pointer.showAtNanos : nil
        }
        guard let focused, focused.revealsItself, !keyboardRevealed,
            focused.showAtNanos > nowNanos
        else { return nil }
        return focused.showAtNanos
    }
}

// MARK: - Environment

/// Environment key for the app's tooltip state.
private struct TooltipStateKey: EnvironmentKey {
    static let defaultValue: TooltipState? = nil
}

extension EnvironmentValues {
    /// The app's tooltip state, or `nil` outside a running application.
    ///
    /// Optional for the reason every runtime service here is: these are the
    /// app's own objects, and a bare `EnvironmentValues()` has none. Absent
    /// means absent — `help(_:)` on a headless render publishes nowhere and
    /// draws nothing, which is the truth rather than a degraded mode.
    public var tooltipState: TooltipState? {
        get { self[TooltipStateKey.self] }
        set { self[TooltipStateKey.self] = newValue }
    }
}
