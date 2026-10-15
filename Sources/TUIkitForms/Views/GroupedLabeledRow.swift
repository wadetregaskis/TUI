//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GroupedLabeledRow.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// A labelled row of a grouped form, laid out as SwiftUI's is (measured on
/// macOS 15.8, `PROBES-1014/labeledcontent`): the label at the leading edge, a
/// fixed value at the trailing edge — each line of a value of several ending
/// there — and a field or a slider from 45% of the row, or from just after the
/// label where the label is longer, to the trailing edge.
///
/// Both a grouped `Form`'s own labelled rows and a `LabeledContent` drawn in
/// one (``LabeledContentPlacement/groupedFormRow``) are drawn by this.
struct _GroupedLabeledRow: View {
    let label: AnyView
    let content: AnyView

    var body: some View {
        _GroupedLabeledRowCore(label: label, content: content)
    }
}

/// The measuring half: where the content starts depends on whether it takes
/// what it is offered, which only asking it can tell.
private struct _GroupedLabeledRowCore: View, Renderable, Layoutable {
    let label: AnyView
    let content: AnyView

    /// Where a flexible content starts, as a share of the row: SwiftUI's 45%.
    static let flexibleStart = 0.45

    var body: Never {
        fatalError("_GroupedLabeledRowCore renders via Renderable")
    }

    /// The label as every labelled control draws it: with its separating
    /// space, or nothing at all under `.labelsHidden()`.
    private var collapsingLabel: _CollapsingLabel<AnyView> {
        _CollapsingLabel(label: label, controlDisabled: false)
    }

    /// Where the content starts in a row `width` wide, whether it fills, and
    /// the least the row needs: the label and what the content needs at least.
    private func arrangement(width: Int, context: RenderContext) -> (start: Int, fills: Bool, least: Int) {
        let labelWidth = measureChild(collapsingLabel, proposal: .unspecified, context: context).width
        let rest = max(0, width - labelWidth)
        let contentSize = measureChild(content, proposal: ProposedSize(width: rest, height: nil), context: context)
        let least = labelWidth + contentSize.width
        guard contentSize.isWidthFlexible else { return (labelWidth, false, least) }
        let share = Int((Double(width) * Self.flexibleStart).rounded())
        return (min(width, max(labelWidth, share)), true, least)
    }

    /// The row as drawn: the same structure whichever way the content goes, so
    /// a content that changes kind keeps its identity and its state.
    private func row(width: Int, context: RenderContext) -> some View {
        let (start, fills, _) = arrangement(width: width, context: context)
        return HStack(alignment: .top, spacing: 0) {
            collapsingLabel.frame(width: start, alignment: .leading)
            content
                .environment(\.unstatedMultilineTextAlignment, fills ? .leading : .trailing)
                .frame(width: max(0, width - start), alignment: .trailing)
        }
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let width = proposal.width else {
            // Asked for its ideal: the label, then the content at its own.
            let labelWidth = measureChild(collapsingLabel, proposal: .unspecified, context: context)
            let contentSize = measureChild(content, proposal: .unspecified, context: context)
            return ViewSize(
                width: labelWidth.width + contentSize.width,
                height: max(labelWidth.height, contentSize.height), isWidthFlexible: true)
        }
        // Flexible: the row spreads across whatever it is given, so its width
        // is the least it needs (`ViewSize`'s contract for a flexible width).
        let least = arrangement(width: width, context: context).least
        let size = measureChild(row(width: width, context: context), proposal: proposal, context: context)
        return ViewSize(width: min(width, least), height: size.height, isWidthFlexible: true)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(row(width: context.availableWidth, context: context), context: context)
    }
}
