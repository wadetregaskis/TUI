//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderingPane.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Renders `content` as the content of pane `id`, with the focus manager and
/// the shortcut registry told so for as long as it renders — see
/// ``FocusManager/beginPane(id:)``.
///
/// A memo that serves a subtree of the content replays its registrations here,
/// where the subtree would have rendered, so they land in the pane as well.
@MainActor
func renderingPane<Result>(_ id: String, context: RenderContext, _ content: () -> Result) -> Result {
    guard !context.isMeasuring else { return content() }
    let focusManager = context.environment.focusManager
    let registry = context.environment.keyboardShortcutRegistry
    var outer: String?
    if let focusManager { outer = focusManager.beginPane(id: id) }
    var outerShortcutPane: String?
    if let registry {
        outerShortcutPane = registry.currentPane
        registry.currentPane = id
    }
    defer {
        focusManager?.endPane(restoring: outer)
        registry?.currentPane = outerShortcutPane
    }
    return content()
}
