//  🖥️ TUI — A Terminal UI framework for Swift
//  DragAndDropSession+Carry.swift
//
//  A drag carried from the keyboard (owner ruling A53-KEYBOARD-DRAG): picked
//  up from a focused `.draggable`, carried by Tab and the arrows among the
//  focus stops that can take it, dropped with Return, sent home with Escape.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStrings

extension DragAndDropSession {
    /// A drag the keyboard carries.
    ///
    /// It is the pointer's drag (``active``), driven by a pointer of its own:
    /// one placed on the focus stop the carry is at, which ``followCarry()``
    /// keeps there. So what a drag over a destination does — `isTargeted`,
    /// the badge, the operation, a drop delegate's moves — a carry does too,
    /// and Return drops it as a release there would.
    ///
    /// While it lasts, Tab and the arrows move the focus only among the stops
    /// that can take it (``carryStops()``): the stops of the destinations that
    /// accept what it carries, the spring-loaded controls a pause would press
    /// (Return presses one, and the carry goes on), and the stop it was picked
    /// up from, where Return puts it back. A stray Return cannot drop it on an
    /// unrelated list, because unrelated lists are not among them.
    package struct Carry {
        /// The focus stop it was picked up from.
        let origin: String

        /// Where the origin is drawn, for an origin no region names: the
        /// `.draggable`'s own stop, drawn by its drag handle's region.
        let originRect: HitTestRegion

        /// The focus manager whose focus it follows. Weak: the session
        /// outlives a manager a test makes.
        weak var focusManager: FocusManager?

        /// Whether the operation is flipped from the destination's proposal —
        /// a copy to a move or back — as holding Option does for the pointer.
        /// Space toggles it.
        var flipsOperation = false

        /// How many rows down the stop it is at it points: Up and Down move
        /// it between the rows of a destination taller than one, so a `List`
        /// is one stop whose landing slot they move. Back to `0` at each stop.
        var row = 0

        /// Where each stop it can reach is drawn, but the one it is at: what
        /// ``carryCues`` marks, as of the frame before the one drawing.
        var reachable: [HitTestRegion] = []
    }

    /// The chord that picks a focused `.draggable` up and, again, puts it
    /// back: a list row's pick-up chord's default, Ctrl-R.
    package static let carryChord = KeyboardShortcut("r", modifiers: .control)

    /// Picks `payload` up from the focus stop `origin`, which `rect` draws, and
    /// carries it.
    ///
    /// - Parameters:
    ///   - payload: What the drag carries.
    ///   - preview: Its picture, drawn beside the stop the carry is at.
    ///   - source: The view picked up, drawn as gone while it is carried.
    ///   - allowedOperations: The operations the source allows.
    ///   - origin: The focus stop it was picked up from.
    ///   - handle: The region that draws the view picked up: where the origin
    ///     is, where no region names the stop.
    ///   - focusManager: The focus manager the carry moves.
    /// - Returns: Whether the carry began.
    @discardableResult
    package func beginCarry(
        payload: Any, preview: FrameBuffer, source: ViewIdentity, allowedOperations: DropOperation.Set,
        origin: String, handle: HitTestRegion.HandlerID, focusManager: FocusManager
    ) -> Bool {
        guard active == nil, let rect = stopRect(origin) ?? dispatcher?.regionRect(for: handle) else { return false }
        let point = Self.carryPoint(of: rect)
        lastAbsoluteEvent = MouseEvent(button: .left, phase: .pressed, x: point.x, y: point.y)
        carry = Carry(origin: origin, originRect: rect, focusManager: focusManager)
        // Beside the stop, not over it: the stop is what the carry is at.
        begin(
            payload: payload, preview: preview, anchor: .offset(x: 1, y: 0), source: source,
            allowedOperations: allowedOperations)
        if active == nil { carry = nil }
        return carry != nil
    }

