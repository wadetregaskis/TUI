//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelListView.swift
//
//  A file panel's list view: the folder's items in a table, as an outline
//  whose folders open in place.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation
import TUITables

/// The folder's items in a ``Table`` — Name, Size, Date Modified and Kind, as
/// many as its width has room for (``FilePanelColumns/shown(inWidth:)``) —
/// drawn as an outline whose folders open in place.
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

    /// The table, with one selection binding or the other, `width` cells wide:
    /// an outline, whose folders open in place, however many rows the folder
    /// has — a table's outline costs what the rows it draws cost
    /// (decisions B-FP2-5).
    @ViewBuilder private func table(width: Int) -> some View {
        Group {
            if allowsMultipleSelection {
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
