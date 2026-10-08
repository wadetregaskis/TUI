//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TUIContext+Reset.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Internal API

extension TUIContext {
    /// Resets the services a render walk fills to their initial state.
    ///
    /// Including what the last walk registered with the mouse dispatcher, the
    /// shortcut registry and the drag session — its hit-test handlers, its
    /// shortcuts, its drop targets and auto-scroll zones — which the next walk
    /// would have emptied first. Those hold closures over the walk's
    /// `RenderContext`, whose environment holds these services and the state
    /// storage and render cache, so a context let go of with them filled was
    /// kept alive by its own registrations: every `renderOnce` of a `List`
    /// stayed whole for the life of the process.
    ///
    /// The context's other stores are left as they are: the images sent to
    /// the terminal, the clipboards, the tooltip and screen-selection state,
    /// the undo keys and the departed undo steps, and a drag in progress.
    func reset() {
        lifecycle.reset()
        keyEventDispatcher.clearHandlers()
        mouseEventDispatcher.beginRenderPass()
        keyboardShortcuts.beginRenderPass()
        dragAndDropSession.beginFrame()
        preferences.reset()
        stateStorage.reset()
        renderCache.reset()
    }
}
