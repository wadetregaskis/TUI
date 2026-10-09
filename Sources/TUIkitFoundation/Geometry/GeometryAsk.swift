//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryAsk.swift
//
//  One view's questions about where it is, as its `GeometryProxy` asks them,
//  and what the coordinate spaces' owners answered.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Observation

/// Where an owner found a view, in the owner's space.
package struct GeometryObservation: Equatable, Sendable {
    /// The view's top-left cell in the space — or, where no view owning the
    /// space encloses the asking one (an unknown name, `.scrollView` with no
    /// scroll view), in the global space: SwiftUI's answer, measured.
    package var origin: CellPoint

    /// The space's own size, or `nil` where no owner enclosed the view —
    /// which is when `GeometryProxy.bounds(of:)` answers `nil`.
    package var spaceSize: CellSize?

    /// For a scroll view's space, the axis it scrolls along — `.vertical`
    /// when it scrolls both ways — which a scroll transition naming no axis
    /// follows; `nil` for any other owner's.
    package var scrollAxis: Axis?
}

// MARK: - Ask

/// One view's questions about where it is, for one walk of the tree: what its
/// ``GeometryProxy`` answers through.
///
/// Made where a view hands out a proxy that can be asked about another space
/// — a `GeometryReader`, `onGeometryChange`, a gesture located in a named
/// space — with the id of the geometry marker the view stamps. While the view
/// renders it RECORDS: each space asked is noted with what it was answered,
/// and those answers are what the space's owner checks the marker against
/// (``GeometryCoordinator``). Asked after its render — from an action, a
/// gesture, the end of the frame — it answers from what the owners found.
///
/// ## What a reader is told
///
/// A reader (``Role/reader``) whose context carries an origin
/// (`RenderContext.geometryOriginX`) is told a PREDICTION: its carried origin
/// less the space owner's, plus its residual — what the owner found last
/// frame less what was predicted then (design study A2, G4). The containers
/// that place a child before rendering it move the carried origin, so motion
/// they cause is in the prediction; an offset one of the others adds is
/// usually the same from frame to frame, and the residual carries it. A
/// reader with no carried origin, or none last frame, is told what its owner
/// found last frame (G1). Either way the owner checks the answer against the
/// marker, so a wrong prediction costs a correction, never a wrong drawing.
///
/// A reference, because the proxy is a value that can be copied into a
/// closure and asked later; the answer it gives then is the latest found.
/// `@unchecked Sendable` on the coordinator's terms: render path and
/// frame-end only, both on the main actor.
package final class GeometryAsk: @unchecked Sendable {
    /// What the asking view does with the answers — which decides whether a
    /// wrong one is corrected.
    package enum Role: Equatable {
        /// A view whose CONTENT is built from the answers: a `GeometryReader`,
        /// a visual effect. An answer that turns out wrong was drawn, so the
        /// space's owner draws its subtree again with the right one.
        case reader
        /// A view that only reports what it is told, once the frame is done
        /// (`onGeometryChange`). Never corrected: it is asked again at the end.
        case reporter
        /// A pointer handler converting locations into a named space at event
        /// time: answered from the frame before the event. Never corrected.
        case pointer
    }

    /// The id of the marker the asking view stamps.
    package let id: HitTestRegion.HandlerID

    /// The asking view, for keeping what was found across frames.
    let identity: ViewIdentity

    let role: Role

    private(set) weak var coordinator: GeometryCoordinator?

    /// The innermost preference layer being built where this view renders,
    /// whose base's anchors it resolves against — see
    /// `GeometryProxy.subscript(_:)`.
    let anchorScope: AnchorLayerScope?

    /// The view's carried origin (`RenderContext.geometryOriginX`), or `nil`
    /// where none was carried — and for any role but ``Role/reader``, which
    /// alone is told a prediction.
    private let origin: CellPoint?

    /// The innermost owner of a space around the view as it renders, whose
    /// origins the view's is measured against (``GeometryOwnerScope``).
    private let owners: GeometryOwnerScope?

    /// Where a reader declares that what it draws depends on something no
    /// memo keys on — see ``observation(in:)``.
    private let tracker: VolatileReadTracker?

    /// Whether the view is rendering, and so whether what it asks is recorded.
    private(set) var isRecording: Bool

    /// What the view was told about one space while recording, and how much
    /// of it it used.
    struct Told {
        /// The answer: `nil` for a space asked before any owner had found the
        /// view and with nothing to predict it from.
        let observation: GeometryObservation?
        /// Whether the view asked the space's size (`bounds(of:)`) as well as
        /// where it is in it — so a wrong size misled it too.
        var usedSize: Bool
    }

    /// What each space was answered with while recording.
    private(set) var told: [CoordinateSpace: Told] = [:]

    /// The prediction made for each space while recording — what the space's
    /// owner keeps beside what it finds, so the next frame's answer can add
    /// the difference (the residual) to its own prediction.
    private(set) var predictions: [CoordinateSpace: CellPoint] = [:]

    /// The spaces to find this view in: those it was told about, and those it
    /// asked after an earlier render (``GeometryCoordinator/noteLateAsk(id:space:)``).
    private(set) var wanted: [CoordinateSpace] = []

    /// What this walk's owners found, by space.
    var found: [CoordinateSpace: GeometryObservation] = [:]

    /// The view's size as drawn.
    var size = CellSize(width: 0, height: 0)

    init(
        id: HitTestRegion.HandlerID, identity: ViewIdentity, role: Role, coordinator: GeometryCoordinator,
        tracker: VolatileReadTracker?, origin: (x: Int, y: Int)? = nil
    ) {
        self.id = id
        self.identity = identity
        self.role = role
        self.coordinator = coordinator
        self.tracker = tracker
        self.anchorScope = coordinator.anchorScope
        self.owners = coordinator.ownerScope
        self.origin = role == .reader ? origin.map { CellPoint(x: $0.x, y: $0.y) } : nil
        self.isRecording = true
    }

    /// Where the view is in `space`, as far as is known: what this walk's
    /// owner found; else, while recording, the prediction and residual (see
    /// the type's discussion); else what an owner found last frame; else
    /// nothing.
    ///
    /// While recording, the first answer for each space is noted — what an
    /// owner will hold the view to — and a reader's first question beyond its
    /// own space declares an unkeyed read: what it draws now follows where it
    /// is, which no memo above it keys on, so none may store it (decisions A2,
    /// the owner's answer 4; the precedent is a preference writer's).
    ///
    /// - Parameters:
    ///   - space: The space asked about.
    ///   - needsSize: Whether the asker uses the space's size as well
    ///     (`GeometryProxy.bounds(of:)`), so a wrong size misleads it too.
    package func observation(in space: CoordinateSpace, needsSize: Bool = false) -> GeometryObservation? {
        if let found = found[space] {
            if isRecording { note(found, in: space, needsSize: needsSize) }
            return found
        }
        guard isRecording else {
            coordinator?.noteLateAsk(id: id, space: space)
            return coordinator?.keptObservation(for: id, in: space)
        }
        if let known = told[space] {
            if needsSize { told[space]?.usedSize = true }
            return known.observation
        }
        let answer = predictedAnswer(in: space) ?? coordinator?.keptObservation(for: id, in: space)
        note(answer, in: space, needsSize: needsSize)
        return answer
    }

    /// Notes what the view was told about `space` the first time it asked.
    private func note(_ answer: GeometryObservation?, in space: CoordinateSpace, needsSize: Bool) {
        if let known = told[space] {
            if needsSize, !known.usedSize { told[space]?.usedSize = true }
            return
        }
        if told.isEmpty, role == .reader { tracker?.recordUnkeyedRead() }
        told[space] = Told(observation: answer, usedSize: needsSize)
        wanted.append(space)
    }

    /// Where the view is predicted to be in `space`, corrected by last frame's
    /// residual — `nil` when there is no prediction to make (no carried
    /// origin), and last frame's answer as it stands when last frame made
    /// none to take a residual from.
    private func predictedAnswer(in space: CoordinateSpace) -> GeometryObservation? {
        guard let origin, space != .local else { return nil }
        // The owner of the space is the nearest scope around the view that
        // declares it; past them all, the scene root, which answers `.global`
        // and every name nothing declared at the frame of reference's origin —
        // if the root started it (`GeometryOwnerScope.startsReference`).
        var ownerOrigin = CellPoint(x: 0, y: 0)
        var ownerSize: CellSize?
        var ownerAxis: Axis?
        var scope = owners
        while let owner = scope {
            if owner.spaces.contains(space) {
                ownerOrigin = owner.origin
                ownerSize = owner.size
                ownerAxis = owner.scrollAxis
                break
            }
            if owner.startsReference { return nil }
            scope = owner.parent
        }
        let predicted = CellPoint(x: origin.x - ownerOrigin.x, y: origin.y - ownerOrigin.y)
        predictions[space] = predicted
        guard let kept = coordinator?.keptEntry(for: id, in: space) else {
            return GeometryObservation(origin: predicted, spaceSize: ownerSize, scrollAxis: ownerAxis)
        }
        guard let then = kept.predicted else { return kept.observation }
        return GeometryObservation(
            origin: CellPoint(
                x: predicted.x + kept.observation.origin.x - then.x,
                y: predicted.y + kept.observation.origin.y - then.y),
            spaceSize: kept.observation.spaceSize, scrollAxis: kept.observation.scrollAxis)
    }

    /// Moves the predictions for the spaces no owner has found the view in
    /// yet by `delta` — the view was drawn somewhere its owner then moved
    /// (``GeometryCoordinator/movePredictions(in:by:)``). What it was TOLD is
    /// left as it was: that is what it drew.
    func movePredictions(by delta: CellPoint) {
        for (space, predicted) in predictions where found[space] == nil {
            predictions[space] = CellPoint(x: predicted.x + delta.x, y: predicted.y + delta.y)
        }
    }

    /// What the view was told while recording, in the order it asked.
    var toldAnswers: [GeometryObservation?] {
        wanted.compactMap { space in told[space].map(\.observation) }
    }

    /// Adds a space to find the view in without telling it anything — one it
    /// asked after an earlier render, or a pointer's.
    func want(_ space: CoordinateSpace) {
        guard !wanted.contains(space) else { return }
        wanted.append(space)
    }

    /// Ends recording: the view has rendered.
    package func finishRecording(size: CellSize) {
        isRecording = false
        self.size = size
    }

    /// Whether what this view was told about `space` is not what was found —
    /// a reader drew something wrong. A space it was never told about cannot
    /// be wrong, and nor can a size it never asked.
    func wasMisled(about space: CoordinateSpace, by observation: GeometryObservation) -> Bool {
        guard role == .reader, let answer = told[space] else { return false }
        guard let given = answer.observation else { return true }
        return given.origin != observation.origin || (answer.usedSize && given.spaceSize != observation.spaceSize)
    }
}
