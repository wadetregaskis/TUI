//  🖥️ TUI — A Terminal UI framework for Swift
//  FormColumnsWindowing.swift
//
//  SCROLL-FIT P8 (design §1c, the owner's A-SCROLLFIT-1): a `.columns` form
//  has no lazy counterpart in SwiftUI, and builds only the rows on screen
//  once its content — a loop over comparable data — passes the lazy stack's
//  threshold, in scroll content, as `GroupBox` and `DisclosureGroup` do
//  (`ImplicitColumnWindowing.swift`). Its label column and its rows' width
//  are read from every row; they are kept from one frame to the next while
//  the loop's data, the width and the labels' visibility are the same, so a
//  frame builds only the rows the scroll view shows, and a change of the
//  data builds every row once to read them again.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// `StateStorage` property indices for `_FormLayout` (file-scope: a generic
/// type cannot hold static storage).
private enum FormStateIndex {
    /// The windowed columns form's kept widths (``FormColumnWidths``).
    /// Negative: the form's content is drawn at its own identity. Range
    /// -230, claimed in ``StateStorage/StateKey``'s table.
    static let columnWidths = -230
}

/// A loop a form's content is, read row by row without building the others.
@MainActor
protocol FormRowLoop {
    /// How many rows the loop draws.
    var formRowCount: Int { get }
    /// The loop's data, boxed for comparison, or `nil` when it cannot be
    /// compared and nothing read from its rows can be kept.
    var formRowsSignature: AnyEquatableBox? { get }
    /// The form's element the `ordinal`-th row is, read where the form's
    /// walk is (`walk`), as the form's extraction reads it: one element, or
    /// the several it makes as one group.
    func formElement(at ordinal: Int, in walk: RenderContext) -> _FormElement
    /// The id of the element the `ordinal`-th row is made from, which the row
    /// is drawn under, as the form drawn whole draws it.
    func formRowID(at ordinal: Int) -> AnyHashable
}

@MainActor extension ForEach: FormRowLoop where Content: View {
    var formRowCount: Int { data.count }

    var formRowsSignature: AnyEquatableBox? { listRowsSignature }

    func formElement(at ordinal: Int, in walk: RenderContext) -> _FormElement {
        let elements = rowElements(of: element(at: ordinal), in: walk)
        return elements.count == 1 ? elements[0] : .group(elements, branch: nil)
    }

    func formRowID(at ordinal: Int) -> AnyHashable { formRowID(of: element(at: ordinal)) }

    private func element(at ordinal: Int) -> Data.Element {
        data[data.index(data.startIndex, offsetBy: ordinal)]
    }
}

/// What a windowed columns form keeps from its whole extraction, for the
/// data and labels' visibility it was read for: at each width it is laid out
/// at, its label column, its rows' width (a row framed by `formRowAlignment`
/// is framed to it), and the width the whole column hugs.
@MainActor
final class FormColumnWidths {
    struct Widths {
        let pillar: Int
        let contentWidth: Int
        let columnWidth: Int
    }

    /// The most widths kept: a frame asks the form at a few (its measures',
    /// its render's), and a resize at a new one.
    static let capacity = 8

    /// The version of the rows the widths were read from: compared in O(1),
    /// where the rows themselves were compared element by element each time
    /// the form was laid out once they came in a new buffer — every frame,
    /// from a body that sorts or filters — as `Table`'s `.fit` columns keep
    /// theirs (`_TableCore.fitMemoKey`).
    let rowsVersion = DataVersion()
    var rows: DataVersion.Token?
    var labelsHidden = false
    var byWidth: [Int: Widths] = [:]
}

@MainActor extension _FormLayout {
    /// The form's column, windowed: a lazy stack of its loop's rows, each
    /// read and laid out only when drawn, framed to the width the whole
    /// column hugs; `nil` when the form is not a long loop over comparable
    /// data in scroll content, and draws every row as before.
    func windowedColumns(context: RenderContext) -> AnyView? {
        guard context.scrollContentOriginDepth != 0, !context.environment.drawsContainerRowsWhole,
            let loop = content as? any FormRowLoop, loop.formRowCount > _VStackCore<EmptyView>.anchoredWindowThreshold,
            let signature = loop.formRowsSignature
        else { return nil }
        let walk = context.withChildIdentity(type: _FormContentWalk.self)
        let widths = keptWidths(signature: signature, context: context)
        let pillar = widths.pillar
        let contentWidth = widths.contentWidth
        // Not memoised by their elements (`FormRowMemo.swift`): each row is
        // already a row of the lazy stack's own loop, memoised there, and a
        // memo inside that one only doubled the bookkeeping of every row
        // served (`app-shapes/columns-form-filtered` +10%, PERFCASE-F7).
        // Each row under its element's id, as the form drawn whole draws it,
        // so its drawn state follows the element (CTRLS-1).
        let rows = ForEach(
            storing: 0..<loop.formRowCount, directID: { loop.formRowID(at: $0) },
            content: { ordinal in
                columnsElementView(
                    loop.formElement(at: ordinal, in: walk), pillar: pillar, contentWidth: contentWidth, walk: nil,
                    isFirst: ordinal == 0)
            })
        return AnyView(
            _VStackCore(alignment: .leading, spacing: 0, overflow: .window, content: rows)
                .frame(width: widths.columnWidth, alignment: .leading))
    }

    /// The widths kept at this form's identity for the width it is laid out
    /// at, read again from every row when the data or the labels' visibility
    /// changed, or at a width not kept.
    private func keptWidths(signature: AnyEquatableBox, context: RenderContext) -> FormColumnWidths.Widths {
        let stateStorage = context.stateStorage!
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: FormStateIndex.columnWidths)
        let box: StateBox<FormColumnWidths> = stateStorage.storage(for: key, default: FormColumnWidths())
        stateStorage.markActive(context.identity)
        let kept = box.value
        let labelsHidden = context.environment.controlLabelsAreHidden
        // Compared by the rows' version, not the rows: see `rowsVersion`.
        let rows = kept.rowsVersion.token(for: signature)
        if kept.rows != rows || kept.labelsHidden != labelsHidden {
            kept.rows = rows
            kept.labelsHidden = labelsHidden
            kept.byWidth.removeAll()
        }
        if let widths = kept.byWidth[context.availableWidth] { return widths }
        let elements = formElements(from: content, in: context.withChildIdentity(type: _FormContentWalk.self))
        let (pillar, contentWidth) = columnWidths(of: elements, walk: nil, context: context)
        let widths = FormColumnWidths.Widths(
            pillar: pillar, contentWidth: contentWidth,
            columnWidth: columnWidth(of: elements, pillar: pillar, contentWidth: contentWidth, context: context))
        if kept.byWidth.count >= FormColumnWidths.capacity { kept.byWidth.removeAll(keepingCapacity: true) }
        kept.byWidth[context.availableWidth] = widths
        return widths
    }

    /// The width the column of `elements` drawn whole is: its widest row
    /// offered the form's width, or the whole of it when a row fills it.
    private func columnWidth(
        of elements: [_FormElement], pillar: Int, contentWidth: Int, context: RenderContext
    ) -> Int {
        let proposal = ProposedViewSize(width: context.availableWidth, height: nil)
        var widest = 0
        for (index, element) in elements.enumerated() {
            let size = measureChild(
                columnsElementView(element, pillar: pillar, contentWidth: contentWidth, walk: nil, isFirst: index == 0),
                proposal: proposal, context: context)
            if size.isWidthFlexible { return context.availableWidth }
            widest = max(widest, size.width)
        }
        return min(widest, context.availableWidth)
    }
}
