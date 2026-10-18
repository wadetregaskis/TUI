//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureArena.swift
//
//  Arbitration between the gestures under one press of the left button, as
//  measured on macOS 15.8's SwiftUI.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Arena

/// The gestures contending for one press of the left button, ranked.
///
/// Built when a press lands where a gesture is attached, from the regions
/// under the pointer. Each entry is a gesture or an ordinary control's region —
/// a `Button`'s press is one of the view's own gestures, and ranks as one. The
/// ranking, measured on macOS 15.8:
///
/// - a view's own gestures, its subviews' included, come before one attached
///   with ``View/gesture(_:including:)``;
/// - one attached with ``View/highPriorityGesture(_:including:)`` comes before
///   them;
/// - one attached with ``View/simultaneousGesture(_:including:)`` is ranked
///   with nothing: it sees every event, and its callbacks run first.
///
/// Every gesture sees every event, so it is ready the moment the ones ahead of
/// it give up, but only the first undecided one may report: the ones after it
/// are held back. When a gesture recognizes, the ones after it are cancelled;
/// when it fails, the next is released — fed the event that released it, then
/// given what it held back, which is its end alone if it had already ended (as
/// macOS reports a drag that a button held up until its release). One that
/// ended while held back keeps that end, and hears nothing more until it is
/// released: then the end comes first and the event after it. A control
/// cannot wait like that: it is given the press once everything ahead of it
/// has failed, and the rest of the gesture through the dispatcher's ordinary
/// capture.
///
/// The arena outlives the release while a gesture is under way: undecided, a
/// double tap waiting for its second click, which a clock tick settles; or
/// recognized and not yet ended, a tap and a double tap together waiting out
/// the double tap's interval, or a sequence waiting for its second gesture,
/// which nothing but that gesture settles (all measured on macOS 15.8) — or
/// its view leaving.
///
/// A gesture whose view has gone, removed from the tree or disabled, hears
/// nothing more — no clock, no event — and reports nothing, and what it holds
/// back stays held, until the next event of the left button has been decided:
/// then it is given up, which releases what it held. That event is decided
/// as if it were still there. Measured on macOS 15.8 for a removed view
/// (``MouseEventDispatcher/routeThroughGestures(_:matching:)``).
///
/// A disabled view's gestures are given up at the disable instead, as macOS
/// does: a gesture that has not won its press lets go at once, and one that
/// has holds the next event of the left button, as above
/// (``cancelDisabled(_:)``).
///
/// So a departed gesture, and the arena it is in, live until that event —
/// in a session driven by the keyboard alone, for as long as it runs. Until
/// then the arena keeps the participant and its gesture's closures, and what
/// it holds back with theirs; and every rendered frame, the first arena input
/// after it rebuilds the set of participants the frame filed
/// (``markDeparted(filed:)``) and ticks the arena, a cost in the gestures on
/// screen. Nothing asks the run loop for a wake on its behalf: it has no
/// deadline. What counts as departed is whatever the last walk did not file,
/// which takes in more than the measured removal: a gesture
/// turned off by `gesture(_:isEnabled: false)` or its mask (filed with no
/// participant), one under a background a modal renders isolated, and one
/// on a row a scroll view windows out — all unmeasured on macOS. A gesture
/// whose view comes back before that event — windowed out, then back — is
/// filed again and carries on where it was, as a removed one never is; macOS
/// is unmeasured there too (decisions B-F2-3). One disabled, then enabled
/// again, was given up at the disable.
///
/// A press that comes while a ranked gesture still waits does not settle it:
/// both arenas live on (the dispatcher's ``MouseEventDispatcher/gestureArenas``),
/// as macOS 15.8 keeps a waiting gesture through a click elsewhere. A gesture
/// under both presses is one contender in both, carried on where it is: one
/// still waiting hears the new press — a double tap's second click — and one
/// that finished, ended or failed, stays finished and hears nothing of it.
/// A gesture not under the new press hears only the clock. A gesture in both
/// may report only once neither arena holds it back, and a control the
/// earlier arena still owes its click is no control of the new press. Once
/// the ranked gestures have all decided — only a simultaneous one still
/// waits — the next press starts every gesture under it afresh.
@MainActor
final class GestureArena {
    /// What the arena is fed.
    enum Input {
        case pointer(MouseEvent, timeNanos: Int64)
        case tick(Int64)
    }

