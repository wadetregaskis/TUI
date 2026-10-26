//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusPathModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Stage

/// When a handler on the focus path is asked, relative to the focused control.
///
/// SwiftUI asks two kinds of handler along the path from the focused view to
/// the root, at two different moments — measured on macOS 15.
package enum FocusPathStage: Sendable {
    /// `onKeyPress`: before the focused control has the key, outermost first.
    case keyPress

    /// `onMoveCommand`, `onExitCommand` and `onDeleteCommand`: once the
    /// focused control has let the key go, innermost first, and before the
    /// app's keyboard shortcuts — an exit command takes Escape from the cancel
    /// button.
    case command
}

// MARK: - Focus Path Modifier

/// The modifier behind SwiftUI's handlers that hear a key only while the focus
/// is on their view or inside it — `onKeyPress` and its siblings.
///
/// It registers a handler scoped to its own identity; the dispatcher asks it
/// only while the focused control renders at that identity or below it. The
/// focus-blind TUI handler is ``KeyEventModifier``; the two share the
/// dispatcher and its per-frame lifecycle (see `InputHandler`).
package struct FocusPathModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// When the handler is asked.
    let stage: FocusPathStage

    /// Which keys the handler is declared for — an `onKeyPress` on keys —
    /// answered without running the app's action; `nil` for a handler only
    /// running it would answer for, and for one on a set of characters. See
    /// `KeyEventDispatcher.declaresFocusPathBinding(forAnyOf:focusedIdentity:)`.
    var declares: ((KeyEvent) -> Bool)?

    /// Makes the handler for a render, from that render's context — for the
    /// handlers whose keys depend on the environment, such as a command chord
    /// resolved through ``EnvironmentValues/commandKey``. The handler does its
    /// own matching of keys, characters and phases, and answers whether it
    /// took the key.
    let bind: @MainActor (RenderContext) -> (KeyEvent) -> Bool

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUITabs makes these, for a tab view's menu openers.
    package init(
        content: Content,
        stage: FocusPathStage,
        declares: ((KeyEvent) -> Bool)? = nil,
        bind: @escaping @MainActor (RenderContext) -> (KeyEvent) -> Bool
    ) {
        self.content = content
        self.stage = stage
        self.declares = declares
        self.bind = bind
    }

    package var body: Never {
        fatalError("FocusPathModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension FocusPathModifier: Renderable {
    package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A render-pass side effect, under the same two rules as
        // `KeyEventModifier`'s: never while measuring (a render-to-measure
        // ancestor would register twice), and always declared to a
        // value-memoizing ancestor as replayable.
        //
        // A disabled view takes no key presses: SwiftUI never focuses one, and
        // TUI's controls do not register for focus inside `.disabled(true)`,
        // so the focus can never be inside it. Not registering at all says the
        // same thing without leaving it to the focus ring.
        guard !context.isMeasuring, context.environment.isEnabled else {
            return TUIView.renderToBuffer(content, context: context)
        }
        context.environment.volatileReadTracker?.recordReplayableEffect()

        let sectionID = context.environment.activeFocusSectionID
        // The modifier's own identity: the content renders at it, and every
        // control inside renders at it or below it.
        let scope = context.identity
        let handler = bind(context)
        FocusPathRegistrar.register(
            scope: scope, stage: stage, declares: declares, handler: handler, sectionID: sectionID,
            context: context)
        if let journal = context.recordingEffectJournal {
            // The scope and section are captured, not looked up: the replay
            // context is the memo root's, whose identity is not this view's.
            journal.append(
                EffectJournal.Entry(
                    kind: FocusPathRegistrar.kind, channelToken: context.environment.keyChannelToken
                ) { [stage, declares, handler] replay in
                    FocusPathRegistrar.register(
                        scope: scope, stage: stage, declares: declares, handler: handler, sectionID: sectionID,
                        context: replay)
                })
        }

        return TUIView.renderToBuffer(content, context: context)
    }
}

// MARK: - Registration

/// The one registration a focus-path handler makes, shared by the live render
/// and by a value memo replaying it — see `EffectJournal`.
enum FocusPathRegistrar {
    /// The journal kind of a focus-path registration.
    static let kind = EffectJournal.Kind("focusPathKey")

    /// Adds `handler` for the subtree at `scope` to `context`'s key dispatcher.
    @MainActor
    static func register(
        scope: ViewIdentity, stage: FocusPathStage, declares: ((KeyEvent) -> Bool)?,
        handler: @escaping (KeyEvent) -> Bool, sectionID: String?, context: RenderContext
    ) {
        context.environment.keyEventDispatcher?.addFocusPathHandler(
            scope: scope, stage: stage, sectionID: sectionID, declares: declares, handler)
    }
}

// MARK: - Layoutable

extension FocusPathModifier: Layoutable {
    /// Behaviour-only decorator — it renders `content` unchanged, so it
    /// measures as its content does.
    package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
extension FocusPathModifier: SingleContentWrapper {
    package var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    package func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension FocusPathModifier: DrawsContentUnchanged {}

// MARK: - In a Form

/// A key press handler or a command written on a form row — `Picker(…)
/// .onKeyPress(.space) { … }` — goes around the row the form lays out, which
/// keeps its place, as SwiftUI's form keeps it (measured, `Tools/SwiftUIProbes/Form rows`). Every
/// control in the row renders below it, so it is on their focus path still.
extension FocusPathModifier: FormRowRewrapping {
    package func rewrappingFormRow<V: View>(_ row: V) -> any View {
        FocusPathModifier<V>(content: row, stage: stage, declares: declares, bind: bind)
    }
}
