//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SearchFieldPlace.swift
//
//  Where a `searchable` draws its field: at the top of the view it modifies,
//  in a bar a `DefaultToolbarItem(kind: .search)` claimed it for, or nowhere
//  once `toolbar(removing: .search)` took it away (refusal review O17).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// Draws a searchable's field — with its scopes — where it goes this walk:
/// here; or, claimed for a bar, handed to the window's chrome for the search
/// item to draw, taking no room here; or nowhere.
///
/// Decided as it renders, from the window's chrome, which no memo keys on: so
/// the read is declared, or a memoised ancestor would serve the field from
/// before a claim.
struct _SearchFieldPlace<Field: View>: View, Renderable, Layoutable {
    let field: Field

    var body: Never { fatalError("_SearchFieldPlace renders via Renderable") }

    private enum Place {
        case here, bar, nowhere
    }

    private func place(_ context: RenderContext) -> Place {
        let chrome = context.environment.windowChrome
        if chrome != nil { context.environment.volatileReadTracker?.recordUnkeyedRead() }
        if context.environment.toolbarSearchRemoved || chrome?.searchFieldRemoved == true { return .nowhere }
        return chrome?.searchFieldClaimed == true ? .bar : .here
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        switch place(context) {
        case .here:
            return TUIkitView.renderToBuffer(field, context: context)
        case .bar:
            handOver(context)
            return FrameBuffer()
        case .nowhere:
            return FrameBuffer()
        }
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        switch place(context) {
        case .here:
            return measureChild(field, proposal: proposal, context: context)
        case .bar:
            // The first frame's seeding walk measures, and the bar the field
            // goes to is sized from it (`EnvironmentValues.seedsWindowChrome`).
            if context.environment.seedsWindowChrome { handOver(context) }
            return ViewSize.fixed(0, 0)
        case .nowhere:
            return ViewSize.fixed(0, 0)
        }
    }

    /// Hands the field to the window's chrome for the search item to draw.
    /// Every walk hands it over afresh, so a memoised ancestor serving its
    /// buffer would leave the bar with no field: declared as a side effect.
    private func handOver(_ context: RenderContext) {
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        context.environment.windowChrome?.offerSearchField(AnyView(field))
    }
}
