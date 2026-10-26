//  🖥️ TUI — A Terminal UI framework for Swift
//  View+Convenience.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Type Erasure

extension View {
    /// Wraps this view in an AnyView for type erasure.
    ///
    /// Use this when you need to return different view types from
    /// conditional branches.
    public func asAnyView() -> AnyView {
        AnyView(self)
    }
}
