//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TUIContext+Reset.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Internal API

extension TUIContext {
    /// Resets all services to their initial state.
    func reset() {
        lifecycle.reset()
        keyEventDispatcher.clearHandlers()
        preferences.reset()
        stateStorage.reset()
        renderCache.reset()
    }
}
