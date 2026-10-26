//  🖥️ TUI — A Terminal UI framework for Swift
//  GeometryCoordinator+Visibility.swift
//
//  Scroll visibility (`onScrollVisibilityChange`): the observers a walk
//  registers, what the scroll views measured, and the reports made when the
//  frame ends.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension GeometryCoordinator {
    /// Whether a scroll view drawing now has an observer to measure.
    var hasUnmeasuredVisibilityObservers: Bool { unmeasuredObservers > 0 }

    /// Registers the view whose marker is `id` as watching its visibility.
    ///
    /// Registered again by a view drawn again in the same walk — a subtree a
    /// container renders twice — which replaces the first registration and
    /// whatever was measured for it: the second drawing is the one shown.
    func registerVisibilityObserver(
        id: HitTestRegion.HandlerID, identity: ViewIdentity, size: CellSize, threshold: Double,
        action: @escaping (Bool) -> Void
    ) {
        if let existing = observers[id] {
            if existing.fraction != nil { unmeasuredObservers += 1 }
        } else {
            observerOrder.append(id)
            unmeasuredObservers += 1
        }
        observers[id] = VisibilityObserver(
            identity: identity, size: size, threshold: threshold, action: action)
    }

    /// Measures every observer `drawn` carries that no scroll view nearer to it
    /// has measured, against a viewport of `viewport` in `drawn`'s coordinates.
    ///
    /// Called by a scroll view on what it drew, once its offset is final:
    /// inner scroll views draw first, so the nearest one measures an observer
    /// and every one further out finds it measured.
    ///
    /// - Parameter noting: Whether to answer each fraction measured, by
    ///   marker id — for a memo recording the scroll view, which makes the
    ///   same measures again when it serves it (``applyMeasuredVisibility(_:)``).
    /// - Returns: The fractions measured when `noting`, and nothing otherwise.
    @discardableResult
    func measureVisibility(
        in drawn: FrameBuffer, viewport: CellRect, noting: Bool = false
    ) -> [(HitTestRegion.HandlerID, Double)] {
        var measured: [(HitTestRegion.HandlerID, Double)] = []
        drawn.forEachGeometryMarker { id, x, y in
            guard var observer = observers[id], observer.fraction == nil else { return }
            let fraction = Self.fraction(
                of: CellRect(x: x, y: y, width: observer.size.width, height: observer.size.height),
                shownIn: viewport)
            observer.fraction = fraction
            observers[id] = observer
            unmeasuredObservers -= 1
            if noting { measured.append((id, fraction)) }
        }
        return measured
    }

    /// Makes again the measures a scroll view made when a memo recorded it,
    /// for the observers its served buffer re-registered: the buffer is the
    /// one measured, so the fractions are too.
    func applyMeasuredVisibility(_ measured: [(HitTestRegion.HandlerID, Double)]) {
        for (id, fraction) in measured {
            guard var observer = observers[id], observer.fraction == nil else { continue }
            observer.fraction = fraction
            observers[id] = observer
            unmeasuredObservers -= 1
        }
    }

    /// How much of `rect` `viewport` shows, from 0 to 1. A view with no area
    /// is shown whole or not at all, by whether its origin is inside.
    static func fraction(of rect: CellRect, shownIn viewport: CellRect) -> Double {
        let area = rect.width * rect.height
        guard area > 0 else {
            let inside =
                rect.x >= viewport.x && rect.x < viewport.maxX && rect.y >= viewport.y
                && rect.y < viewport.maxY
            return inside ? 1 : 0
        }
        let width = max(0, min(rect.maxX, viewport.maxX) - max(rect.x, viewport.x))
        let height = max(0, min(rect.maxY, viewport.maxY) - max(rect.y, viewport.y))
        return Double(width * height) / Double(area)
    }

    /// Reports what this frame changed, once the frame is drawn.
    ///
    /// An observer reports when it first appears — shown or not — and then
    /// each time its fraction crosses its threshold (a fraction AT the
    /// threshold counts as shown, as SwiftUI's does). One no scroll view
    /// measured is reported shown: SwiftUI reports a view in no scroll view
    /// visible wherever it is (measured, macOS 15).
    ///
    /// An observer that drew last frame and not this one has either left the
    /// window of a lazy container — still in the tree, its state kept, and
    /// certainly not on screen — or left the tree. The first is reported hidden
    /// if it was shown; the second is not reported at all, as SwiftUI reports
    /// nothing for a removed view (measured).
    ///
    /// A registration whose marker no scroll view measured and the finished
    /// frame does not carry was not drawn — its buffer was thrown away — and
    /// counts as no registration at all.
    func endVisibilityFrame(frame: FrameBuffer, isRetained: (ViewIdentity) -> Bool) {
        guard !observers.isEmpty || !reported.isEmpty else { return }
        if unmeasuredObservers > 0 {
            frame.forEachGeometryMarker { id, _, _ in observers[id]?.reachedFrame = true }
        }
        var reports: [(action: (Bool) -> Void, isVisible: Bool)] = []
        var drawn: Set<HitTestRegion.HandlerID> = []
        for id in observerOrder {
            guard let observer = observers[id], observer.fraction != nil || observer.reachedFrame else {
                continue
            }
            drawn.insert(id)
            let isVisible = observer.fraction.map { $0 >= observer.threshold } ?? true
            let previous = reported[id]?.isVisible
            reported[id] = Reported(
                identity: observer.identity, isVisible: isVisible, action: observer.action)
            if previous != isVisible { reports.append((observer.action, isVisible)) }
        }
        if reported.count > drawn.count {
            var removed: [HitTestRegion.HandlerID] = []
            for (id, last) in reported where !drawn.contains(id) {
                guard isRetained(last.identity) else {
                    removed.append(id)
                    continue
                }
                if last.isVisible {
                    reported[id]?.isVisible = false
                    reports.append((last.action, false))
                }
            }
            for id in removed { reported.removeValue(forKey: id) }
        }
        // After the books are settled: an action may write state, and nothing
        // here should be half-updated when it does.
        for report in reports { report.action(report.isVisible) }
    }
}

extension RenderContext {
    /// Measures the scroll visibility observers in `drawn` against `viewport`,
    /// for a scroll container whose offset is final — a `ScrollView`, a `List`.
    ///
    /// One environment read and a count when no observer is waiting, which is
    /// every frame of an app that has none.
    ///
    /// The measures are a REPLAYABLE effect, as the observers' registrations
    /// are (``ScrollVisibilityRegistrar``): a memo that serves this scroll
    /// view's buffer replays the registrations, and without the measures each
    /// observer would come back unmeasured — reported shown, since its marker
    /// is in the frame, however far off screen it is.
    @MainActor
    package func measureScrollVisibility(in drawn: FrameBuffer, viewport: CellRect) {
        guard !isMeasuring, let geometry = geometryCoordinator,
            geometry.hasUnmeasuredVisibilityObservers
        else { return }
        guard let journal = recordingEffectJournal else {
            geometry.measureVisibility(in: drawn, viewport: viewport)
            return
        }
        let measured = geometry.measureVisibility(in: drawn, viewport: viewport, noting: true)
        guard !measured.isEmpty else { return }
        journal.append(
            EffectJournal.Entry(
                kind: ScrollVisibilityRegistrar.measuredKind, channelToken: environment.keyChannelToken
            ) { replay in
                replay.geometryCoordinator?.applyMeasuredVisibility(measured)
            })
    }
}
