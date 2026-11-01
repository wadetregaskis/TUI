//  🖥️ TUI — A Terminal UI framework for Swift
//  OnGeometryChangeModifier.swift
//
//  Reports something derived from a view's own geometry, whenever it changes.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension View {
    /// Calls `action` with a value derived from this view's geometry, whenever
    /// that value changes.
    ///
    /// The difference from ``GeometryReader`` is which view's geometry you get,
    /// and it is the whole point. A reader is GREEDY — it fills what it was
    /// offered, because it has to know its size before it can build the content
    /// that would otherwise determine it — so wrapping something in one to
    /// measure it changes the layout you were trying to measure. This measures
    /// the view as it actually laid out and leaves it exactly where it was.
    ///
    /// ```swift
    /// Text(article.body)
    ///     .onGeometryChange(for: Int.self) { $0.size.height } { rows in
    ///         visibleRows = rows
    ///     }
    /// ```
    ///
    /// The action fires on the first render as well as on changes — a report
    /// that only ever arrived on the second size would leave an app that never
    /// resizes knowing nothing. It runs on the render pass only, so a measure
    /// (of which there are several per frame) cannot fire it.
    ///
    /// A `transform` that asks only the view's size or `.local` frame runs as
    /// the view renders. One that asks another space — `.global`, a name
    /// declared with ``View/coordinateSpace(_:)``, `.scrollView` — is run again
    /// once the frame is done, against where that space's owner found the
    /// view, and the action fires then: the view's position is only known once
    /// its ancestors have placed it (decisions A2, the owner's answer 7). A
    /// view no owner can find — inside a `Table` cell, which composes its
    /// cells as text — is answered with where it was last found, or the
    /// origin, and still fires.
    ///
    /// - Parameters:
    ///   - type: The type of the derived value, stated so the closure's return
    ///     type is unambiguous — SwiftUI's spelling.
    ///   - transform: Derives the value from the view's geometry.
    ///   - action: Receives the new value.
    /// - Returns: A view that reports its geometry.
    nonisolated public func onGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (T) -> Void
    ) -> some View {
        OnGeometryChangeModifier(content: self, transform: transform) { _, new in action(new) }
    }

    /// Calls `action` with the old and the new value whenever a value derived
    /// from this view's geometry changes.
    ///
    /// The two-argument form of ``onGeometryChange(for:of:action:)``. On the
    /// first render the old and new values are the same, as `onChange`'s
    /// `initial` does.
    ///
    /// - Parameters:
    ///   - type: The type of the derived value.
    ///   - transform: Derives the value from the view's geometry.
    ///   - action: Receives the previous and the new value.
    /// - Returns: A view that reports its geometry.
    nonisolated public func onGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (T, T) -> Void
    ) -> some View {
        OnGeometryChangeModifier(content: self, transform: transform, action: action)
    }
}

// MARK: - Modifier

/// Renders `content` unchanged and reports a value derived from the size it
/// came out at.
nonisolated struct OnGeometryChangeModifier<Content: View, T: Equatable>: View {
    let content: Content
    let transform: (GeometryProxy) -> T
    let action: (T, T) -> Void

    @MainActor var body: Never {
        fatalError("OnGeometryChangeModifier renders via Renderable")
    }
}

