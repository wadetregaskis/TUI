//  🖥️ TUI — A Terminal UI framework for Swift
//  OnChangeModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIView

// MARK: - OnChange Modifier

/// A modifier that observes a value and calls an action when it changes.
///
/// Created by the `.onChange(of:initial:_:)` view modifier. Stores the
/// previous value in ``StateStorage`` and compares on each render pass.
///
/// Multiple chained `.onChange(of:)` modifiers on the same view are
/// disambiguated via ``StateStorage/nextOnChangeIndex(for:)``.
nonisolated package struct OnChangeModifier<Content: View, V: Equatable>: View {
    /// The content view to wrap.
    let content: Content

    /// The value to observe for changes.
    let value: V

    /// Whether to fire the action on the first render pass.
    let initial: Bool

    /// The action to call with old and new values when a change is detected.
    let action: (V, V) -> Void

    /// Where the value is tracked when this is one of the copies standing
    /// around the members of content the modifier was written on whole
    /// (``OnceAcrossMembers``); `nil` for the modifier as written, which
    /// claims a slot at its own identity instead.
    var anchor: ViewIdentity?

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and `Scene.onChange(of:initial:_:)` (TUIApp) makes these.
    package init(content: Content, value: V, initial: Bool, action: @escaping (V, V) -> Void) {
        self.content = content
        self.value = value
        self.initial = initial
        self.action = action
    }

    @MainActor package var body: Never {
        fatalError("OnChangeModifier renders via Renderable")
    }
}

// MARK: - Renderable

@MainActor extension OnChangeModifier: Renderable {
    package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Pure passthrough during a measure pass: the comparison, the index
        // claim and the action are render side effects. A measure-pass render
        // (under a render-to-measure ancestor) used to fire the action a
        // second time within the frame AND advance the per-identity index
        // counter, mis-slotting the render pass's tracked values.
        guard !context.isMeasuring else {
            return TUIView.renderToBuffer(content, context: context)
        }
        let storage = context.stateStorage!

        // The comparison below is per-frame work a cached buffer cannot
        // reproduce: a value-memoized row containing this modifier would
        // never compare again after its first frame, so changes went
        // permanently unnoticed. Declare the side effect so the memos
        // decline to cache this subtree.
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        // A copy around one member compares at the anchor every copy shares:
        // the first drawn this pass sees the change, runs the action and
        // tracks the new value, so the rest see none — once for the group.
        // The modifier as written claims a unique slot at its own identity.
        let identity = anchor ?? context.identity
        let index = anchor == nil ? storage.nextOnChangeIndex(for: identity) : OnChangeStateIndex.anchored
        let key = StateStorage.StateKey(identity: identity, propertyIndex: index)
        storage.compareTrackedValue(value, at: key, initial: initial, action: action)

        // Keep tracked values alive through GC
        storage.markActive(identity)

        return TUIView.renderToBuffer(content, context: context)
    }
}

/// StateStorage property indices for ``OnChangeModifier``. A free enum because
/// the modifier is generic (which can't hold static stored properties).
private enum OnChangeStateIndex {
    /// The one value an anchored copy tracks. The anchor is a place of the
    /// modifier's own, one type step below the identity the members were
    /// resolved at (``OnChangeModifier/anchoringEffect(at:)``), which no
    /// composite view's `@State` shares, so slot 0 is free.
    static let anchored = 0
}

// MARK: - The Comparison

extension StateStorage {
    /// Compares `value` with the one tracked under `key` — the last render
    /// pass's — and runs `action` with the two where they differ, or with
    /// `value` twice where none is tracked yet and `initial` says so; then
    /// tracks `value` for the next pass. What `onChange(of:initial:_:)` does
    /// each pass, for a view and for a scene.
    ///
    /// Inside a drawing the walk may still discard, the action is held until
    /// the drawing is kept, and what the comparison replaced is put back if it
    /// is not (``EffectStage``): the drawing a geometry correction makes again
    /// compares against the frame's starting value, not the first drawing's
    /// guess — so a reader's first frame fires nothing, as SwiftUI's does.
    ///
    /// An action run twice already in this frame is refused a third time,
    /// with SwiftUI's warning (``admitsActionRun(at:warning:)``).
    package func compareTrackedValue<V: Equatable>(
        _ value: V, at key: StateKey, initial: Bool, action: @escaping (V, V) -> Void
    ) {
        guard let oldValue: V = trackedValue(for: key) else {
            if initial { performChange(at: key, of: V.self) { action(value, value) } }
            setChangedTrackedValue(value, for: key)
            return
        }
        guard oldValue != value else {
            setTrackedValue(value, for: key)
            return
        }
        performChange(at: key, of: V.self) { action(oldValue, value) }
        setChangedTrackedValue(value, for: key)
    }

