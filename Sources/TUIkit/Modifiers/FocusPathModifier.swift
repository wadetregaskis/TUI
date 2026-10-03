//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusPathModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Stage

/// When a handler on the focus path is asked, relative to the focused control.
///
/// SwiftUI asks two kinds of handler along the path from the focused view to
/// the root, at two different moments — measured on macOS 15.
enum FocusPathStage: Sendable {
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
struct FocusPathModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// When the handler is asked.
    let stage: FocusPathStage

    /// Makes the handler for a render, from that render's context — for the
    /// handlers whose keys depend on the environment, such as a command chord
    /// resolved through ``EnvironmentValues/commandKey``. The handler does its
    /// own matching of keys, characters and phases, and answers whether it
    /// took the key.
    let bind: @MainActor (RenderContext) -> (KeyEvent) -> Bool

    var body: Never {
        fatalError("FocusPathModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension FocusPathModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A render-pass side effect, under the same two rules as
        // `KeyEventModifier`'s: never while measuring (a render-to-measure
        // ancestor would register twice), and always declared to a
        // value-memoizing ancestor as replayable.
        //
        // A disabled view takes no key presses: SwiftUI never focuses one, and
        // TUIkit's controls do not register for focus inside `.disabled(true)`,
        // so the focus can never be inside it. Not registering at all says the
        // same thing without leaving it to the focus ring.
        guard !context.isMeasuring, context.environment.isEnabled else {
            return TUIkit.renderToBuffer(content, context: context)
        }
        context.environment.volatileReadTracker?.recordReplayableEffect()

        let sectionID = context.environment.activeFocusSectionID
        // The modifier's own identity: the content renders at it, and every
        // control inside renders at it or below it.
        let scope = context.identity
        let handler = bind(context)
        FocusPathRegistrar.register(
            scope: scope, stage: stage, handler: handler, sectionID: sectionID, context: context)
        if let journal = context.recordingEffectJournal {
            // The scope and section are captured, not looked up: the replay
            // context is the memo root's, whose identity is not this view's.
            journal.append(
                EffectJournal.Entry(
                    kind: FocusPathRegistrar.kind, channelToken: context.environment.keyChannelToken
                ) { [stage, handler] replay in
                    FocusPathRegistrar.register(
                        scope: scope, stage: stage, handler: handler, sectionID: sectionID, context: replay)
                })
        }

        return TUIkit.renderToBuffer(content, context: context)
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
        scope: ViewIdentity, stage: FocusPathStage, handler: @escaping (KeyEvent) -> Bool,
        sectionID: String?, context: RenderContext
    ) {
        context.environment.keyEventDispatcher?.addFocusPathHandler(
            scope: scope, stage: stage, sectionID: sectionID, handler)
    }
}

// MARK: - Layoutable

extension FocusPathModifier: Layoutable {
    /// Behaviour-only decorator — it renders `content` unchanged, so it
    /// measures as its content does.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
extension FocusPathModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension FocusPathModifier: DrawsContentUnchanged {}
