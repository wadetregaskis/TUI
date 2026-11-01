//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionActionsView+Parts.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// A section with actions is its section's parts in a container — the actions
/// belong to a `List`, which keeps the section whole, as do the section APIs,
/// which hand them to a custom container.
@MainActor extension _SectionActionsView: ChildViewProvider where Content: ChildViewProvider {
    func childViews(context: RenderContext) -> [ChildView] {
        guard !staysWhole(in: context) else { return [ChildView(self)] }
        // A step inside this view, where drawing it through its `body` puts
        // the section.
        let sectionScope = context.withChildIdentity(type: Content.self)
        return resolveChildViews(from: content, context: sectionScope).map {
            $0.pinningIdentity(to: sectionScope.identity)
        }
    }

    func staysWhole(in context: RenderContext) -> Bool {
        content.staysWhole(in: context)
    }
}
