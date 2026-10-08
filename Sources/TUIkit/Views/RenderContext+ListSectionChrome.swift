//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderContext+ListSectionChrome.swift
//
//  Created by LAYERED.work
//  License: MIT

extension RenderContext {
    /// This context with ``EnvironmentValues/drawsListSectionChrome`` set, for
    /// a `List` to draw in. Written directly, as a stack publishes its axis: a
    /// list is a list on every frame, so no memo can hold a value that changed.
    func drawingListSectionChrome() -> RenderContext {
        guard !environment.drawsListSectionChrome else { return self }
        var copy = self
        copy.environment.drawsListSectionChrome = true
        return copy
    }
}
