//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryCoordinator+Spaces.swift
//
//  Coordinate spaces: the asks a walk registers, the owners that answer them
//  from what they drew, and what is kept for the next frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Asking

extension GeometryCoordinator {
    /// What an owner found for the view whose marker is `id` in `space`, in
    /// this walk or the last one that found it.
    func keptObservation(for id: HitTestRegion.HandlerID, in space: CoordinateSpace) -> GeometryObservation? {
        kept[id]?.bySpace[space]
    }

    /// ``keptObservation(for:in:)``, with what the view was predicted to be at
    /// when it was found there — `nil` where no prediction was made.
    func keptEntry(
        for id: HitTestRegion.HandlerID, in space: CoordinateSpace
    ) -> (observation: GeometryObservation, predicted: CellPoint?)? {
        guard let entry = kept[id], let observation = entry.bySpace[space] else { return nil }
        return (observation, entry.predicted[space])
    }

    /// Notes that the view whose marker is `id` asked about `space` after its
    /// render, so it is found there from its next render on — an action that
    /// asks a proxy where its view is, the first time it does.
    func noteLateAsk(id: HitTestRegion.HandlerID, space: CoordinateSpace) {
        guard space != .local else { return }
        var spaces = lateAsks[id] ?? []
        guard !spaces.contains(space) else { return }
        spaces.append(space)
        lateAsks[id] = spaces
    }

    /// Registers `ask`, once its view has rendered, for the owners of the
    /// spaces it wants to find it in — and answers whether it wants anything,
    /// which is whether the view stamps its marker.
    ///
    /// A view drawn again in the same walk registers again under the same id,
    /// and replaces the first registration with what it asked the second time.
    @discardableResult
    package func register(_ ask: GeometryAsk) -> Bool {
        let wanted = ask.wanted.filter { $0 != .local }
        guard !wanted.isEmpty else { return false }
        if let previous = asks[ask.id] {
            for space in previous.wanted where space != .local && previous.found[space] == nil {
                decrementUnanswered(space)
            }
        } else {
            askOrder.append(ask.id)
        }
        asks[ask.id] = ask
        for space in wanted {
            unanswered[space, default: 0] += 1
            unansweredTotal += 1
        }
        let isReader = ask.role == .reader
        if kept[ask.id] == nil {
            kept[ask.id] = KeptObservations(identity: ask.identity, isReader: isReader)
        } else {
            kept[ask.id]?.askedThisWalk = true
            kept[ask.id]?.isReader = isReader
        }
        if isReader { keepsReaders = true }
        return true
    }

    /// Registers what a reporter does once the frame is done: asked again, by
    /// a proxy answering from what the owners found.
    func registerReporter(_ ask: GeometryAsk, report: @escaping (GeometryProxy) -> Void) {
        guard register(ask) else { return }
        reporters[ask.id] = report
    }

    private func decrementUnanswered(_ space: CoordinateSpace) {
        unanswered[space, default: 0] -= 1
        unansweredTotal -= 1
    }

    /// Whether any view this walk is still waiting to be found in one of
    /// `spaces` — what an owner asks before scanning what it drew.
    func isWaiting(in spaces: [CoordinateSpace]) -> Bool {
        guard unansweredTotal > 0 else { return false }
        return spaces.contains { unanswered[$0, default: 0] > 0 }
    }

    /// Moves the predictions made for the views whose markers `drawn` carries
    /// by `delta`, for every space no owner has answered for them yet — what
    /// a scroll view does when its offset moved after its content was drawn
    /// (`_ScrollViewCore.settlePlacement`).
    func movePredictions(in drawn: FrameBuffer, by delta: CellPoint) {
        guard unansweredTotal > 0 else { return }
        drawn.forEachGeometryMarker { id, _, _ in asks[id]?.movePredictions(by: delta) }
    }

    /// Records that `ask`'s view is at `observation` in `space`.
    private func answer(_ ask: GeometryAsk, in space: CoordinateSpace, with observation: GeometryObservation) {
        ask.found[space] = observation
        decrementUnanswered(space)
        kept[ask.id, default: KeptObservations(identity: ask.identity, isReader: ask.role == .reader)]
            .bySpace[space] = observation
        kept[ask.id]?.predicted[space] = ask.predictions[space]
    }
}

// MARK: - Owning

extension GeometryCoordinator {
    /// Finds, in what an owner of `spaces` drew, every view waiting to be
    /// found in one of them, and answers whether a reader among them drew from
    /// a wrong answer — which the owner corrects by drawing its subtree again.
    ///
    /// Inner owners draw first, so the nearest owner of a space answers for a
    /// view and every owner further out finds it answered: a name declared
    /// twice resolves to the nearer declaration, and `.scrollView` to the
    /// innermost scroll view.
    ///
    /// - Parameters:
    ///   - spaces: The spaces this owner answers for.
    ///   - drawn: What it drew, its own origin at `(0, 0)`.
    ///   - size: The space's size, for `GeometryProxy.bounds(of:)`.
    ///   - shift: Where `drawn`'s top-left is in the space — not at its origin
    ///     when the owner drew only a band of a longer content.
    ///   - scrollAxis: For a scroll view, its axis
    ///     (``GeometryObservation/scrollAxis``).
    /// - Returns: Whether a reader must be drawn again.
    func resolve(
        _ spaces: [CoordinateSpace], in drawn: FrameBuffer, size: CellSize,
        shift: CellPoint = CellPoint(x: 0, y: 0), scrollAxis: Axis? = nil
    ) -> Bool {
        guard isWaiting(in: spaces) else { return false }
        var misled = false
        drawn.forEachGeometryMarker(offsetX: shift.x, offsetY: shift.y) { id, x, y in
            guard let ask = asks[id] else { return }
            for space in spaces where ask.found[space] == nil && ask.wanted.contains(space) {
                let observation = GeometryObservation(
                    origin: CellPoint(x: x, y: y), spaceSize: size, scrollAxis: scrollAxis)
                answer(ask, in: space, with: observation)
                if ask.wasMisled(about: space, by: observation) { misled = true }
            }
        }
        return misled
    }

