//  🖥️ TUI — A Terminal UI framework for Swift
//  ContainerBodyHeight.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

/// The height a container built by `renderContainer` offers its body.
///
/// For a view that decides how much content to make before handing it over. A
/// `List` fills its body with exactly as many row lines as fit, and the
/// container clips a taller body from the bottom — so the list asks, rather than
/// repeating the container's arithmetic. Its own copy charged a flat two lines
/// for "footer + separator", which hid the last row under a footer that wrapped
/// and left the box a line short under `.listFooterSeparator(false)`.
///
/// Built by `makeContainer`, like the render, so the footer is measured at the
/// identity and in the environment it is drawn in. That costs one
/// side-effect-free render of the footer; without a footer it is arithmetic.
///
/// - Parameters:
///   - title: The container title (optional).
///   - config: The shared visual configuration.
///   - content: A body of the type that will be rendered. Its TYPE is part of
///     the footer's identity; its value is never read.
///   - footer: The footer view (optional).
///   - context: The context the container will be rendered in.
/// - Returns: The height the container will offer its body.
@MainActor
internal func containerBodyHeight<Content: View, Footer: View>(
    title: String?,
    config: ContainerConfig,
    content: Content,
    footer: Footer?,
    context: RenderContext
) -> Int {
    // No footer to measure, and `makeContainer` draws no separator without one,
    // so the chrome is the border alone — `verticalBudget`'s answer, without
    // rendering an empty footer to learn that it is empty.
    guard footer != nil else {
        return RenderContext.extent(context.availableHeight, insideChrome: config.hasBorder ? 2 : 0)
    }
    return makeContainer(title: title, config: config, content: content, footer: footer)
        .bodyHeight(in: context)
}