    /// Hands `call`, an `onChange(of: V)` action's, to the stage, to run once
    /// the walk is done if the action has not already run twice this frame.
    private func performChange<V>(at key: StateKey, of _: V.Type, _ call: @escaping () -> Void) {
        effectStage.perform(as: .change) { [self] in
            guard admitsActionRun(at: key, warning: { "onChange(of: \(V.self)) action tried to update multiple times per frame." })
            else { return }
            call()
        }
    }

    /// Calls `action`, `preference`'s observer, with `value` — at once, or, in
    /// a drawing, once the walk is done (``EffectStage``) — unless it has
    /// already run twice this frame (``admitsActionRun(at:warning:)``).
    ///
    /// The call is made up here, outside the view's main-actor render, so the
    /// value — a preference's reduction, read from the walk's preference
    /// storage — is captured where the storage it came from is, rather than
    /// sent into a main-actor closure.
    package func perform<V>(
        _ action: @escaping (V) -> Void, with value: V, at key: StateKey, preference: Any.Type
    ) {
        effectStage.perform(as: .preference) { [self] in
            guard admitsActionRun(at: key, warning: { "Bound preference \(preference) tried to update multiple times per frame." })
            else { return }
            action(value)
        }
    }
}

// MARK: - Layoutable

@MainActor extension OnChangeModifier: Layoutable {
    /// Renders `content` unchanged, so it measures as `content`. Forwarding is
    /// also what keeps the change-detection and `action` firing on the render
    /// pass — a measure must not observe values or fire `onChange`.
    package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it, and hands the
/// members of multi-view content on to their container, each in a copy that
/// tracks the value at one place (``OnceAcrossMembers``).
@MainActor extension OnChangeModifier: SingleContentWrapper {
    package var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    package func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

// MARK: - Multi-Member Content

/// `HStack { Group { a; b }.onChange(of: x) { … } }` lays `a` beside `b` and
/// runs the action once a change, as SwiftUI runs a lifecycle effect written
/// on a group once (measured for `.onAppear` and `.task`).
@MainActor extension OnChangeModifier: OnceAcrossMembers {
    package func rewrapping<R: View>(_ view: R) -> any View {
        var copy = OnChangeModifier<R, V>(content: view, value: value, initial: initial, action: action)
        copy.anchor = anchor
        return copy
    }

    /// Anchored one type step below the identity the members were resolved
    /// at — the chained modifier's type nests the one inside it, so two
    /// `.onChange`s on one group keep apart.
    package func anchoringEffect(at context: RenderContext) -> Self {
        var anchored = self
        anchored.anchor = anchor ?? context.identity.child(type: Self.self)
        return anchored
    }
}

/// Body deliberately empty: ``OnceAcrossMembers`` has the whole implementation.
@MainActor extension OnChangeModifier: ChildViewProvider where Content: ChildViewProvider {}
/// Body deliberately empty: ``OnceAcrossMembers`` has the whole implementation.
@MainActor extension OnChangeModifier: GridRowProviding where Content: GridRowProviding {}

/// A change action written on a form row — `Toggle(…).onChange(of: x) { … }`
/// — goes around the row the form lays out, which keeps its place, as
/// SwiftUI's form keeps it (measured, `Tools/SwiftUIProbes/Form rows`).
@MainActor extension OnChangeModifier: FormRowRewrapping {
    package func rewrappingFormRow<R: View>(_ row: R) -> any View {
        OnChangeModifier<R, V>(content: row, value: value, initial: initial, action: action)
    }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension OnChangeModifier: DrawsContentUnchanged {}
