//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyEvent.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Key Event Handler

/// Global key event handler.
///
/// Views can register handlers that are called when keys are pressed.
/// Handlers are processed in reverse order (most recent first).
/// `@usableFromInline`: the type of an `@inlinable` environment accessor (module split step A3).
@usableFromInline
package final class KeyEventDispatcher: @unchecked Sendable {
    /// One registration: the handler and the focus section it rendered in.
    private struct Entry {
        /// The focus section that was active where this handler registered, or
        /// `nil` for a handler outside any section.
        let sectionID: String?
        let handler: (KeyEvent) -> Bool
    }

    /// Registered key handlers, in render (outside-in) order.
    private var handlers: [Entry] = []

    /// One focus-path registration (SwiftUI's `onKeyPress` and its kin): the
    /// handler, the subtree it hears for, when it is asked, and the focus
    /// section it rendered in.
    private struct FocusPathEntry {
        /// The identity of the view the modifier is on: the handler hears a
        /// press only while the focus is on this view or inside it.
        let scope: ViewIdentity
        let stage: FocusPathStage
        let sectionID: String?
        /// Which keys the handler is declared for — an `onKeyPress` on keys —
        /// or `nil` where only running it would say, or it asks for typed
        /// characters rather than keys.
        let declares: ((KeyEvent) -> Bool)?
        let handler: (KeyEvent) -> Bool
    }

    /// The focus-path handlers of every stage, in render (outside-in) order.
    /// See ``dispatchFocusPath(_:focusedIdentity:stage:)``.
    private var focusPathHandlers: [FocusPathEntry] = []

    /// The section that currently owns the keyboard, if any.
    ///
    /// A presented surface — an alert, a modal, a context menu — sets this
    /// while it is up, and only handlers registered inside it run. The focus
    /// system already has this notion (``FocusManager/markSectionModal(id:)``),
    /// and a ROOT-attached presentation also gets it for free by rendering the
    /// page beneath through ``RenderContext/isolatedForBackground()``, which
    /// swaps in a throwaway dispatcher. But a popover attached to a LEAF — a
    /// `.contextMenu` on one `Text` — can only isolate its own subtree; its
    /// siblings still render into this dispatcher every frame and keep their
    /// handlers. `Menu`'s arrow handler is registered unconditionally and
    /// answers `true` to Up/Down, so it swallowed the arrows meant for an open
    /// context menu while Tab (which goes through the focus system, and WAS
    /// captured) worked. Cleared with the handlers each render pass.
    private(set) var grabbingSectionID: String?

    /// The modifier keys held, and the views listening for them. A modifier
    /// key reported on its own is a keyboard event too, and its listeners are
    /// registered per walk as the handlers here are, so they are cleared with
    /// them (``clearHandlers()``).
    let modifierKeys = ModifierKeyMonitor()

    /// Creates a new key event dispatcher.
    package init() {}
}

// MARK: - Internal API

extension KeyEventDispatcher {
    /// Registers a key handler.
    ///
    /// - Parameters:
    ///   - sectionID: The focus section this handler renders in — pass
    ///     `context.environment.activeFocusSectionID`. A handler outside any
    ///     section passes `nil` and is silenced whenever some section holds the
    ///     keyboard.
    ///   - handler: A closure that returns true if the key was handled.
    func addHandler(sectionID: String? = nil, _ handler: @escaping (KeyEvent) -> Bool) {
        handlers.append(Entry(sectionID: sectionID, handler: handler))
    }

    /// Registers a key handler at `position` in the registration order, rather
    /// than after everything registered so far.
    ///
    /// For a container that must render its content before it knows whether to
    /// claim a key, yet must still be asked AFTER that content: read
    /// ``handlerCount`` before the content renders and pass it here. Dispatch
    /// asks the most recent registration first, so a plain
    /// ``addHandler(sectionID:_:)`` at that point is not the container waiting
    /// its turn — it outranks every handler the content just registered.
    /// `NavigationStack`'s Escape-to-pop is the case.
    ///
    /// - Parameters:
    ///   - position: A ``handlerCount`` read earlier this frame. Clamped to the
    ///     handlers present, so a count read before ``clearHandlers()`` cannot
    ///     trap.
    ///   - sectionID: As for ``addHandler(sectionID:_:)``.
    ///   - handler: A closure that returns true if the key was handled.
    func insertHandler(
        at position: Int, sectionID: String? = nil, _ handler: @escaping (KeyEvent) -> Bool
    ) {
        let index = min(max(0, position), handlers.count)
        handlers.insert(Entry(sectionID: sectionID, handler: handler), at: index)
    }

