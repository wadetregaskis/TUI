//  🖥️ TUI — A Terminal UI framework for Swift
//  FormScroller.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - A grouped form's scroll view

/// A form's laid-out rows, in a scroll view when the form is grouped.
///
/// A grouped form is a scroll view on macOS, as SwiftUI's is: content taller
/// than its space scrolls by the wheel and by the paging keys the focused
/// control leaves, and Tab onto a row below the visible area scrolls it in
/// (measured, `Tools/SwiftUIProbes/Tab into rows off screen (1110F)`). So it
/// fills the space it is offered, as SwiftUI's does, and answers the scroll
/// modifiers written on it, `contentMargins` among them: around its sections,
/// and not passed on to them (measured). The scroll view is no Tab stop of its
/// own, as SwiftUI's is not: the form's controls are the stops, and the reveal
/// scrolls to whichever holds the focus.
///
/// A columns form is not one: Apple's `FormStyle.columns` is "a non-scrolling
/// form style", and the probe found no scroll view in it. Nor is a form of a
/// style of the app's own, which draws what its `makeBody` draws.
struct _FormScroller<Content: View>: View {
    let content: Content
    @Environment(\.formStyle) private var style

    var body: some View {
        if style is GroupedFormStyle {
            ScrollView {
                content.transformEnvironment(\.contentMargins) { $0 = ContentMargins() }
            }
            .withoutFocusStop()
        } else {
            content
        }
    }
}