    private var ranked: [Entry]
    private var simultaneous: [Contender]

    /// Which ranked gestures this arena holds back, by their place in
    /// ``ranked``: each counted once in its contender's ``Contender/holdCount``.
    private var heldHere: [Bool]

    /// Controls that declined the press, or were ranked after a gesture that
    /// recognized: out of the running, by their place in ``ranked``.
    private var controlsOut: Set<Int> = []

    /// The press, and its release once it comes, as the dispatcher received
    /// them: what a control held back behind a gesture is given when released.
    private let press: MouseEvent
    private var release: MouseEvent?

    /// A control has taken the press; the dispatcher's capture routes the rest
    /// of the gesture to it.
    private(set) var controlTookPress = false

    /// A control took the press and handed the rest of it to live
    /// hit-testing: the arena is done.
    private(set) var handedOff = false

    init(ranked: [Entry], simultaneous: [Contender], press: MouseEvent) {
        self.ranked = ranked
        self.simultaneous = simultaneous
        self.heldHere = Array(repeating: false, count: ranked.count)
        self.press = press
        for contender in contenders { contender.feeder = self }
    }

    /// The participants contending here.
    var participants: Set<ObjectIdentifier> {
        Set(contenders.lazy.map { ObjectIdentifier($0.participant) })
    }

    // MARK: A press while an arena waits

    /// Whether a ranked gesture is still under way — a double tap waiting for
    /// its next click, or one that has recognized and not yet ended — so that
    /// a press now continues what this arena began instead of starting its
    /// gestures afresh.
    ///
    /// Recognized counts as much as undecided. Measured on macOS 15.8: a
    /// `TapGesture().simultaneously(with: TapGesture(count: 2))` clicked
    /// once, and a sequence waiting for its second gesture, each keep the tap
    /// around them, which they cancelled, off a click on a plain view beside
    /// them: the first until the double tap's interval is out, the second
    /// until the sequence ends, with no limit — or, its view gone, through
    /// the first click after, which gives it up.
    ///
    /// A gesture attached with `simultaneousGesture` does not count: once the
    /// ranked gestures have decided, macOS starts them over at the next press
    /// (measured on macOS 15.8: a single tap that ran, beside a simultaneous
    /// double tap, runs again for the second click of a double click; a drag
    /// that failed at the first click drags at the second).
    ///
    /// An arena whose button is still down at the next press waits on
    /// nothing: its release was lost, and the new press supersedes it, as it
    /// does the dispatcher's own record of a press. Kept waiting, a drag
    /// under way in it never heard a release and held up what came after it
    /// for good.
    var waitsOnRankedGesture: Bool {
        guard !isButtonDown else { return false }
        return ranked.contains { entry in
            guard let contender = entry.contender else { return false }
            return !contender.isOut && isEngaged(contender)
        }
    }

    /// Takes over the contenders this press shares with `waiting`, the
    /// arenas still waiting on a ranked gesture, oldest first: each carries on
    /// where it is, fed from now on by this arena. A control one of them still
    /// owes its click is out of this press: as measured on macOS 15.8, a
    /// button behind a double tap that a second press gives up runs once, for
    /// the first click, and not at the second release.
    func adopt(from waiting: [GestureArena]) {
        guard !waiting.isEmpty else { return }
        var carried: [ObjectIdentifier: Contender] = [:]
        for arena in waiting {
            for contender in arena.contenders { carried[ObjectIdentifier(contender.participant)] = contender }
        }
        func carry(_ fresh: Contender) -> Contender {
            guard let kept = carried[ObjectIdentifier(fresh.participant)] else { return fresh }
            kept.region = fresh.region
            kept.feeder = self
            return kept
        }
        for index in ranked.indices {
            switch ranked[index] {
            case .gesture(let fresh):
                ranked[index] = .gesture(carry(fresh))
            case .control(let region):
                if waiting.contains(where: { $0.owesClick(to: region.handlerID) }) { controlsOut.insert(index) }
            }
        }
        simultaneous = simultaneous.map(carry)
    }

    /// Whether a control with this handler id is still waiting for the
    /// gestures ahead of it to give up, owed this arena's press and release.
    private func owesClick(to handlerID: HitTestRegion.HandlerID) -> Bool {
        ranked.indices.contains { index in
            guard owesClick(at: index), case .control(let region) = ranked[index] else { return false }
            return region.handlerID == handlerID
        }
    }