    /// The number of currently-registered handlers. Used by tests to assert
    /// that measure passes register nothing, and as the slot
    /// ``insertHandler(at:sectionID:_:)`` files a handler at.
    var handlerCount: Int { handlers.count }

    /// How far registration has got: what ``rollBack(to:)`` returns to.
    struct Mark {
        fileprivate let handlers: Int
        fileprivate let focusPathHandlers: Int
    }

    /// Where registration has got so far in this walk.
    var mark: Mark {
        Mark(handlers: handlers.count, focusPathHandlers: focusPathHandlers.count)
    }

    /// Drops every handler registered since `mark` was read — what a subtree
    /// drawn a second time in one walk registered the first time
    /// (`RenderWalkCheckpoint`), which would otherwise run twice.
    func rollBack(to mark: Mark) {
        if handlers.count > mark.handlers { handlers.removeLast(handlers.count - mark.handlers) }
        if focusPathHandlers.count > mark.focusPathHandlers {
            focusPathHandlers.removeLast(focusPathHandlers.count - mark.focusPathHandlers)
        }
    }

    /// Declares that `id` owns the keyboard for the rest of this frame — see
    /// ``grabbingSectionID``. Called by a presented surface as it renders.
    func grabInput(sectionID id: String) {
        grabbingSectionID = id
    }

    /// Clears all handlers, and any input grab.
    package func clearHandlers() {
        handlers.removeAll()
        focusPathHandlers.removeAll()
        grabbingSectionID = nil
        modifierKeys.beginSceneRender()
    }

    /// Registers a focus-path handler — SwiftUI's `onKeyPress` and its kin —
    /// which hears a press only while the focus is on the view at `scope` or
    /// inside it.
    ///
    /// - Parameters:
    ///   - scope: The identity of the view the modifier is on.
    ///   - stage: When it is asked; see ``FocusPathStage``.
    ///   - sectionID: As for ``addHandler(sectionID:_:)``: a handler outside
    ///     the section holding the keyboard is silenced.
    ///   - declares: Which keys the handler is declared for, where its
    ///     declaration says (``declaresFocusPathBinding(forAnyOf:focusedIdentity:)``);
    ///     `nil` for one that hears every key.
    ///   - handler: Answers whether it took the key. It does its own matching
    ///     of keys, characters and phases.
    func addFocusPathHandler(
        scope: ViewIdentity, stage: FocusPathStage, sectionID: String?,
        declares: ((KeyEvent) -> Bool)? = nil, _ handler: @escaping (KeyEvent) -> Bool
    ) {
        focusPathHandlers.append(
            FocusPathEntry(scope: scope, stage: stage, sectionID: sectionID, declares: declares, handler: handler))
    }

    /// Whether an `onKeyPress` on the path to the focused view is declared
    /// for one of `events` — on its keys, which can be known without running
    /// the app's action. One that hears every key
    /// (`onKeyPress(phases:action:)`) declares nothing: only running it would
    /// say whether it takes the key. Nor does one on a set of characters
    /// (`onKeyPress(characters:phases:action:)`), which asks for typed text,
    /// not chords, nor one on a key for a Control chord the key does not name
    /// (`KeyEquivalent.namesControlChord`: a digit's for ⌃4). Silenced
    /// handlers, as for a dispatch, do not count.
    ///
    /// For the user's quit key (`InputHandler.quitKeyBindings(byte:hostAliases:)`).
    ///
    /// - Parameters:
    ///   - events: The keys asked about: whether a handler is declared for
    ///     any of them. One walk of the handlers for all of them.
    ///   - focusedIdentity: Where the focused control rendered.
    package func declaresFocusPathBinding(forAnyOf events: [KeyEvent], focusedIdentity: ViewIdentity) -> Bool {
        focusPathHandlers.contains { entry in
            guard entry.stage == .keyPress, let declares = entry.declares,
                grabbingSectionID == nil || entry.sectionID == grabbingSectionID,
                entry.scope == focusedIdentity || entry.scope.isAncestor(of: focusedIdentity)
            else { return false }
            return events.contains(where: declares)
        }
    }

