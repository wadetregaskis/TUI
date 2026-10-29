//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelFolderView.swift
//
//  A file panel's folder in the view chosen: the list, with the preview pane
//  behind a splitter after it while the preview shows, or the columns.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation
import TUINavigation

/// The folder's items in the view chosen: the list view (``FilePanelListView``)
/// with, while the preview shows, the preview pane after it behind a splitter
/// the user drags or moves with ← and → (``HSplitView``), as Finder's list
/// view has one; or the column view (``FilePanelColumnView``), whose preview
/// is a column of its own.
///
/// The selection bindings are the panel's, which refuse a dimmed item; the
/// keys and the primary action the panel puts round it.
struct FilePanelFolderView: View {
    let browser: FileBrowser

    /// How the folder is shown.
    let viewMode: FilePanelViewMode

    /// The folder the path abbreviates as `~`, where the columns start.
    let home: URL

    /// Whether the view takes ``selection`` rather than ``singleSelection``.
    let allowsMultipleSelection: Bool

    /// The items selected, where several may be chosen.
    let selection: Binding<Set<URL>>

    /// The item selected, where one may be chosen.
    let singleSelection: Binding<URL?>

    /// Where the panel's focus is: the list's table and the columns are bound
    /// to it.
    let focus: FocusState<FilePanelField?>.Binding

    /// Whether the preview shows (``FilePanelPreviewVisibility``).
    let showsPreview: Bool

    /// The folder's width in cells, which the pane starts at a share of.
    let width: Int

    var body: some View {
        switch viewMode {
        case .list:
            // A split whether or not the pane shows, the pane its second child
            // only while it does: the table is the split's first child either
            // way, so opening and closing the pane keeps its cursor, its
            // scroll and the focus, where moving it in and out of a split
            // would make it a new table.
            HSplitView {
                list
                    .frame(minWidth: FilePanelColumns.width(showing: 0), maxHeight: .infinity)
                if showsPreview {
                    FilePanelPreviewPane(entry: selectedEntry)
                        .frame(
                            minWidth: FilePanelColumnView.minimumColumnWidth,
                            idealWidth: FilePanelPreviewVisibility.paneWidth(in: width), maxHeight: .infinity)
                }
            }
        case .columns:
            // The columns keep their place from folder to folder: each is a
            // folder's, and keeps its cursor while it shows.
            FilePanelColumnView(
                browser: browser, home: home, allowsMultipleSelection: allowsMultipleSelection,
                selection: selection, singleSelection: singleSelection, focus: focus, showsPreview: showsPreview)
        }
    }

    /// The list view's table.
    private var list: some View {
        FilePanelListView(
            browser: browser, allowsMultipleSelection: allowsMultipleSelection, selection: selection,
            singleSelection: singleSelection)
            // A folder is a new table: its cursor starts on the first row and
            // its scroll at the top, rather than where the last folder's were.
            .id(browser.directory)
            .focused(focus, equals: .rows)
    }

    /// The item selected, alone, which the pane previews; `nil` for none, or
    /// for several, which have no one preview.
    private var selectedEntry: FileEntry? {
        let urls = allowsMultipleSelection ? selection.wrappedValue : Set(singleSelection.wrappedValue.map { [$0] } ?? [])
        guard urls.count == 1, let entry = browser.entries(for: urls).first, !entry.isPlaceholder else { return nil }
        return entry
    }
}
