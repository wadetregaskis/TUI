//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderOnce.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation

/// Executes a view closure and renders it once.
///
/// This is useful for simple CLI tools that don't need a full App.
///
/// # Example
///
/// ```swift
/// renderOnce {
///     VStack {
///         Text("Hello, TUI!")
///             .bold()
///             .foregroundStyle(.cyan)
///         Divider()
///         Text("Version \(tuiKitVersion)")
///             .dim()
///     }
/// }
/// ```
///
/// - Parameter content: A ViewBuilder closure that defines the view to render.
@MainActor
public func renderOnce<Content: View>(@ViewBuilder content: () -> Content) {
    let view = content()
    let renderer = ViewRenderer(terminal: Terminal())
    renderer.render(view)
}
