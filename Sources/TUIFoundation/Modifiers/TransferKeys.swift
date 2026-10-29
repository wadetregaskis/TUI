//  🖥️ TUI — A Terminal UI framework for Swift
//  TransferKeys.swift
//
//  The keyboard's way to what a drag carries: Copy on a focused `.draggable`
//  takes its payload, and Paste on a focused drop destination drops what was
//  copied there — a drag's two ends, each reached by Tab.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// The Copy and Paste a `.draggable` and a drop destination answer, while the
/// focus is on them (owner, 2026-10-26: the prerequisite of A53's carry mode,
/// so no drag is mouse-only).
///
/// **Which stop.** A modifier whose content registers focus stops of its own —
/// `Button(…).draggable(x)` — answers on those, so Tab does not cross the
/// control twice; content that registers none gets one stop of the
/// modifier's, which publishes `\.isFocused` to it as `.focusable()` does, the
/// content drawing the focus as it chooses. Nothing in a list row, which the
/// list reaches; nothing while disabled.
///
/// **The keys.** Copy and Paste are the app's (⌘C and ⌘V through
/// ``EnvironmentValues/commandKey``), as `copyable(_:)` and
/// `pasteDestination(for:action:validator:)` use; a terminal's own paste
/// reaches a destination too. A copy keeps the value (``TypedClipboard``), so a
/// paste in this app gets it back typed, and writes its text for the system's
/// clipboard.
@MainActor
enum TransferKeys {
    /// The journal kind of a registration.
    static let kind = EffectJournal.Kind("transfer.clipboardKey")

    /// Whether this context answers the keys at all: a running app's render,
    /// enabled, and not a list row's (the list is the row's stop).
    static func applies(in context: RenderContext) -> Bool {
        !context.isMeasuring && context.environment.isEnabled && context.environment.focusManager != nil
            && context.environment.listRowEditRestrictions?.currentRowIndex == nil
    }

    /// The modifier's own stop's id, persisted at `propertyIndex`, and whether
    /// it holds the focus — asked before the content draws, so it can be told.
    static func ownStop(prefix: String, propertyIndex: Int, context: RenderContext) -> (id: String, isFocused: Bool) {
        let id = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil, defaultPrefix: prefix, propertyIndex: propertyIndex)
        return (id, FocusRegistration.isFocused(context: context, focusID: id))
    }

    /// The stops the keys answer on: the content's own, found in its drawn
    /// regions, or else `ownID`, registered now.
    static func stops(of buffer: FrameBuffer, ownID: String, context: RenderContext) -> [String] {
        var ids: [String] = []
        for case let id? in buffer.hitTestRegions.map(\.focusID) where !ids.contains(id) { ids.append(id) }
        guard ids.isEmpty else { return ids }
        FocusRegistration.register(
            context: context, handler: ActionHandler(focusID: ownID, action: {}, triggerKeys: []), focusID: ownID)
        return [ownID]
    }

    /// Answers the clipboard command `key` (`"c"` or `"v"`) with `perform`
    /// while one of `focusIDs` holds the focus — and, for `"v"`, the terminal's
    /// own paste. Replayable, so a memo serving the view registers it again.
    static func register(
        _ key: KeyEquivalent, focusIDs: [String], context: RenderContext,
        perform: @escaping (KeyEvent, ClipboardAccess) -> Bool
    ) {
        let sectionID = context.environment.activeFocusSectionID
        let (chord, clipboard) = context.environment.clipboardCommand(key)
        let entry = Entry(key: key, chord: chord, focusIDs: focusIDs, clipboard: clipboard, perform: perform)
        entry.register(sectionID: sectionID, context: context)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(kind: kind, channelToken: context.environment.keyChannelToken) { replay in
                    entry.register(sectionID: sectionID, context: replay)
                })
        }
    }

    /// Answers `chord` with `perform`, handed the stop that holds the focus,
    /// while one of `focusIDs` does: a `.draggable`'s pick-up
    /// (``DragAndDropSession/carryChord``). Replayable, as ``register(_:focusIDs:context:perform:)`` is.
    static func registerChord(
        _ chord: KeyboardShortcut, focusIDs: [String], context: RenderContext,
        perform: @escaping (_ focused: String) -> Bool
    ) {
        let trigger = chord.trigger
        let sectionID = context.environment.activeFocusSectionID
        let entry = ChordEntry(trigger: trigger, focusIDs: focusIDs, perform: perform)
        entry.register(sectionID: sectionID, context: context)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(kind: chordKind, channelToken: context.environment.keyChannelToken) { replay in
                    entry.register(sectionID: sectionID, context: replay)
                })
        }
    }

    /// The journal kind of a chord's registration.
    static let chordKind = EffectJournal.Kind("transfer.chord")

    /// One chord's registration, made by the render and again by a replay.
    private struct ChordEntry {
        let trigger: KeyboardShortcut.Trigger
        let focusIDs: [String]
        let perform: (String) -> Bool

        func register(sectionID: String?, context: RenderContext) {
            let focusManager = context.environment.focusManager
            let (trigger, focusIDs, perform) = (trigger, focusIDs, perform)
            context.environment.keyEventDispatcher?.addHandler(sectionID: sectionID) { [weak focusManager] event in
                guard KeyboardShortcut.trigger(for: event) == trigger, let focusManager,
                    let focused = focusIDs.first(where: { focusManager.isFocused(id: $0) })
                else { return false }
                return perform(focused)
            }
        }
    }

    /// One registration, made by the render and again by a replay.
    private struct Entry {
        let key: KeyEquivalent
        let chord: KeyboardShortcut.Trigger?
        let focusIDs: [String]
        let clipboard: ClipboardAccess
        let perform: (KeyEvent, ClipboardAccess) -> Bool

        func register(sectionID: String?, context: RenderContext) {
            let focusManager = context.environment.focusManager
            let (key, chord, focusIDs, clipboard, perform) = (key, chord, focusIDs, clipboard, perform)
            context.environment.keyEventDispatcher?.addHandler(sectionID: sectionID) { [weak focusManager] event in
                guard let focusManager, focusIDs.contains(where: { focusManager.isFocused(id: $0) }) else {
                    return false
                }
                let isPaste: Bool
                if case .paste = event.key { isPaste = true } else { isPaste = false }
                guard (isPaste && key == "v") || (chord != nil && KeyboardShortcut.trigger(for: event) == chord)
                else { return false }
                return perform(event, clipboard)
            }
        }
    }
}