@MainActor extension OnGeometryChangeModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A measure pass must not fire the action — there are several per frame
        // and they are asking a question, not laying anything out. Same rule
        // (and the same reason) as `OnChangeModifier`.
        guard !context.isMeasuring, let storage = context.stateStorage else {
            return TUIView.renderToBuffer(content, context: context)
        }

        // Declared as a render side effect for the reason `onChange` declares
        // one: the comparison is per-frame work a cached buffer cannot
        // reproduce, so a value-memoized subtree containing this would compare
        // once and then never notice another change.
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        // Allocated, not fixed: the tracked-value dictionary is shared with
        // onChange and onPreferenceChange at this same identity, and they claim
        // indices from the per-identity counter. A fixed 0 here landed on the
        // first sibling's slot; the per-frame overwrite read back as "no
        // previous value" on their side, so a real change fired nothing.
        //
        // Claimed BEFORE the content renders, not after: an index claimed after
        // is the count of claimants the CONTENT contributed at this same
        // identity, and an `if` without `else` (or an `AnyView`) changes that
        // between frames — both render at the parent identity. The observer
        // then moved onto a vanished sibling's slot and read its value as its
        // own previous geometry. Claiming first makes the index depend only on
        // the chain above, which is body order and the same every frame.
        let key = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: storage.nextOnChangeIndex(for: context.identity))
        // Claimed before the content renders too, for the same reason: the
        // marker's slot is an ordinal at this identity.
        let ask = context.makeGeometryAsk(role: .reporter)

        var buffer = TUIView.renderToBuffer(content, context: context)
        // Manual tracked values are pruned unless the identity is marked — see
        // the same call in `OnChangeModifier`.
        storage.markActive(context.identity)
        // The view's OWN size — what its content actually came out at, not what
        // was offered. That is the whole difference from `GeometryReader`.
        let value = transform(GeometryProxy(width: buffer.width, height: buffer.height, ask: ask))

        // A transform that asked about another space is asked again once the
        // frame is done, with where that space's owner found the view.
        if let ask {
            ask.finishRecording(size: buffer.cellSize)
            if !ask.wanted.isEmpty, let geometry = context.geometryCoordinator {
                let (transform, action) = (self.transform, self.action)
                geometry.registerReporter(ask) { proxy in
                    Self.report(transform(proxy), at: key, in: storage, action: action)
                }
                buffer.hitTestRegions.append(.geometryMarker(ask.id))
                return buffer
            }
        }
        Self.report(value, at: key, in: storage, action: action)
        return buffer
    }

    /// Calls `action` when `value` differs from the one last reported at
    /// `key` — and on the first report, with the same value as old and new.
    ///
    /// The call waits for the walk to be done, and the report is put back if
    /// the drawing it was made in is discarded (`EffectStage`): what the kept
    /// drawing's view came out at is what the action hears.
    ///
    /// SwiftUI's cut-off: a value that goes back, within one frame, to the one
    /// reported before the last — `A → B → A`, an action whose write moves
    /// the view back to where it was — is refused, with SwiftUI's warning,
    /// and taken as seen, so the action is not called for it this frame or
    /// the next (measured, `Tools/SwiftUIProbes/Effect and update ordering/geofeedback.out`).
    /// There is no count: a value that keeps changing is reported each walk.
    private static func report(
        _ value: T, at key: StateStorage.StateKey, in storage: StateStorage, action: @escaping (T, T) -> Void
    ) {
        let previous: GeometryReport<T>? = storage.trackedValue(for: key)
        guard previous?.value != value else { return }
        let pass = storage.currentPass
        if let previous, previous.pass == pass, previous.prior == value {
            storage.setChangedTrackedValue(GeometryReport(value: value, prior: previous.value, pass: pass), for: key)
            SoftTrap.warn("Geometry action is cycling between duplicate values.")
            return
        }
        storage.setChangedTrackedValue(GeometryReport(value: value, prior: previous?.value, pass: pass), for: key)
        storage.effectStage.perform(as: .geometry) { action(previous?.value ?? value, value) }
    }
}

/// What an `onGeometryChange` last reported at a key, and what it changed from in the frame
/// it was reported in — the two values SwiftUI's cut-off compares.
private struct GeometryReport<T> {
    /// The value last reported.
    let value: T
    /// The value before it, for a report made in ``pass``: the one before
    /// last, which a report going back to is a cycle.
    let prior: T?
    /// The render pass (the frame) the report was made in.
    let pass: UInt32
}

@MainActor extension OnGeometryChangeModifier: Layoutable {
    /// Measures as its content: reporting is the whole of this modifier's
    /// effect, and it contributes no geometry.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
@MainActor extension OnGeometryChangeModifier: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension OnGeometryChangeModifier: DrawsContentUnchanged {}

// MARK: - In a Form

/// A geometry action written on a form row watches the row the form lays out,
/// which keeps its place, as SwiftUI's form keeps it (measured, `Tools/SwiftUIProbes/Form rows`).
@MainActor extension OnGeometryChangeModifier: FormRowRewrapping {
    func rewrappingFormRow<V: View>(_ row: V) -> any View {
        OnGeometryChangeModifier<V, T>(content: row, transform: transform, action: action)
    }
}
