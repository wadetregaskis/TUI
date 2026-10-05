//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureArena+Ranking.swift
//
//  What the gesture arena is built from: the role an attached gesture files
//  for its region, the ranking of the regions under a press, and the
//  gesture's view of a dispatcher event.
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

// MARK: - Ranking

extension GestureArena {
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
