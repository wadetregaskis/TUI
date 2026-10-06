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
struct GeometryObservation: Equatable, Sendable {
    /// The view's top-left cell in the space — or, where no view owning the
    /// space encloses the asking one (an unknown name, `.scrollView` with no
    /// scroll view), in the global space: SwiftUI's answer, measured.
    var origin: CellPoint

    /// The space's own size, or `nil` where no owner enclosed the view —
    /// which is when `GeometryProxy.bounds(of:)` answers `nil`.
    var spaceSize: CellSize?
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
/// A reference, because the proxy is a value that can be copied into a
/// closure and asked later; the answer it gives then is the latest found.
/// `@unchecked Sendable` on the coordinator's terms: render path and
/// frame-end only, both on the main actor.
final class GeometryAsk: @unchecked Sendable {
    /// What the asking view does with the answers — which decides whether a
    /// wrong one is corrected.
    enum Role: Equatable {
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
    let id: HitTestRegion.HandlerID

    /// The asking view, for keeping what was found across frames.
    let identity: ViewIdentity

    let role: Role

    private(set) weak var coordinator: GeometryCoordinator?

    /// The innermost preference layer being built where this view renders,
    /// whose base's anchors it resolves against — see
    /// `GeometryProxy.subscript(_:)`.
    let anchorScope: AnchorLayerScope?

    /// Where a reader declares that what it draws depends on something no
    /// memo keys on — see ``observation(in:)``.
    private let tracker: VolatileReadTracker?

    /// Whether the view is rendering, and so whether what it asks is recorded.
    private(set) var isRecording: Bool

    /// What each space was answered with while recording: `nil` for a space
    /// asked before any owner had found the view.
    private(set) var told: [CoordinateSpace: GeometryObservation?] = [:]

    /// The spaces to find this view in: those it was told about, and those it
    /// asked after an earlier render (``GeometryCoordinator/noteLateAsk(id:space:)``).
    private(set) var wanted: [CoordinateSpace] = []

    /// What this walk's owners found, by space.
    var found: [CoordinateSpace: GeometryObservation] = [:]

    /// The view's size as drawn.
    var size = CellSize(width: 0, height: 0)

    init(
        id: HitTestRegion.HandlerID, identity: ViewIdentity, role: Role, coordinator: GeometryCoordinator,
        tracker: VolatileReadTracker?
    ) {
        self.id = id
        self.identity = identity
        self.role = role
        self.coordinator = coordinator
        self.tracker = tracker
        self.anchorScope = coordinator.anchorScope
        self.isRecording = true
    }

    /// Where the view is in `space`, as far as is known: what this walk's
    /// owner found, else what an owner found last frame, else nothing.
    ///
    /// While recording, the first answer for each space is noted — what an
    /// owner will hold the view to — and a reader's first question beyond its
    /// own space declares an unkeyed read: what it draws now follows where it
    /// is, which no memo above it keys on, so none may store it (decisions A2,
    /// the owner's answer 4; the precedent is a preference writer's).
    func observation(in space: CoordinateSpace) -> GeometryObservation? {
        let known = found[space] ?? coordinator?.keptObservation(for: id, in: space) ?? firstGuess(in: space)
        guard isRecording else {
            if found[space] == nil { coordinator?.noteLateAsk(id: id, space: space) }
            return known
        }
        if told.index(forKey: space) == nil {
            if told.isEmpty, role == .reader { tracker?.recordUnkeyedRead() }
            told.updateValue(known, forKey: space)
            wanted.append(space)
        }
        return known
    }

    /// What the view was told while recording, in the order it asked.
    var toldAnswers: [GeometryObservation?] {
        wanted.compactMap { space in told.index(forKey: space).map { told.values[$0] } }
    }

    /// What to tell the view about `space` before any owner has found it: the
    /// origin of a preference layer it is being built in
    /// (``AnchorLayerScope/firstGuess``), else nothing.
    private func firstGuess(in space: CoordinateSpace) -> GeometryObservation? {
        var scope = anchorScope
        while let layer = scope {
            if layer.space == space { return layer.firstGuess }
            scope = layer.parent
        }
        return nil
    }

    /// Adds a space to find the view in without telling it anything — one it
    /// asked after an earlier render, or a pointer's.
    func want(_ space: CoordinateSpace) {
        guard !wanted.contains(space) else { return }
        wanted.append(space)
    }

    /// Ends recording: the view has rendered.
    func finishRecording(size: CellSize) {
        isRecording = false
        self.size = size
    }

    /// Whether what this view was told about `space` is not what was found —
    /// a reader drew something wrong. A space it was never told about cannot
    /// be wrong.
    func wasMisled(about space: CoordinateSpace, by observation: GeometryObservation) -> Bool {
        guard role == .reader, let answer = told[space] else { return false }
        return answer != observation
    }
}
