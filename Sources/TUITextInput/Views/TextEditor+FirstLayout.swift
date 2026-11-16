//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditor+FirstLayout.swift
//
//  The layout an editor's measures make in the frame it first appears, before
//  its render has made the handler that keeps one: kept for that frame's other
//  measures and handed to the handler its render makes.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The text a measure laid out before the editor had a handler, the glyph it
/// was hidden with (`nil` where it is shown), and its layout.
///
/// Kept as a tracked value at the editor's identity, not a box: a measure
/// must not create state (``StateStorage/existingStorage(for:)``), and a
/// tracked value is no state anything reads but this. It goes with the
/// identity at the end of a pass that did not draw it, as a box does, and the
/// render that makes the handler takes it out.
struct FirstEditorLayout {
    let text: String
    let glyph: Character?
    let layout: EditorLayout
}

extension _TextEditorCore {
    /// The layout of `current`, hidden with `glyph` where it is, for a measure
    /// of an editor that has no handler yet: the one an earlier measure of
    /// this frame made, while the text is the same, else a new one, kept for
    /// the next.
    ///
    /// tuitree's M5 feedback, item 1: each measure of a new editor laid its
    /// whole text out afresh, and its render once more, six times over in a
    /// pane beside a tree and under a heading (`EditorLayoutFirstFrameTests`).
    func firstLayout(of current: String, hidingWith glyph: Character?, context: RenderContext) -> EditorLayout {
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.firstLayoutStateIndex)
        // `String ==` answers from the storage when the binding hands back the
        // string it handed the last measure, which it does.
        if let kept: FirstEditorLayout = context.stateStorage?.trackedValue(for: key), kept.glyph == glyph,
            kept.text == current
        {
            return kept.layout
        }
        let fresh = EditorLayout(text: glyph.map { TextEditorHandler.hiding(current, with: $0) } ?? current)
        context.stateStorage?.setTrackedValue(FirstEditorLayout(text: current, glyph: glyph, layout: fresh), for: key)
        return fresh
    }

    /// Hands a handler that has laid nothing out yet — the one this frame's
    /// render just made — the layout this frame's measures made, and drops
    /// it from the identity, so a document the editor has since moved on
    /// from is not kept alive beside it. The handler's own check of the text
    /// (``TextEditorHandler/layout(of:)``) lays out afresh a text the binding
    /// changed between the measure and the render.
    func adoptFirstLayout(into handler: TextEditorHandler, context: RenderContext) {
        guard handler.cachedLayout == nil, handler.cachedDisplayLayout == nil, let storage = context.stateStorage
        else { return }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.firstLayoutStateIndex)
        guard let kept: FirstEditorLayout = storage.trackedValue(for: key) else { return }
        // Absent from now on: a tracked `nil` reads back as no value.
        storage.setTrackedValue(FirstEditorLayout?.none, for: key)
        if let glyph = kept.glyph {
            handler.cachedDisplayLayout = (kept.text, glyph, kept.layout)
        } else {
            handler.cachedLayout = kept.layout
        }
    }
}