    /// Answers a key while a carry lasts, or `nil` when none does.
    ///
    /// Tab and the arrows move among the stops that can take the drag — Up and
    /// Down first between the rows of a destination taller than one; Return
    /// drops it on the destination at the focus, presses a spring-loaded
    /// control there, or puts it back at its origin; Escape and the pick-up
    /// chord put it back; Space flips its operation; the paging keys go on to
    /// the drag navigators, which scroll what it is over. Other plain keys are
    /// swallowed — a field the focus passed must not type them — and a chord
    /// goes on its way, so the app's quit key still quits.
    package func handleCarryKey(_ event: KeyEvent) -> Bool? {
        guard carry != nil else { return nil }
        guard active != nil else {
            carry = nil
            return nil
        }
        if KeyboardShortcut.trigger(for: event) == Self.carryChord.trigger {
            endCarry(dropping: false)
            return true
        }
        switch event.key {
        case .tab:
            moveCarry(by: event.shift ? -1 : 1)
        case .down:
            if !moveCarryRow(by: 1) { moveCarry(by: 1) }
        case .up:
            if !moveCarryRow(by: -1) { moveCarry(by: -1) }
        case .right:
            moveCarry(by: 1)
        case .left:
            moveCarry(by: -1)
        case .enter:
            endCarry(dropping: true)
        case .escape:
            endCarry(dropping: false)
        case .space:
            carry?.flipsOperation.toggle()
            dragMoved()
        case .pageUp, .pageDown, .home, .end:
            // The drag navigators' (layer 0.5): they scroll what the carry
            // is over, so a destination out of sight can be reached.
            return nil
        default:
            return event.ctrl || event.alt || event.command ? nil : true
        }
        return true
    }

