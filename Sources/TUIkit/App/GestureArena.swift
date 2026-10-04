//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureArena.swift
//
//  Arbitration between the gestures under one press of the left button, as
//  measured on macOS 15.8's SwiftUI.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Role

/// What an attached gesture filed with the dispatcher for its region: who it
/// is, how it ranks, and which regions it covers.
struct GestureRole {
    /// The gesture, or `nil` when its mask leaves it off and only its effect
    /// on its subviews remains.
    let participant: GestureParticipant?

    /// How it ranks against the gestures of the view it is attached to.
    let priority: GesturePriority

    /// Whether its mask turns off every gesture in its subtree.
    let disablesSubviews: Bool

    /// The handler ids of the regions its view's content filed — its
    /// subviews. Recorded only when its priority or mask needs them.
    let subtree: Set<HitTestRegion.HandlerID>
}

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
/// macOS reports a drag that a button held up until its release). A control
/// cannot wait like that: it is given the press once everything ahead of it
/// has failed, and the rest of the gesture through the dispatcher's ordinary
/// capture.
///
/// The arena outlives the release while a gesture is undecided — a double tap
/// waiting for its second click — and a clock tick or the next press settles
/// it.
@MainActor
final class GestureArena {
    /// A gesture contending in the arena.
    final class Contender {
        let participant: GestureParticipant
        let region: HitTestRegion

        /// Out of the running: it failed or was cancelled, so it holds nothing
        /// up.
        var isOut = false

        /// Held back on an earlier input, so it owes a flush once released.
        var isHeldBack = false

        init(participant: GestureParticipant, region: HitTestRegion) {
            self.participant = participant
            self.region = region
        }
    }

    /// One place in the ranking.
    enum Entry {
        case gesture(Contender)
        case control(HitTestRegion)

        var handlerID: HitTestRegion.HandlerID {
            switch self {
            case .gesture(let contender): contender.region.handlerID
            case .control(let region): region.handlerID
            }
        }
    }

    /// What the arena is fed.
    enum Input {
        case pointer(MouseEvent, timeNanos: Int64)
        case tick(Int64)
    }

    private let ranked: [Entry]
    private let simultaneous: [Contender]

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
        self.press = press
    }

    // MARK: Ranking

    /// Ranks the regions under a press, or returns `nil` when none of them is
    /// a gesture.
    ///
    /// - Parameter matching: The regions containing the press, innermost
    ///   first — an attached gesture's region comes after its content's,
    ///   because it is filed behind them.
    static func rank(
        _ matching: [HitTestRegion], roles: [HitTestRegion.HandlerID: GestureRole]
    ) -> (ranked: [Entry], simultaneous: [Contender])? {
        guard matching.contains(where: { roles[$0.handlerID] != nil }) else { return nil }
        var disabled: Set<HitTestRegion.HandlerID> = []
        for region in matching {
            if let role = roles[region.handlerID], role.disablesSubviews { disabled.formUnion(role.subtree) }
        }
        var ranked: [Entry] = []
        var simultaneous: [Contender] = []
        for region in matching where !disabled.contains(region.handlerID) {
            guard let role = roles[region.handlerID] else {
                ranked.append(.control(region))
                continue
            }
            guard let participant = role.participant else { continue }
            let contender = Contender(participant: participant, region: region)
            switch role.priority {
            case .normal:
                ranked.append(.gesture(contender))
            case .high:
                let ahead = ranked.firstIndex { role.subtree.contains($0.handlerID) } ?? ranked.endIndex
                ranked.insert(.gesture(contender), at: ahead)
            case .simultaneous:
                simultaneous.append(contender)
            }
        }
        return (ranked, simultaneous)
    }

    /// Takes over from `previous`, an arena still waiting on a gesture when
    /// this press came: the gestures in both carry on — a double tap's second
    /// press finds the recognizer its first left waiting — and the rest of
    /// `previous` is given up on, which may release what it held back.
    func inherit(from previous: GestureArena, dispatcher: MouseEventDispatcher) {
        let carried = Dictionary(
            previous.contenders.map { (ObjectIdentifier($0.participant), $0.isHeldBack) },
            uniquingKeysWith: { first, _ in first })
        for contender in contenders where carried[ObjectIdentifier(contender.participant)] == true {
            contender.isHeldBack = true
        }
        previous.cancel(allBut: Set(carried.keys).intersection(contenders.map { ObjectIdentifier($0.participant) }))
        previous.process(nil, dispatcher: dispatcher)
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
                    advance(contender, at: index, by: input, released: released)
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
        for contender in simultaneous where !contender.isOut {
            if let input { feed(contender, input, deliver: true) }
            if isEngaged(contender) { engaged = true } else { contender.isOut = isFinished(contender) }
        }
        return engaged
    }

    /// One ranked gesture's turn: fed and allowed to report if everything
    /// ahead of it has given up, fed and held back otherwise.
    private func advance(_ contender: Contender, at index: Int, by input: Input?, released: Bool) -> Step {
        guard !contender.isOut, let root = contender.participant.root else { return .passed }
        if released {
            if let input { feed(contender, input, deliver: !contender.isHeldBack) }
            if contender.isHeldBack {
                contender.isHeldBack = false
                root.flush()
            }
        } else if let input {
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
        switch dispatcher.offer(press, to: region) {
        case .declined:
            controlsOut.insert(index)
            return .passed
        case .captured:
            controlTookPress = true
            cancel(after: index)
            // Released without an event of its own — by a clock tick or a
            // cancellation — after the button came up: the release it missed
            // is still owed. (Released by a drag or a release, the dispatcher
            // routes that event to it next.)
            if !isPointer(input), let release { _ = dispatcher.routeAgainstItsPress(release) }
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
        for contender in contenders where !contender.isOut && isEngaged(contender) {
            if let phase = contender.participant.root?.phase, phase == .possible || phase == .active {
                return false
            }
        }
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
        contenders.lazy.filter { !$0.isOut }.compactMap { $0.participant.deadline }.min()
    }

    // MARK: Helpers

    private var contenders: [Contender] {
        ranked.compactMap {
            if case .gesture(let contender) = $0 { return contender }
            return nil
        } + simultaneous
    }

    private func isEngaged(_ contender: Contender) -> Bool {
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
            root.receive(.pointer(Self.pointer(event, in: contender.region, at: time)), deliver: deliver)
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

    private func cancel(_ contender: Contender) {
        guard !contender.isOut else { return }
        contender.isOut = true
        contender.participant.root?.cancel()
    }

    /// The gesture's view of a dispatcher event.
    static func pointer(_ event: MouseEvent, in region: HitTestRegion, at time: Int64) -> GesturePointer {
        let kind: GesturePointer.Kind =
            switch event.phase {
            case .pressed: .down
            case .released: .up
            default: .moved
            }
        var modifiers: EventModifiers = []
        if event.shift { modifiers.insert(.shift) }
        if event.ctrl { modifiers.insert(.control) }
        if event.meta { modifiers.insert(.option) }
        return GesturePointer(
            kind: kind,
            location: CellPoint(x: event.x - region.localOriginX, y: event.y - region.localOriginY),
            globalLocation: CellPoint(x: event.x, y: event.y),
            modifiers: modifiers, timeNanos: time,
            isInside: region.contains(x: event.x, y: event.y))
    }
}
