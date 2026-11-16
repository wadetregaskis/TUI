//  🖥️ TUI — A Terminal UI framework for Swift
//  _ListCore+SectionWindow.swift
//
//  A `List` whose content is one `Section` holding an outline: the outline's
//  rows windowed, as a list of the outline alone windows them, with the
//  section's header before them and its footer after (finding G1-section).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIView

extension _ListCore {
    /// The rows of a list whose content is one section, `info`'s, holding an
    /// outline whose rows are `rows`: the header, if any, then the outline's
    /// rows, then the footer, if any.
    ///
    /// Each row's box is made only when the overflow check or the window walks
    /// to it, so a tree of thousands of open rows costs a screenful a frame,
    /// where the eager section made a box for every open row. Everything the
    /// eager section gives a row is given here as the row is made: the line
    /// under the header is the section's `.top` edge, the line under the last
    /// row its `.bottom` edge, and the header carries its actions while the
    /// section is in use. An outline has no `.onDelete` or `.onMove`, so there
    /// is no edit owner to place.
    func windowedSectionSource(
        info: SectionInfo, rows: OutlineListRows<SelectionValue>, rowsContent: (any View)?, context: RenderContext
    ) -> RowSource<SelectionValue> {
        let headerRows = info.headerBuffer == nil ? 0 : 1
        let footerRow: Int? = info.footerBuffer == nil ? nil : headerRows + rows.count
        let count = headerRows + rows.count + (footerRow == nil ? 0 : 1)
        var headerBuffer = info.headerBuffer
        if let actions = info.headerActions, headerRows == 1,
            let drawn = Self.sectionHeader(actions: actions, span: 0..<count, context: context) {
            headerBuffer = drawn
        }
        var chrome: [(index: Int, isHeader: Bool)] = headerRows == 1 ? [(0, true)] : []
        if let footerRow { chrome.append((footerRow, false)) }
        let separator = info.separator
        let footerBuffer = info.footerBuffer
        let lastItem = headerRows + rows.count - 1
        let source = RowSource<SelectionValue>(
            count: count, allContent: chrome.isEmpty, sectionChrome: chrome,
            typeAt: { index in
                if index < headerRows { return .header }
                if index == footerRow { return .footer }
                return rows.rowID(index - headerRows).map { .content(id: $0) } ?? .unselectable
            },
            make: { index in
                if index < headerRows, let headerBuffer {
                    let header = LazyListRowContent(buffer: headerBuffer, badge: nil)
                    header.sectionSeparator = (.top, separator.top, separator.topTint)
                    return header
                }
                if index == footerRow, let footerBuffer { return LazyListRowContent(buffer: footerBuffer, badge: nil) }
                let content = rows.make(index - headerRows)
                if index == lastItem { content.sectionSeparator = (.bottom, separator.bottom, separator.bottomTint) }
                return content
            })
        source.sectionOutlines = (rowsContent as? any OutlineRowActivating).map { [$0] } ?? []
        return source
    }
}
