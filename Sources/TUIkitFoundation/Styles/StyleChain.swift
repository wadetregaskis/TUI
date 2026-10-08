//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StyleChain.swift
//
//  A control style in force, and the one that was in force where it was set.
//
//  SwiftUI lets a custom style decorate the CURRENT appearance rather than
//  replace it: `Toggle(configuration)`, `Label(configuration)` and their kind,
//  inside the style's own body, draw the control as the style that was in force
//  OUTSIDE it would. That needs the environment to remember the outer style —
//  without it, the control drawn inside the body finds the custom style again
//  and recurses into it for ever.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A style in force, and the chain of styles outside it.
///
/// `Style` is an existential — `any LabelStyle`, say — held as the environment
/// holds a style. Equal when both styles are `Equatable`, of one type and equal,
/// and so are the styles outside them: a style that is not `Equatable` compares
/// unequal, so the render cache treats what is under it as changed every frame
/// rather than serving it stale, the price the style protocols' documentation
/// states.
struct StyleChain<Style>: Equatable, @unchecked Sendable {
    /// The style in force.
    let style: Style

    /// The chain that was in force where ``style`` was set, or `nil` at the
    /// root — the environment's default.
    let outer: Box?

    /// The outer chain, boxed because a struct cannot hold itself. Immutable,
    /// which is what makes the unchecked `Sendable` true.
    final class Box: Equatable, @unchecked Sendable {
        let chain: StyleChain

        init(_ chain: StyleChain) {
            self.chain = chain
        }

        static func == (lhs: Box, rhs: Box) -> Bool {
            lhs === rhs || lhs.chain == rhs.chain
        }
    }

    /// A chain of one style, with nothing outside it.
    init(_ style: Style) {
        self.style = style
        self.outer = nil
    }

    /// `style` in force over `outer` — or over nothing, for a chain whose
    /// absence means "none in force" rather than a default style.
    init(_ style: Style, outer: Self?) {
        self.style = style
        self.outer = outer.map(Box.init)
    }

    /// `style` put in force over this chain.
    func pushing(_ style: Style) -> Self {
        Self(style, outer: self)
    }

    /// The chain a control drawn INSIDE ``style``'s body sees: the one outside
    /// it, or this one at the root.
    var inside: Self {
        outer?.chain ?? self
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = lhs.style as? any Equatable, left.isEqual(to: rhs.style) else { return false }
        return lhs.outer == rhs.outer
    }
}
