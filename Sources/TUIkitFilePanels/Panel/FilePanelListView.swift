//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelListView.swift
//
//  A file panel's list view: the folder's items in a table, as an outline
//  whose folders open in place.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation
import TUIkitTables

/// The folder's items in a ``Table`` — Name, Size, Date Modified and Kind, as
/// many as its width has room for (``FilePanelColumns/shown(inWidth:)``) —
/// drawn as an outline whose folders open in place, up to
/// ``outlineRowLimit`` rows.
///
/// The selection bindings are the panel's, which refuse a dimmed item; the
/// keys and the primary action the panel puts round it.
struct FilePanelListView: View {
    let browser: FileBrowser

    /// Whether the table takes ``selection`` rather than ``singleSelection``.
    let allowsMultipleSelection: Bool

    /// The items selected, where several may be chosen.
    let selection: Binding<Set<URL>>

    /// The item selected, where one may be chosen.
    let singleSelection: Binding<URL?>

    var body: some View {
        // A reader is greedy: the table has the rest of the sheet's height,
        // however few the rows, and the panel is the same size from one
        // folder to the next.
        GeometryReader { proxy in
            table(width: proxy.size.width)
        }
    }

    /// The table, with one selection binding or the other, `width` cells wide.
    ///
    /// An outline, whose folders open in place, up to ``outlineRowLimit``
    /// rows; past it, the rows alone.
    @ViewBuilder private func table(width: Int) -> some View {
        Group {
            if browser.rows.count > Self.outlineRowLimit {
                flatTable(width: width)
            } else if allowsMultipleSelection {
                Table(browser.rows, children: \.children, selection: selection, sortOrder: sortOrder) {
                    FilePanelColumns.fitting(width, browser: browser)
                }
                .tableEmptyPlaceholder(emptyText)
            } else {
                Table(browser.rows, children: \.children, selection: singleSelection, sortOrder: sortOrder) {
                    FilePanelColumns.fitting(width, browser: browser)
                }
                .tableEmptyPlaceholder(emptyText)
            }
        }
        // Inset, not bordered: the panel's box is the table's border.
        .tableStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The most rows the list view draws as an outline. A table's outline is
    /// worked out afresh for every row on every pass, which a flat table is
    /// not: a frame of a folder of 20,000 files took 87 ms as an outline and
    /// 6.5 ms flat in a debug build. A folder of more is drawn flat, its
    /// folders opened by Return alone, until the outline's cost stops growing
    /// with the rows (decisions B-FP2-5).
    static let outlineRowLimit = 5_000

    /// The table with no outline, for a folder of more than
    /// ``outlineRowLimit`` rows.
    @ViewBuilder private func flatTable(width: Int) -> some View {
        if allowsMultipleSelection {
            Table(browser.rows, selection: selection, sortOrder: sortOrder) {
                FilePanelColumns.fitting(width, browser: browser)
            }
            .tableEmptyPlaceholder(emptyText)
        } else {
            Table(browser.rows, selection: singleSelection, sortOrder: sortOrder) {
                FilePanelColumns.fitting(width, browser: browser)
            }
            .tableEmptyPlaceholder(emptyText)
        }
    }

    /// The table's order, which the browser keeps.
    private var sortOrder: Binding<[KeyPathComparator<FileEntry>]> {
        let browser = browser
        return Binding(get: { browser.sortOrder }, set: { browser.sortOrder = $0 })
    }

    /// What the table says when it has no rows (``FileBrowser/emptyText``).
    private var emptyText: String { browser.emptyText }
}

extension FileBrowser {
    /// What a view of the folder says when it has no rows: why.
    var emptyText: String {
        switch state {
        case .loading:
            LocalizationService.shared.string(for: LocalizationKey.FilePanel.loading)
        case .loaded:
            LocalizationService.shared.string(for: LocalizationKey.FilePanel.emptyFolder)
        case .failed(let failure):
            String(
                format: LocalizationService.shared.string(for: LocalizationKey.FilePanel.unreadableFolder),
                failure.folderName) + " " + failure.reason
        }
    }
}
