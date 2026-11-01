//  🖥️ TUI — A Terminal UI framework for Swift
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
/// unequal, and says so (`PartiallyComparable`), so the render cache declines
/// the memos under it rather than serving them stale, the price the style
/// protocols' documentation states. Unequal alone, the cache read it as a
/// change on every pass and cleared everything under it every frame.
package struct StyleChain<Style>: Equatable, PartiallyComparable {
    /// The style in force.
    package let style: Style

    /// The chain that was in force where ``style`` was set, or `nil` at the
    /// root — the environment's default.
    let outer: Box?

    /// The outer chain, boxed because a struct cannot hold itself.
    final class Box: Equatable {
        let chain: StyleChain

        init(_ chain: StyleChain) {
            self.chain = chain
        }

        static func == (lhs: Box, rhs: Box) -> Bool {
            lhs === rhs || lhs.chain == rhs.chain
        }
    }

    /// A chain of one style, with nothing outside it.
    package init(_ style: Style) {
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
    package func pushing(_ style: Style) -> Self {
        Self(style, outer: self)
    }

    /// The chain a control drawn INSIDE ``style``'s body sees: the one outside
    /// it, or this one at the root.
    package var inside: Self {
        outer?.chain ?? self
    }

    /// Whether this is the root chain, the environment's default: no style
    /// was put in force over it. Asked here, where ``outer`` is, so that a
    /// control in another module asks one question, not for the box.
    package var isRoot: Bool {
        outer == nil
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = lhs.style as? any Equatable, left.isEqual(to: rhs.style) else { return false }
        return lhs.outer == rhs.outer
    }

    /// Whether every style in the chain is `Equatable`, which is when `==` can
    /// say anything but "unequal".
    package var isComparable: Bool {
        style is any Equatable && (outer?.chain.isComparable ?? true)
    }
}
