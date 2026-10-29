//  🖥️ TUI — A Terminal UI framework for Swift
//  SearchFindChord.swift
//
//  Find (⌘F) for a searchable view: the chord that puts the keys in its search
//  field, as Edit ▸ Find ▸ Find… does for a macOS window's search field.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

/// Registers Find — `("f", .command)`, through `commandKey`: ⌃F by default —
/// as a framework default that moves the focus to the search field, and draws
/// nothing.
///
/// A default, so an app shortcut on the same keys wins, and so does a control
/// that takes the key first: a text field's ⌃F, forward a character, and a
/// text editor's own find. Drawn behind the field, so a field the searchable
/// does not draw (`_SearchFieldPlace`) registers nothing, and a disabled one
/// none either, as a disabled `Button` registers no shortcut.
struct _SearchFindChord: View, Renderable, Layoutable {
    let search: SearchDismissal

    var body: Never {
        fatalError("_SearchFindChord renders via Renderable")
    }

    /// The journal kind of a search field's Find chord.
    static let kind = EffectJournal.Kind("searchFindChord")

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(width: 0, height: 0)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring, context.environment.isEnabled,
            let shortcut = KeyboardShortcut("f", modifiers: .command)
                .resolved(commandKey: context.environment.commandKey),
            context.environment.keyboardShortcutRegistry != nil
        else { return FrameBuffer() }
        // The registry is emptied every walk: declared as REPLAYABLE, so a memo
        // serving the field registers the chord again from the entry below.
        context.environment.volatileReadTracker?.recordReplayableEffect()
        let search = search
        let action = { MainActor.assumeIsolated { search.focusField() } }
        Self.register(shortcut, action: action, context: context)
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(kind: Self.kind, channelToken: context.environment.keyChannelToken) { replay in
                    Self.register(shortcut, action: action, context: replay)
                })
        }
        return FrameBuffer()
    }

    /// Registers `action` as the framework default for `shortcut`, in the
    /// registry `context` holds — the replaying walk's, for a replay.
    @MainActor
    private static func register(_ shortcut: KeyboardShortcut, action: @escaping () -> Void, context: RenderContext) {
        context.environment.keyboardShortcutRegistry?.registerDefault(
            shortcut, section: context.environment.activeFocusSectionID, action: action)
    }
}
