//  🖥️ TUI — A Terminal UI framework for Swift
//  GestureArena+Ranking.swift
//
//  What the gesture arena is built from: the role an attached gesture files
//  for its region, the entries it ranks, the ranking of the regions under a
//  press, and the gesture's view of a dispatcher event.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

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

// MARK: - Entries

extension GestureArena {
    /// A gesture contending in the arena, or in several: one under a press
    /// that came while an earlier arena still waited is that arena's
    /// contender, carried on.
    final class Contender {
        let participant: GestureParticipant

        /// Its region, as of the latest press it is contending for.
        var region: HitTestRegion

        /// The view its gesture is attached to, which its callbacks run as
        /// dispatched from (`StateRegistration.dispatchingIdentity`).
        var owner: ViewIdentity?

        /// Out of the running: it failed or was cancelled, so it holds nothing
        /// up.
        var isOut = false

        /// Held back on an earlier input, so it owes a flush once released.
        var isHeldBack = false

        /// Its view has gone — the frame on screen did not file it: removed
        /// from the tree (measured on macOS 15.8), disabled once it has been
        /// given up for that (``gaveUpAtDisable``), or, unmeasured, turned
        /// off by `isEnabled: false` or its mask, under
        /// a background a modal renders isolated, or on a row a scroll view
        /// windows out. It hears nothing and reports nothing, and what it
        /// holds back stays held, until the next event of the left button,
        /// once decided, gives it up
        /// (``MouseEventDispatcher/routeThroughGestures(_:matching:)``). Filed
        /// again before then, it is no longer departed, and carries on.
        var isDeparted = false

        /// Given up at its view's disable (decisions B-F2-2): cancelled then,
        /// so a `@GestureState` it updated reset, and out of the running —
        /// unless it had won the press, in which case it holds what it holds,
        /// as a departed one does, until the next event of the left button
        /// (``GestureArena/cancelDisabled(_:)``). Set once, so a view that
        /// stays disabled is not cancelled again.
        var gaveUpAtDisable = false

        /// How many arenas hold it back: it may report only at none.
        var holdCount = 0

        /// The arena that feeds it, the latest it contends in, so that one
        /// under two presses hears each input once. Weak: an arena keeps its
        /// contenders, not the other way round.
        weak var feeder: GestureArena?

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

        /// The gesture in this place, if it is one.
        var contender: Contender? {
            if case .gesture(let contender) = self { return contender }
            return nil
        }
    }
}

// MARK: - Ranking

extension GestureArena {
    /// Ranks the regions under a press, or returns `nil` when none of them is
    /// a gesture.
    ///
    /// A region that `yieldsToGestures` names — `.focusable()`'s
    /// click-to-focus — is no control of the view it covers in SwiftUI's
    /// sense, and outranks no gesture: it is ranked after the gestures behind
    /// it, ahead of the next control, so `Canvas { … }.focusable()
    /// .onTapGesture { … }` runs its tap. The focusing is done apart from the
    /// press (`MouseEventDispatcher.focusPressedView(_:)`); the region takes
    /// a press only so that what lies behind the view doesn't.
    ///
    /// - Parameters:
    ///   - matching: The regions containing the press, innermost first — an
    ///     attached gesture's region comes after its content's, because it is
    ///     filed behind them.
    ///   - roles: The gestures filed for the regions, by handler id.
    ///   - yieldsToGestures: Whether a region that is no gesture's ranks after
    ///     the gestures behind it.
    static func rank(
        _ matching: [HitTestRegion], roles: [HitTestRegion.HandlerID: GestureRole],
        yieldsToGestures: (HitTestRegion.HandlerID) -> Bool = { _ in false }
    ) -> (ranked: [Entry], simultaneous: [Contender])? {
        guard matching.contains(where: { roles[$0.handlerID] != nil }) else { return nil }
        var disabled: Set<HitTestRegion.HandlerID> = []
        for region in matching {
            if let role = roles[region.handlerID], role.disablesSubviews { disabled.formUnion(role.subtree) }
        }
        var ranked: [Entry] = []
        var simultaneous: [Contender] = []
        // Click-to-focus regions waiting for the next control behind them.
        var yielding: [Entry] = []
        for region in matching where !disabled.contains(region.handlerID) {
            guard let role = roles[region.handlerID] else {
                if yieldsToGestures(region.handlerID) {
                    yielding.append(.control(region))
                    continue
                }
                ranked += yielding
                yielding.removeAll()
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
        return (ranked + yielding, simultaneous)
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
            isInside: region.contains(x: event.x, y: event.y),
            subcell: CGSize(width: event.subcellX, height: event.subcellY))
    }
}
