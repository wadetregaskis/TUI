//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditor+Highlighting.swift
//
//  A frame's part in a TextEditor's highlighting (lane H6′ of the
//  highlighting design's §8.6): the highlighter in the environment started
//  in a task of its own when the editor appears, kept across body
//  evaluations while it is the same one (B-ATTRED-25), and cancelled when
//  the editor goes or is given another (B-ATTRED-22); and the lines on
//  screen told to its session each frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension _TextEditorCore {
    /// Starts, keeps or stops the environment's highlighter for `handler`,
    /// and tells its session the lines `window` shows. A render's work,
    /// never a measure's; and only where effects fire, so a snapshot render
    /// starts no highlighter.
    func syncHighlighter(_ handler: TextEditorHandler, window: Window, height: Int, context: RenderContext) {
        let wanted = context.environment.textEditorHighlighting
        guard let lifecycle = context.environment.lifecycle, let stateStorage = context.stateStorage,
            wanted != nil || handler.highlightConnection != nil
        else { return }
        let token = "texteditor-highlighter-\(context.identity.path)"
        // Its appearance taken back (a drawing discarded), it starts again.
        let appeared = lifecycle.hasAppeared(token: token)
        if let connection = handler.highlightConnection,
            !appeared || wanted.map({ !connection.key.isSame(as: $0.key) }) ?? true
        {
            lifecycle.cancelTask(token: token)
            handler.disconnectHighlighter()
        }
        guard let wanted else { return }
        // Its session told of the lines drawn: what no buffer kept can do.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        if handler.highlightConnection == nil {
            start(wanted, for: handler, token: token, lifecycle: lifecycle, stateStorage: stateStorage, context: context)
        }
        if !appeared {
            lifecycle.registerDisappear(token: token) { [weak handler, lifecycle] in
                lifecycle.cancelTask(token: token)
                handler?.disconnectHighlighter()
            }
        }
        _ = lifecycle.recordAppear(token: token) {}
        handler.syncHighlighting(visibleLines: visibleLines(window, handler: handler, height: height))
    }

    /// Makes `highlighting`'s session over the editor's text, connects the
    /// handler to it, and starts the highlighter's work, off the main actor
    /// (`TextEditorHighlightSession.run(_:)`), as `AsyncImage` starts its load.
    private func start(
        _ highlighting: EditorHighlighting, for handler: TextEditorHandler, token: String,
        lifecycle: LifecycleManager, stateStorage: StateStorage, context: RenderContext
    ) {
        // Written when a line on screen changed its tokens: the editor's
        // memo goes, and a frame is asked for (`AsyncImage`'s pattern).
        let generation: StateBox<UInt32> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: Self.highlightsStateIndex),
            default: 0)
        let redraw: @MainActor @Sendable () -> Void = { generation.value &+= 1 }
        let layout = handler.layout()
        let started = highlighting.start(layout.text, layout.lines.count) { Task { @MainActor in redraw() } }
        handler.connectHighlighter(
            EditorHighlightConnection(key: highlighting.key, feed: started.feed, style: started.style), layout: layout)
        lifecycle.startTask(
            token: token, priority: .userInitiated, name: "TextEditor highlighting", identity: context.identity,
            operation: started.work)
    }

    /// The lines `window` shows, from its first row's to its last's.
    private func visibleLines(_ window: Window, handler: TextEditorHandler, height: Int) -> Range<Int> {
        let last = window.offset + max(1, height) - 1
        if let rows = window.rows {
            return rows.placement(ofRow: window.offset).line..<(rows.placement(ofRow: last).line + 1)
        }
        let rows = handler.sidewaysRows()
        return rows.placement(ofRow: window.offset).line..<(rows.placement(ofRow: last).line + 1)
    }
}