    /// Whether `successor` has taken over everything this arena still has a
    /// say in — every gesture still in the running, and no control waiting —
    /// so it can go: what it held back, `successor` holds back too, ranked
    /// the same way.
    func isTakenOver(by successor: GestureArena) -> Bool {
        guard !ranked.indices.contains(where: { owesClick(at: $0) }) else { return false }
        return contenders.allSatisfy { $0.isOut || $0.feeder === successor }
    }

    /// Whether the control at `index` still waits for this arena's press.
    private func owesClick(at index: Int) -> Bool {
        guard case .control = ranked[index], !controlTookPress, !handedOff else { return false }
        return !controlsOut.contains(index)
    }

    /// Lets go of every gesture this arena holds back, and of every one it
    /// feeds, as it is dropped.
    func leave() {
        for index in ranked.indices where heldHere[index] {
            heldHere[index] = false
            ranked[index].contender?.holdCount -= 1
        }
        for contender in contenders where contender.feeder === self { contender.feeder = nil }
    }

    /// Feeds, from now on, the gestures here that no arena feeds — ones an
    /// arena dropped at a press fed while this one still waits. Unfed, such a
    /// gesture never heard the clock that gives it up, and its deadline, once
    /// past, asked the run loop for a wake on every turn.
    func feedOrphans() {
        for contender in contenders where contender.feeder == nil { contender.feeder = self }
    }

    // MARK: Feeding

    /// Feeds one input to every contender in rank order, and gives the press
    /// to the first control that everything ahead of it has given up on.
    ///
    /// - Parameter input: The event or tick, or `nil` to settle what a
    ///   cancellation released without a new one.
    /// - Returns: Whether anything is engaged by the input: a gesture under
    ///   way, or a control holding the press.
    @discardableResult
    func process(_ input: Input?, dispatcher: MouseEventDispatcher) -> Bool {
        if case .pointer(let event, _)? = input, event.phase == .released { release = event }
        var engaged = feedSimultaneous(input)
        var released = true
        for index in ranked.indices {
            let step =
                switch ranked[index] {
                case .gesture(let contender):
                    advance(contender, at: index, by: input, releasedHere: released)
                case .control(let region):
                    advance(region, at: index, by: input, released: released, dispatcher: dispatcher)
                }
            switch step {
            case .passed:
                continue
            case .holding:
                engaged = true
                released = false
            case .waiting:
                released = false
            case .decided:
                return true
            }
        }
        return engaged
    }

    /// What one entry did with an input, for the entries ranked after it.
    private enum Step {
        /// Out of the running: it holds nothing up.
        case passed

        /// Undecided, or a control holding the press: everything after it is
        /// held back.
        case holding

        /// A control not yet given the press: everything after it waits too.
        case waiting

        /// It took the pointer: everything after it has been cancelled.
        case decided
    }

    /// Feeds the simultaneous gestures, which nothing holds back.
    ///
    /// - Returns: Whether any of them is under way.
    private func feedSimultaneous(_ input: Input?) -> Bool {
        var engaged = false
        for contender in simultaneous where !contender.isOut && !contender.isDeparted {
            if let input, contender.feeder === self { feed(contender, input, deliver: true) }
            if isEngaged(contender) { engaged = true } else { contender.isOut = isFinished(contender) }
        }
        return engaged
    }