    /// Puts the carried drag where the focus is now, as last drawn: what the
    /// render loop asks before each frame, so the drag follows a stop that
    /// moved, and what a move of the carry asks at once.
    package func followCarry() {
        guard carry != nil, active != nil, let focused = carry?.focusManager?.currentFocusedID else { return }
        let stops = carryStops()
        carry?.reachable = stops.filter { $0.id != focused }.map(\.rect)
        guard let rect = stops.first(where: { $0.id == focused })?.rect ?? stopRect(focused) else { return }
        var point = Self.carryPoint(of: rect)
        point.y += min(carry?.row ?? 0, max(0, rect.height - 1))
        guard lastAbsoluteEvent?.x != point.x || lastAbsoluteEvent?.y != point.y else { return }
        lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: point.x, y: point.y)
        dragMoved()
    }

    /// Where to mark the stops a carry can reach, but the one it is at, in the
    /// screen's coordinates: the cell after each one's top row, where the
    /// carried picture would be drawn were the carry there. Empty while
    /// nothing is carried.
    package var carryCues: [(x: Int, y: Int)] {
        guard active != nil else { return [] }
        return carry?.reachable.map { (Self.carryPoint(of: $0).x + 1, $0.offsetY) } ?? []
    }

    /// What the status bar's Return and Escape say while a carry lasts: drop
    /// it, at a destination; put it back, at its origin; and nothing for
    /// Return at a spring-loaded control, whose own verb stands. `nil` while
    /// nothing is carried.
    package var carryLabels: (returnKey: String?, escape: String)? {
        guard let carry, active != nil else { return nil }
        let service = LocalizationService.shared
        let putBack = service.string(for: LocalizationKey.StatusBar.cancelMove)
        let focused = carry.focusManager?.currentFocusedID
        if focused == nil || focused == carry.origin { return (putBack, putBack) }
        let drops = proposedOperation.map { $0 != .forbidden && $0 != .cancel } ?? false
        return (drops ? service.string(for: LocalizationKey.StatusBar.dropCarried) : nil, putBack)
    }

    /// Whether the keyboard flips the operation of the carry under way.
    var carryFlipsOperation: Bool { carry?.flipsOperation == true }

    /// The focus stops a carry can be at, in reading order, each with where
    /// it is drawn (``Carry``).
    func carryStops() -> [(id: String, rect: HitTestRegion)] {
        guard let carry, let drag = active, let dispatcher else { return [] }
        // Each stop, with where it is drawn should no region name it — a
        // view's own stop, which its modifier's region draws.
        var candidates: [(id: String, fallback: HitTestRegion?)] = []
        // The stops of each destination that accepts the payload: those it
        // filed, or else the stops drawn inside it.
        for target in targets where target.accepts(drag.payload) {
            let zone = dispatcher.regionRect(for: target.handlerID)
            if !target.focusIDs.isEmpty {
                candidates += target.focusIDs.map { ($0, zone) }
            } else if let zone {
                candidates += dispatcher.regions.lazy.filter { Self.contains(zone, $0) }.compactMap(\.focusID)
                    .map { ($0, nil) }
            }
        }
        // The controls a pause would press.
        for spring in springLoadTargets {
            candidates += dispatcher.regions.lazy.filter { $0.handlerID == spring.handlerID }.compactMap(\.focusID)
                .map { ($0, nil) }
        }
        candidates.append((carry.origin, carry.originRect))
        var seen: Set<String> = []
        var stops: [(id: String, rect: HitTestRegion)] = []
        for (id, fallback) in candidates where seen.insert(id).inserted {
            if let rect = stopRect(id) ?? fallback { stops.append((id, rect)) }
        }
        return stops.sorted { ($0.rect.offsetY, $0.rect.offsetX) < ($1.rect.offsetY, $1.rect.offsetX) }
    }

    // MARK: - Moving and ending

    /// Moves the carry `step` rows within the destination it is at, if that
    /// is taller than a row and the row is inside it, and says whether it did.
    private func moveCarryRow(by step: Int) -> Bool {
        guard let carry, proposedOperation != nil, let focused = carry.focusManager?.currentFocusedID,
            let rect = carryStops().first(where: { $0.id == focused })?.rect
        else { return false }
        let row = carry.row + step
        guard rect.height > 1, (0..<rect.height).contains(row) else { return false }
        self.carry?.row = row
        followCarry()
        return true
    }

    /// Moves the focus `step` stops on among ``carryStops()``, round the end.
    private func moveCarry(by step: Int) {
        guard let focusManager = carry?.focusManager else { return }
        let stops = carryStops()
        guard !stops.isEmpty else { return }
        let count = stops.count
        let next: Int
        if let focused = focusManager.currentFocusedID, let here = stops.firstIndex(where: { $0.id == focused }) {
            next = ((here + step) % count + count) % count
        } else {
            next = step > 0 ? 0 : count - 1
        }
        focusManager.focus(id: stops[next].id)
        carry?.row = 0
        followCarry()
    }

    /// Ends the carry: drops it where the focus is — or presses the
    /// spring-loaded control there and carries on — or puts it back at its
    /// origin.
    ///
    /// Dropped only on a stop still drawn (``carryStops()``): a stop can keep
    /// the focus while drawn nowhere — scrolled or clipped out of sight —
    /// and the carry's pointer stays where it last followed the focus, so it
    /// dropped there, on whatever is drawn there now. It goes back instead.
    private func endCarry(dropping: Bool) {
        guard let carry else { return }
        followCarry()
        if dropping, let focused = carry.focusManager?.currentFocusedID, focused != carry.origin,
            carryStops().contains(where: { $0.id == focused })
        {
            if let point = lastAbsoluteEvent, springLoadTarget(at: point) != nil, proposedOperation == nil {
                springLoadTarget(at: point)?.activate()
                return
            }
            self.carry = nil
            if !performDrop() { carry.focusManager?.focus(id: carry.origin) }
            return
        }
        self.carry = nil
        cancelReturningToOrigin()
        carry.focusManager?.focus(id: carry.origin)
    }

    // MARK: - Geometry

    /// The spring-loaded control drawn at `event`'s cell, if any.
    private func springLoadTarget(at event: MouseEvent) -> SpringLoadTarget? {
        guard let dispatcher else { return nil }
        let ids = dispatcher.handlerIDs(at: event.x, y: event.y)
        return springLoadTargets.first { ids.contains($0.handlerID) }
    }

    /// Where the focus stop `id` is drawn: the largest region carrying it.
    private func stopRect(_ id: String) -> HitTestRegion? {
        dispatcher?.regions.lazy.filter { $0.focusID == id }.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// The cell a carry at `rect` points at: its top row's last cell, so the
    /// picture drawn just after it sits beside the stop.
    private static func carryPoint(of rect: HitTestRegion) -> (x: Int, y: Int) {
        (rect.offsetX + max(0, rect.width - 1), rect.offsetY)
    }

    /// Whether `inner`'s rectangle lies inside `outer`'s.
    private static func contains(_ outer: HitTestRegion, _ inner: HitTestRegion) -> Bool {
        inner.offsetX >= outer.offsetX && inner.offsetY >= outer.offsetY
            && inner.offsetX + inner.width <= outer.offsetX + outer.width
            && inner.offsetY + inner.height <= outer.offsetY + outer.height
    }
}
