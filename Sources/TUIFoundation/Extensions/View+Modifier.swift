//  🖥️ TUI — A Terminal UI framework for Swift
//  View+Modifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - View Modifier Extension

extension View {
    /// Applies a modifier to this view.
    ///
    /// - Parameter modifier: The modifier to apply.
    /// - Returns: A modified view.
    nonisolated public func modifier<M: BufferModifier>(_ modifier: M) -> ModifiedView<Self, M> {
        ModifiedView(content: self, modifier: modifier)
    }
}