    /// Answers every view in `frame` still waiting, as the scene root: in the
    /// global space for `.global`, and in the global space as well for a name
    /// nothing declared around it — SwiftUI's answer, measured on macOS 15
    /// (an unknown name, `.scrollView` with no scroll view, and
    /// `.scrollView(axis:)` with none along that axis all give the global
    /// frame, and `bounds(of:)` gives `nil`). Then checks what the members of
    /// the matched geometry groups drew from against where they all turned
    /// out to be (``MatchedGeometryRegistry``).
    ///
    /// - Parameters:
    ///   - frame: The screen as drawn, its top-left at `(0, 0)`.
    ///   - size: The screen's size.
    /// - Returns: Whether a reader or a matched member must be drawn again.
    package func resolveRemaining(in frame: FrameBuffer, size: CellSize) -> Bool {
        var misled = false
        if unansweredTotal > 0 {
            frame.forEachGeometryMarker { id, x, y in
                guard let ask = asks[id] else { return }
                for space in ask.wanted where space != .local && ask.found[space] == nil {
                    let observation = GeometryObservation(
                        origin: CellPoint(x: x, y: y), spaceSize: space == .global ? size : nil)
                    answer(ask, in: space, with: observation)
                    if ask.wasMisled(about: space, by: observation) { misled = true }
                }
            }
        }
        if matchedGeometry.resolveWalk(origin: { asks[$0]?.found[.global]?.origin }) { misled = true }
        return misled
    }
}

// MARK: - Ending the Frame

extension GeometryCoordinator {
    /// Calls each reporter that registered this walk, with a proxy answering
    /// what was found; then lets go of what was kept for views that have gone.
    ///
    /// A reporter no owner found is called too, its proxy answering as
    /// though none had — what was found for it last, else the origin: one
    /// whose marker a container dropped (a bare `FrameBuffer(lines:)` that
    /// leaves its content's regions behind, decisions D5G B-D5G-2). Its first
    /// report is the one
    /// `onGeometryChange` always makes, as it made it when it reported from
    /// its render.
    ///
    /// A view that asked last frame and drew nothing this one keeps what was
    /// kept for it while a lazy container still holds it — windowed out, its
    /// state kept — so it is told the same when it comes back; otherwise it
    /// has left the tree, and so does what was kept.
    func endSpacesFrame(isRetained: (ViewIdentity) -> Bool) {
        guard !kept.isEmpty || !asks.isEmpty else { return }
        var reports: [(report: (GeometryProxy) -> Void, proxy: GeometryProxy)] = []
        for id in askOrder {
            guard let report = reporters[id], let ask = asks[id] else { continue }
            reports.append((report, GeometryProxy(width: ask.size.width, height: ask.size.height, ask: ask)))
        }
        if kept.count > asks.count {
            var gone: [HitTestRegion.HandlerID] = []
            for (id, entry) in kept where !entry.askedThisWalk && !isRetained(entry.identity) {
                gone.append(id)
            }
            for id in gone { kept.removeValue(forKey: id) }
        }
        // A space asked late about a view no owner has ever found is kept only
        // until that view's next render, which asks for it.
        if lateAsks.count > kept.count {
            for id in Array(lateAsks.keys) where kept[id] == nil { lateAsks.removeValue(forKey: id) }
        }
        var keepsReaders = false
        for id in kept.keys {
            kept[id]?.askedThisWalk = false
            if kept[id]?.isReader == true { keepsReaders = true }
        }
        self.keepsReaders = keepsReaders
        for (report, proxy) in reports { report(proxy) }
    }
}

// MARK: - Reaching It

extension RenderContext {
    /// An ask for the view rendering in this context, under the id of the
    /// marker it stamps — `nil` in a measure (which asks a size, and must not
    /// claim a marker the render will ask for) and where no coordinator is
    /// wired.
    ///
    /// - Parameter role: What the view does with what it is told.
    package func makeGeometryAsk(role: GeometryAsk.Role) -> GeometryAsk? {
        guard !isMeasuring, let dispatcher = environment.mouseEventDispatcher else { return nil }
        let id = dispatcher.geometryMarkerID(in: self)
        let geometry = dispatcher.geometry
        let ask = GeometryAsk(
            id: id, identity: identity, role: role, coordinator: geometry,
            tracker: environment.volatileReadTracker, origin: geometryOrigin)
        for space in geometry.lateAsks[id] ?? [] { ask.want(space) }
        return ask
    }
}