    /// One ranked gesture's turn: fed and allowed to report if everything
    /// ahead of it has given up, fed and held back otherwise.
    ///
    /// A gesture held back that has already ended keeps that end until it is
    /// released, and hears nothing more while it waits — not even a press that
    /// would start it again. So a single tap behind a double tap runs for the
    /// first click when the second click gives the double tap up (held too
    /// long, or strayed), and does not run again for that second click: what
    /// macOS 15.8 does. Fed the second press, it started over, and the click
    /// it had recognized was lost.
    ///
    /// A gesture in several arenas is released once none of them holds it
    /// back, and only the latest feeds it.
    ///
    /// - Parameter releasedHere: Whether everything ahead of it in this arena
    ///   has given up.
    private func advance(_ contender: Contender, at index: Int, by input: Input?, releasedHere: Bool) -> Step {
        guard !contender.isOut, let root = contender.participant.root else { return .passed }
        // Its view gone, it waits to be given up, holding what it held.
        if contender.isDeparted { return .holding }
        if heldHere[index] == releasedHere {
            heldHere[index] = !releasedHere
            contender.holdCount += releasedHere ? -1 : 1
        }
        let released = contender.holdCount == 0
        let input = contender.feeder === self ? input : nil
        let holdsEnd = contender.isHeldBack && root.phase == .ended
        if released, holdsEnd {
            // The end came before this input, so it is reported first; the
            // input then goes to it as to any gesture under way.
            contender.isHeldBack = false
            root.flush()
            if let input { feed(contender, input, deliver: true) }
        } else if released {
            if let input { feed(contender, input, deliver: !contender.isHeldBack) }
            if contender.isHeldBack {
                contender.isHeldBack = false
                root.flush()
            }
        } else if let input, !holdsEnd {
            feed(contender, input, deliver: false)
            contender.isHeldBack = true
        }
        if root.phase == .failed || root.phase == .idle {
            contender.isOut = true
            return .passed
        }
        guard released, root.phase.hasRecognized else { return .holding }
        cancel(after: index)
        return .decided
    }

    /// One ranked control's turn: given the press once everything ahead of
    /// it has given up.
    private func advance(
        _ region: HitTestRegion, at index: Int, by input: Input?, released: Bool,
        dispatcher: MouseEventDispatcher
    ) -> Step {
        if controlTookPress { return .holding }
        if controlsOut.contains(index) { return .passed }
        guard released else { return .waiting }
        // Released without an event of its own — by a clock tick or a
        // cancellation — after the button came up: the release it missed is
        // still owed, so the click is given whole. Another press may be under
        // way by then, its capture set aside meanwhile. (Released by a drag or
        // a release, the dispatcher routes that event to it next.)
        if !isPointer(input), let release {
            return dispatcher.settingCaptureAside { give(region, at: index, release: release, dispatcher: dispatcher) }
        }
        return give(region, at: index, release: nil, dispatcher: dispatcher)
    }

    /// Offers the press to a control, and the release after it if given.
    private func give(
        _ region: HitTestRegion, at index: Int, release: MouseEvent?, dispatcher: MouseEventDispatcher
    ) -> Step {
        switch dispatcher.offer(press, to: region) {
        case .declined:
            controlsOut.insert(index)
            return .passed
        case .captured:
            controlTookPress = true
            cancel(after: index)
            if let release { _ = dispatcher.routeAgainstItsPress(release) }
            return .decided
        case .handedOff:
            // A menu-opening press: the rest of the gesture belongs to the
            // menu, hit-tested live. Nothing here hears it.
            handedOff = true
            cancel(after: -1)
            return .decided
        }
    }

    /// Whether the arena has nothing left to decide: the button is up, and no
    /// gesture or held-back control is still waiting.
    var isSettled: Bool {
        if handedOff { return true }
        guard release != nil else { return false }
        // Still owing a held-back end counts as undecided: in one arena that
        // means something ahead of it is, but with another press's arena
        // holding it back, this one stays to decide what comes after it.
        if contenders.contains(where: { !$0.isOut && (isEngaged($0) || $0.isHeldBack) }) { return false }
        if controlTookPress { return true }
        return !ranked.indices.contains { index in
            if case .control = ranked[index] { return !controlsOut.contains(index) }
            return false
        }
    }

    /// Whether the button is still down for the press this arena was built
    /// for.
    var isButtonDown: Bool { release == nil && !handedOff }

    /// The earliest instant a contender needs to hear the clock.
    var deadline: Int64? {
        contenders.lazy.filter { !$0.isOut && !$0.isDeparted }.compactMap { $0.participant.deadline }.min()
    }

    // MARK: Helpers

    private var contenders: [Contender] {
        ranked.compactMap(\.contender) + simultaneous
    }

    private func isEngaged(_ contender: Contender) -> Bool {
        // Given up at its disable having won its press: cancelled, and still
        // holding the arena until the next event of the left button.
        if contender.gaveUpAtDisable { return !contender.isOut }
        guard let phase = contender.participant.root?.phase else { return false }
        return phase == .possible || phase == .active
    }

    private func isFinished(_ contender: Contender) -> Bool {
        guard let phase = contender.participant.root?.phase else { return true }
        return phase.isTerminal || phase == .idle
    }

    private func isPointer(_ input: Input?) -> Bool {
        if case .pointer? = input { return true }
        return false
    }

