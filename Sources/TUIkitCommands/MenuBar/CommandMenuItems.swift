//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CommandMenuItems.swift
//
//  One menu of the menu bar, as the rows its declarations' views make.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// The items of one menu of the menu bar: each group's declarations' views,
/// as rows of their own, with a separator between two groups.
///
/// A child-view provider, so a menu's column — the pop-up drawn when the menu
/// is open, or the stack the closed menus' shortcuts are registered from —
/// lays out each `Button`, `Toggle`, `Divider` and `Section` as a row of its
/// own, as a ``Menu``'s items are, and a `Section` is drawn as a menu draws
/// one. Each declaration's views are keyed under its place in the commands
/// (``CommandItems/key``), so what they keep follows the declaration.
struct _CommandMenuItems: View, Renderable, Layoutable, ChildViewProvider {
    /// The groups, in order, each a run of declarations.
    let groups: [[CommandItems]]

    var body: Never { fatalError("_CommandMenuItems renders via Renderable") }

    func childViews(context: RenderContext) -> [ChildView] {
        var children: [ChildView] = []
        for (index, group) in groups.enumerated() {
            if index > 0 {
                children.append(ChildView(Divider(), childIndex: index).pinningIdentity(to: context.identity))
            }
            for items in group {
                let scope = context.withChildIdentity(erasedType: CommandItems.self, key: items.key)
                children += items.children(scope).map { $0.pinningIdentity(to: scope.identity) }
            }
        }
        return children
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = context.availableWidth
        return FrameBuffer(
            verticallyStacking: childViews(context: context).map { child in
                let size = child.measure(proposal: ProposedSize(width: width, height: nil), context: context)
                return child.render(width: width, height: size.height, context: context)
            })
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var width = 0
        var height = 0
        for child in childViews(context: context) {
            let size = child.measure(proposal: proposal, context: context)
            width = max(width, size.width)
            height += size.height
        }
        return ViewSize(width: width, height: height, isWidthFlexible: false, isHeightFlexible: false)
    }
}