    /// The number of focus-path handlers registered this frame, for tests.
    var focusPathHandlerCount: Int { focusPathHandlers.count }

    /// The scopes of this frame's focus-path handlers, in registration order,
    /// for tests.
    var focusPathScopes: [ViewIdentity] { focusPathHandlers.map(\.scope) }

    /// Offers `event` to the `stage` handlers on the path to the focused view
    /// until one takes it.
    ///
    /// `onKeyPress` handlers are asked OUTERMOST first, SwiftUI's order
    /// measured on macOS 15: a handler on a container that answers `.handled`
    /// keeps the press from a handler on the focused view inside it, and the
    /// outer of two modifiers on one view is asked before the inner. Render
    /// order is that order, because a modifier registers before its content
    /// renders.
    ///
    /// Commands are asked INNERMOST first, the responder chain's order: on
    /// macOS 15 an exit command on the focused view runs and one on its
    /// container does not. So they are asked in reverse.
    ///
    /// - Parameters:
    ///   - event: The key event.
    ///   - focusedIdentity: Where the focused control rendered. A handler hears
    ///     the key when its scope is that identity or an ancestor of it.
    ///   - stage: Which handlers to ask.
    /// - Returns: Whether some handler took the key.
    package func dispatchFocusPath(_ event: KeyEvent, focusedIdentity: ViewIdentity, stage: FocusPathStage) -> Bool {
        switch stage {
        case .keyPress:
            return firstHandling(event, focusedIdentity: focusedIdentity, stage: stage, in: focusPathHandlers)
        case .command:
            return firstHandling(
                event, focusedIdentity: focusedIdentity, stage: stage, in: focusPathHandlers.reversed())
        }
    }

    /// Offers `event` to the `onKeyPress` handlers on the path to the focused
    /// view that are declared for it — those
    /// ``declaresFocusPathBinding(forAnyOf:focusedIdentity:)`` counts —
    /// outermost first, as ``dispatchFocusPath(_:focusedIdentity:stage:)``
    /// asks every one. For a key only a declared binding is offered: a ⌃\\
    /// nothing took, gone round again as the ⌃4, ⌃| or ⌃⇧\\ it may have been
    /// (`InputHandler.dispatchToDeclaredBindings(_:)`).
    ///
    /// - Returns: Whether one of them took it.
    package func dispatchDeclaredFocusPath(_ event: KeyEvent, focusedIdentity: ViewIdentity) -> Bool {
        firstHandling(
            event, focusedIdentity: focusedIdentity, stage: .keyPress,
            in: focusPathHandlers.lazy.filter { $0.declares?(event) == true })
    }

    /// Whether one of `entries` of `stage`, scoped over `focusedIdentity` and
    /// not silenced by an input grab, took `event` — asked in the order given.
    private func firstHandling(
        _ event: KeyEvent, focusedIdentity: ViewIdentity, stage: FocusPathStage,
        in entries: some Sequence<FocusPathEntry>
    ) -> Bool {
        for entry in entries
        where entry.stage == stage && (grabbingSectionID == nil || entry.sectionID == grabbingSectionID) {
            guard entry.scope == focusedIdentity || entry.scope.isAncestor(of: focusedIdentity) else {
                continue
            }
            if entry.handler(event) { return true }
        }
        return false
    }

    /// Dispatches a key event to handlers.
    ///
    /// - Parameter event: The key event to dispatch.
    /// - Returns: True if any handler consumed the event.
    @discardableResult
    package func dispatch(_ event: KeyEvent) -> Bool {
        // Process in reverse order (most recent handlers first) — and, while a
        // surface holds the keyboard, only the handlers registered inside it.
        for entry in handlers.reversed()
        where grabbingSectionID == nil || entry.sectionID == grabbingSectionID {
            if entry.handler(event) { return true }
        }
        return false
    }
}
