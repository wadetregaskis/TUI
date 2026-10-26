//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderContext+GeometryRoot.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - The Root

extension RenderContext {
    /// This context as the scene root hands it to the scene: carrying a
    /// geometry origin at `(0, 0)` — the global space's — when the frame's
    /// coordinator has readers to predict for, and unchanged otherwise, so a
    /// tree that asks nothing pays nothing (`RenderContext.geometryOriginX`).
    package func carryingGeometryRootOrigin() -> Self {
        guard let geometry = geometryCoordinator, geometry.hasReaders else { return self }
        return carryingGeometryOrigin()
    }
}