    /// Feeds `input` to one contender, in its region's cells.
    private func feed(_ contender: Contender, _ input: Input, deliver: Bool) {
        guard let root = contender.participant.root else { return }
        switch input {
        case .tick(let now):
            root.receive(.tick(now), deliver: deliver)
        case .pointer(let event, let time):
            var pointer = Self.pointer(event, in: contender.region, at: time)
            pointer.spaceOrigin = contender.participant.pointerSpaces
            root.receive(.pointer(pointer), deliver: deliver)
        }
    }

    /// Cancels every entry ranked after `index` — a gesture ahead of them has
    /// recognized, or a control has taken the press — and, for an `index` of
    /// `-1`, every simultaneous gesture too.
    private func cancel(after index: Int) {
        for later in ranked.indices where later > index {
            switch ranked[later] {
            case .gesture(let contender):
                cancel(contender)
            case .control:
                controlsOut.insert(later)
            }
        }
        if index < 0 { simultaneous.forEach(cancel) }
    }

    /// Gives up on every gesture whose participant is not in `kept`.
    func cancel(allBut kept: Set<ObjectIdentifier>) {
        for contender in contenders where !kept.contains(ObjectIdentifier(contender.participant)) {
            cancel(contender)
        }
    }

    /// Marks each gesture here whose participant is not in `filed` as
    /// departed (``Contender/isDeparted``), and the rest as not.
    func markDeparted(filed: Set<ObjectIdentifier>) {
        for contender in contenders {
            contender.isDeparted = !filed.contains(ObjectIdentifier(contender.participant))
        }
    }

    /// Gives up, at the disable, on every gesture here whose view the frame on
    /// screen files as disabled (`disabled`, by participant), and says
    /// whether that took one out of the running — whether what it held back
    /// may now run.
    ///
    /// As macOS 15.8 does (F2 probes review4b–d; decisions B-F2-2): each is
    /// cancelled at once, so a `@GestureState` it updated resets then. One
    /// that has not won the press — a double tap waiting for its next click,
    /// a tap held back behind it — lets go at once, so the tap around a row
    /// disabled while its double tap waits runs the row's click at the
    /// disable. One that has won it — a sequence waiting for its second
    /// gesture, a drag under way — still holds the next event of the left
    /// button, as a departed gesture does: a waiting sequence disabled keeps
    /// the tap around it, which it had cancelled, off the next click beside
    /// it, and that click then gives it up.
    func cancelDisabled(_ disabled: Set<ObjectIdentifier>) -> Bool {
        var released = false
        for contender in contenders
        where !contender.isOut && !contender.gaveUpAtDisable
            && disabled.contains(ObjectIdentifier(contender.participant))
        {
            contender.gaveUpAtDisable = true
            let won = hasWon(contender)
            contender.participant.root?.cancel()
            if !won {
                contender.isOut = true
                released = true
            }
        }
        return released
    }

    /// Whether `contender` has won its press: a ranked gesture that nothing
    /// holds back and that has recognized, so it cancelled what was ranked
    /// after it. A simultaneous gesture holds nothing, and never has.
    private func hasWon(_ contender: Contender) -> Bool {
        guard ranked.contains(where: { $0.contender === contender }),
            let phase = contender.participant.root?.phase
        else { return false }
        return contender.holdCount == 0 && !contender.isHeldBack && phase.hasRecognized
    }

    /// Whether a gesture here, still in the running and not yet given up for
    /// it, is filed as disabled (`disabled`, by participant): what the run
    /// loop asks after a walk, to ask for the frame that gives it up.
    func hasPendingDisable(_ disabled: Set<ObjectIdentifier>) -> Bool {
        contenders.contains { contender in
            !contender.isOut && !contender.gaveUpAtDisable
                && disabled.contains(ObjectIdentifier(contender.participant))
        }
    }

    /// Gives up on every departed gesture still in the running, and says
    /// whether there was one.
    func cancelDeparted() -> Bool {
        var gaveUp = false
        for contender in contenders where contender.isDeparted && !contender.isOut {
            cancel(contender)
            gaveUp = true
        }
        return gaveUp
    }

    private func cancel(_ contender: Contender) {
        guard !contender.isOut else { return }
        contender.isOut = true
        // Already cancelled at its disable: once is its reset.
        if !contender.gaveUpAtDisable { contender.participant.root?.cancel() }
    }
}
