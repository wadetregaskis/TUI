//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewChords.swift
//
//  The sidebar chords of ``NavigationSplitView``, ⌃S and ⌥⌃S: SwiftUI's View ▸
//  Show Sidebar and Toggle Sidebar, registered by the split's render and by a
//  value memo replaying it. Split out of `NavigationSplitViewToggle.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

// MARK: - Sidebar chord registration

/// A split view's sidebar chords, as registered by its render and by a value
/// memo replaying one — see `EffectJournal`.
enum SidebarChordRegistrar {
    /// The journal kind of a split view's sidebar chords.
    static let kind = EffectJournal.Kind("sidebarChords")

    /// Registers `action` as the framework default for each of `shortcuts`.
    ///
    /// The registry is looked up in `context`, not handed in, so a replay
    /// registers into the registry of the walk that serves it.
    @MainActor
    static func register(
        _ shortcuts: [KeyboardShortcut], holdsFocus: Bool, action: @escaping () -> Void,
        context: RenderContext
    ) {
        guard let registry = context.environment.keyboardShortcutRegistry else { return }
        for shortcut in shortcuts {
            registry.registerDefault(shortcut, holdsFocus: holdsFocus, action: action)
        }
    }
}

// MARK: - Registration

extension _NavigationSplitViewCore {
    /// Registers SwiftUI's two sidebar chords, View ▸ Show Sidebar
    /// `("s", [.command, .control])` and the hidden Toggle Sidebar
    /// `("s", [.command, .option])`, each resolved through `commandKey`: ⌃S and
    /// ⌥⌃S under the default `.control`, none under `.unavailable`.
    ///
    /// They work wherever the focus is, as framework defaults
    /// (`KeyboardShortcutRegistry.registerDefault`), so an app shortcut on the
    /// same keys wins, and anything that consumes the key earlier in the input
    /// chain (`onKeyEvent`, a focused sortable Table) does too. Every split
    /// registers them twice: at the start of its render, which makes the first
    /// split in render order the one that toggles when no split holds the focus;
    /// and, if it holds the focus, again once its columns have rendered, which
    /// makes the innermost focus-holding split win.
    ///
    /// A disabled split registers nothing, as a disabled `Button` registers no
    /// shortcut. `.toolbar(removing: .sidebarToggle)` leaves the chords alone, as
    /// SwiftUI's menu items stay when its toolbar button goes.
    func registerSidebarChords(
        context: RenderContext, toggleState: SplitViewToggleState, holdsFocus: Bool
    ) {
        // A collapsed split registers none either: SwiftUI ignores column
        // visibility there, so the chords would change nothing to see — until
        // the split expanded again with its sidebar hidden.
        guard !context.isMeasuring, context.environment.isEnabled, !isCollapsed(context),
            context.environment.keyboardShortcutRegistry != nil
        else { return }
        // The registry is emptied every walk. Declared as REPLAYABLE: a memo
        // serving the split registers the chords again from the entry below.
        // The split's own sections declare separately, in `renderToBuffer`.
        context.environment.volatileReadTracker?.recordReplayableEffect()
        let action = stepAction(toggleState: toggleState, focus: nil) { visibility, isThreeColumn in
            SplitViewToggle.togglingSidebar(visibility, isThreeColumn: isThreeColumn)
        }
        let modifierSets: [EventModifiers] = [[.command, .control], [.command, .option]]
        let shortcuts = modifierSets.compactMap {
            KeyboardShortcut("s", modifiers: $0).resolved(commandKey: context.environment.commandKey)
        }
        SidebarChordRegistrar.register(shortcuts, holdsFocus: holdsFocus, action: action, context: context)
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(
                    kind: SidebarChordRegistrar.kind, channelToken: context.environment.keyChannelToken
                ) { replay in
                    SidebarChordRegistrar.register(
                        shortcuts, holdsFocus: holdsFocus, action: action, context: replay)
                })
        }
    }
}
