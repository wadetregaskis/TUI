//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DeferredListRow.swift
//
//  A list row drawn from one of a container's children when the list first
//  reads it, rather than as the list extracts its rows.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The list row `child` draws, as a box that renders it when the list first
/// reads it: at the identity the child has in `context`, with what a list asks
/// of any row — its size without drawing it, its badge, where it sits in a
/// ramp, its raised background when it is the focused, selected row, the
/// separator guides it states and its type-select text.
///
/// - Parameters:
///   - child: The child, as the container's walk resolved it.
///   - listRow: Which row of the enclosing LIST this is — what a refusal
///     (`.deleteDisabled()`) or a separator guide inside it reports against.
///   - context: The context the child is drawn under, before its own identity
///     step, which the child applies itself.
///   - placedByRamp: Whether a ramp spanning the list places the row by the
///     list's row pitch (``ListRowRamp``) — `false` where `context` already
///     places it exactly.
@MainActor
package func deferredListRow(
    of child: ChildView, listRow: Int, context: RenderContext, placedByRamp: Bool = true
) -> LazyListRowContent {
    let box = LazyListRowContent(
        identity: child.identity(under: context),
        carriesBadge: rowCarriesBadge(child.wrappedView),
        measure: {
            let size = child.measure(
                proposal: ProposedSize(width: context.availableWidth, height: nil), context: context)
            return (size, context.availableWidth)
        },
        render: { placement, prominence in
            var rowContext = context
            if placedByRamp { rowContext.gradientFrame = placement ?? rowContext.gradientFrame }
            if prominence != .standard { rowContext.environment.backgroundProminence = prominence }
            context.environment.listRowEditRestrictions?.currentRowIndex = listRow
            let buffer = child.render(
                width: rowContext.availableWidth, height: rowContext.availableHeight, context: rowContext)
            // Cleared after, as every row clears it, so what draws next
            // outside a row reports against none.
            context.environment.listRowEditRestrictions?.currentRowIndex = nil
            // The separator guides this view states (decisions A47, B-D6L-3).
            reportSeparatorGuides(
                of: child, size: (buffer.width, buffer.height), row: listRow, context: rowContext)
            return (buffer, extractRowBadge(from: child.wrappedView))
        })
    box.typeSelectProbe = typeSelectProbe(statedBy: child.wrappedView) {
        var probe = context
        probe.isMeasuring = true
        return LazyListRowContent.typeSelectText(
            drawnIn: child.render(width: context.availableWidth, height: context.availableHeight, context: probe))
    }
    return box
}

/// The one row `content` makes when it is the whole content of a list, or of a
/// list's section, and is neither a loop nor several views — `List {
/// Text("Notifications").badge(5) }`, `Section("Sync") { Toggle(…) }` — drawn
/// when the list reads it; `nil` when it draws nothing at all, an `EmptyView`,
/// which is no row.
///
/// Drawn at `context`'s own identity, the list's or the section's, where it
/// always was. Measured to tell nothing from a row — a content whose height
/// can grow is a row, as it was drawn at the list's height — and, under a ramp
/// spanning the list, to place it: one row is the whole of what the ramp spans,
/// so its own height is the extent.
@MainActor
package func loneListRow<V: View>(of content: V, context: RenderContext) -> LazyListRowContent? {
    let measured = measureChild(
        content, proposal: ProposedSize(width: context.availableWidth, height: nil), context: context)
    guard measured.height > 0 || measured.isHeightFlexible else { return nil }
    var rowContext = context
    if context.gradientFrame != nil {
        rowContext = context.placingChild(
            gradient: context.gradientContentFrame(width: context.availableWidth, height: max(1, measured.height)),
            x: 0, y: 0)
    }
    let badge = extractListRowBadge(from: content)
    return LazyListRowContent(
        identity: context.identity, carriesBadge: badge != nil,
        measure: { (measured, context.availableWidth) },
        render: { _, prominence in
            var drawn = rowContext
            if prominence != .standard { drawn.environment.backgroundProminence = prominence }
            return (TUIkitView.renderToBuffer(content, context: drawn), badge)
        })
}
