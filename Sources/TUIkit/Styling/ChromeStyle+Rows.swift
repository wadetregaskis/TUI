//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeStyle+Rows.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

extension ChromeStyle {
    /// How many rows this style adds around the bar's own content.
    ///
    /// The single place the arithmetic lives: heights are computed before the
    /// bars render (the layout has to reserve their space first), so a style
    /// that added a row here and forgot to draw it there would overlap the
    /// page — or leave a gap.
    var chromeRows: Int {
        switch self {
        case .rule: return 1
        case .bordered: return 2
        case .compact: return 0
        }
    }

    /// The bar's total height for `contentRows` rows of content.
    func barHeight(contentRows: Int) -> Int {
        contentRows + chromeRows
    }

    /// How many columns the style's own drawing takes away from the bar's
    /// content — a wall down each side of a box, nothing for the rest.
    ///
    /// Wanted in two places that must agree: the modifier lays the header
    /// content out at `width - contentWidthInset`, and the renderer pads each
    /// of those lines to the same figure before boxing them. Laying out at the
    /// full width and boxing afterwards is what silently ate the last two cells
    /// of every header ("TUIkit v0.6" for "TUIkit v0.6.0").
    var contentWidthInset: Int {
        self == .bordered ? BorderRenderer.borderWidthOverhead : 0
    }

    /// How wide a status bar's content may be at a terminal width of `width`.
    ///
    /// The bordered style spends its two walls AND a space of padding either
    /// side of the content. Wanted in two places that must agree — the tooltip
    /// row wraps its text to this, and `_StatusBarCore.renderBordered` lays the
    /// items out at it — so it is one function rather than the same subtraction
    /// written twice.
    func barContentWidth(_ width: Int) -> Int {
        max(1, width - contentWidthInset - (self == .bordered ? 2 : 0))
    }
}

// MARK: - Shared drawing

extension ChromeStyle {
    /// A full-width rule in the current appearance's horizontal border glyph and
    /// the palette's border colour.
    ///
    /// Shared so the header's rule and the status bar's are the same rule: they
    /// are meant to read as two edges of one frame, and drawing them from two
    /// places is how they drift.
    @MainActor
    static func ruleRow(width: Int, context: RenderContext) -> String {
        // Through `BorderRenderer` rather than by hand: a rule drawn in a style
        // that paints its cells must paint them here too, or a block-bordered
        // page grows a hairline gap where its rules are.
        BorderRenderer.rule(
            style: context.environment.appearance.borderStyle, width: width,
            color: context.environment.palette.border)
    }

    /// The claim ``ruleRow(width:context:)`` needs when the theme's border colour
    /// is faded — its other half, and beside it for that reason.
    ///
    /// `BorderRenderer` states the opaque spelling in the bytes because an SGR
    /// emitter has no backdrop to composite against, so a rule drawn from a
    /// translucent palette entry has an alpha still to spend. A rule is one row of
    /// the full width, which makes this the simplest claim in the framework — and
    /// the easiest to forget, which is why it is not left to the two call sites to
    /// remember.
    ///
    /// - Parameters:
    ///   - width: The rule's width, matching the row it was drawn for.
    ///   - offsetY: The row the rule was placed on.
    ///   - context: The render context, for the palette.
    /// - Returns: The region, or `nil` when the border colour is opaque.
    @MainActor
    static func ruleClaim(width: Int, offsetY: Int, context: RenderContext) -> OpacityRegion? {
        let style = context.environment.appearance.borderStyle
        let colour = context.environment.palette.border
        return OpacityRegion.claim(
            offsetY: offsetY, width: width, height: 1, ink: colour,
            field: BorderRenderer.fill(style, colour))
    }
}
