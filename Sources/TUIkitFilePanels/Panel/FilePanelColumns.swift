//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelColumns.swift
//
//  The columns of a file panel's table, and the path bar above it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitChrome
import TUIkitFoundation
import TUIkitTables

/// The four columns a file panel lists a folder's items in, as a macOS panel's
/// list view has them: Name, Size, Date Modified and Kind. Each sorts by its
/// own value (a click on its header, or the table's sort keys); folders stay
/// first whatever the order (``FileBrowser/arrange(_:showsHiddenFiles:sortOrder:)``).
@MainActor
enum FilePanelColumns {
    /// The columns, the name taking whatever width the others leave.
    @TableColumnBuilder<FileEntry, KeyPathComparator<FileEntry>>
    static var all: some TableColumnContent<FileEntry, KeyPathComparator<FileEntry>> {
        TableColumn(
            LocalizationService.shared.string(for: LocalizationKey.Label.name), sortUsing: FileBrowser.nameOrder
        ) { entry in
            nameCell(entry)
        }
        TableColumn(
            LocalizationService.shared.string(for: LocalizationKey.FilePanel.columnSize),
            sortUsing: KeyPathComparator(\FileEntry.sortSize)
        ) { entry in
            Text(entry.sizeText)
        }
        .width(9)
        .alignment(.trailing)
        TableColumn(
            LocalizationService.shared.string(for: LocalizationKey.FilePanel.columnDateModified),
            sortUsing: KeyPathComparator(\FileEntry.sortDate)
        ) { entry in
            Text(entry.modifiedText)
        }
        .width(20)
        TableColumn(
            LocalizationService.shared.string(for: LocalizationKey.FilePanel.columnKind),
            sortUsing: KeyPathComparator(\FileEntry.kind)
        ) { entry in
            Text(entry.kind)
        }
        .width(min: 6, ideal: 14, max: 18)
    }

    /// An item's name: a folder's bold and ending in a slash. Typing finds it
    /// by the name alone, without the slash.
    private static func nameCell(_ entry: FileEntry) -> some View {
        Text(entry.displayName)
            .bold(entry.isFolder)
            .typeSelectEquivalent(entry.name)
    }
}

/// The path of the folder a panel shows, with a `..` to click to the folder
/// above (← and Backspace are its keys).
struct FilePanelPathBar: View {
    let browser: FileBrowser

    /// The folder the path abbreviates as `~`.
    let home: URL

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "..")
                .foregroundStyle(browser.isAtRoot ? .palette.foregroundTertiary : .palette.accent)
                .onTapGesture { browser.goUp() }
                .help(LocalizationService.shared.string(for: LocalizationKey.FilePanel.enclosingFolder))
            Text(Self.displayPath(of: browser.directory, home: home))
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    /// `folder`'s path as a shell prompt writes it: the home folder as `~`.
    nonisolated static func displayPath(of folder: URL, home: URL) -> String {
        let path = folder.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard homePath.count > 1 else { return path }
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
