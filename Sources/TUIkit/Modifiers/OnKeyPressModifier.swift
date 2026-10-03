//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnKeyPressModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The modifier behind SwiftUI's `onKeyPress` family: registers a handler that
/// hears a press only while the focus is on this view or inside it.
///
/// The focus-blind TUI handler is ``KeyEventModifier``; the two share the
/// dispatcher and its per-frame lifecycle, and differ in what a registration
/// is scoped to and when it is asked (see `InputHandler`).
struct OnKeyPressModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The action, with its own matching of keys, characters and phases.
    let handler: (KeyPress) -> KeyPress.Result

    var body: Never {
        fatalError("OnKeyPressModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension OnKeyPressModifier: Renderable {
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
        OnKeyPressRegistrar.register(scope: scope, handler: handler, sectionID: sectionID, context: context)
        if let journal = context.recordingEffectJournal {
            // The scope and section are captured, not looked up: the replay
            // context is the memo root's, whose identity is not this view's.
            journal.append(
                EffectJournal.Entry(
                    kind: OnKeyPressRegistrar.kind, channelToken: context.environment.keyChannelToken
                ) { [handler] replay in
                    OnKeyPressRegistrar.register(scope: scope, handler: handler, sectionID: sectionID, context: replay)
                })
        }

        return TUIkit.renderToBuffer(content, context: context)
    }
}

// MARK: - Registration

/// The one registration `onKeyPress` makes, shared by the live render and by a
/// value memo replaying it — see `EffectJournal`.
enum OnKeyPressRegistrar {
    /// The journal kind of an `onKeyPress` registration.
    static let kind = EffectJournal.Kind("onKeyPress")

    /// Adds `handler` for the subtree at `scope` to `context`'s key dispatcher.
    @MainActor
    static func register(
        scope: ViewIdentity, handler: @escaping (KeyPress) -> KeyPress.Result, sectionID: String?,
        context: RenderContext
    ) {
        context.environment.keyEventDispatcher?.addFocusPathHandler(
            scope: scope, sectionID: sectionID, handler)
    }
}

// MARK: - Layoutable

extension OnKeyPressModifier: Layoutable {
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
extension OnKeyPressModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension OnKeyPressModifier: DrawsContentUnchanged {}
