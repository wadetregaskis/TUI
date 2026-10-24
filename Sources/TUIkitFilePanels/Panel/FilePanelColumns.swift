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
///
/// A narrow panel gives way from the right: Kind goes first, then Date
/// Modified, then Size, each where the name would otherwise have fewer than
/// ``nameRoom`` cells beside it (``shown(inWidth:)``). A name is what a row is
/// told by; with every column kept at its width whatever the width, a panel
/// 64 columns wide showed each name in four cells, `fil…`, beside eighteen of
/// `Plain Text Docum…`, and one 50 wide a bare `…`.
@MainActor
enum FilePanelColumns {
    /// The cells a name keeps before a column beside it gives way.
    static let nameRoom = 20

    /// The widths of the columns beside the name, in the order they stay:
    /// Size's, Date Modified's, and the width Kind starts at.
    static let besideName = [9, 20, 14]

    /// What a table draws around its columns besides their widths: an inset
    /// at each side, and the spacing between two columns (`Table`'s inset
    /// style and default spacing), counted generously.
    private static let inset = 4
    private static let spacing = 2

    /// How many of the columns beside the name — Size, Date Modified, Kind,
    /// in that order — a table `width` cells wide shows, each where the name
    /// keeps ``nameRoom`` cells beside it and the ones before it.
    static func shown(inWidth width: Int) -> Int {
        var used = inset + nameRoom
        var count = 0
        for columnWidth in besideName {
            used += spacing + columnWidth
            guard used <= width else { break }
            count += 1
        }
        return count
    }

    /// The columns a table `width` cells wide shows: the name always,
    /// starting at ``nameRoom`` and taking whatever width the others leave,
    /// and as many of the others as ``shown(inWidth:)`` says.
    @TableColumnBuilder<FileEntry, KeyPathComparator<FileEntry>>
    static func fitting(_ width: Int) -> some TableColumnContent<FileEntry, KeyPathComparator<FileEntry>> {
        let shown = shown(inWidth: width)
        TableColumn(
            LocalizationService.shared.string(for: LocalizationKey.Label.name), sortUsing: FileBrowser.nameOrder
        ) { entry in
            nameCell(entry)
        }
        .width(ideal: nameRoom)
        if shown >= 1 {
            TableColumn(
                LocalizationService.shared.string(for: LocalizationKey.FilePanel.columnSize),
                sortUsing: KeyPathComparator(\FileEntry.sortSize)
            ) { entry in
                cell(entry.sizeText, entry)
            }
            .width(besideName[0])
            .alignment(.trailing)
        }
        if shown >= 2 {
            TableColumn(
                LocalizationService.shared.string(for: LocalizationKey.FilePanel.columnDateModified),
                sortUsing: KeyPathComparator(\FileEntry.sortDate)
            ) { entry in
                cell(entry.modifiedText, entry)
            }
            .width(besideName[1])
        }
        if shown >= 3 {
            TableColumn(
                LocalizationService.shared.string(for: LocalizationKey.FilePanel.columnKind),
                sortUsing: KeyPathComparator(\FileEntry.kind)
            ) { entry in
                cell(entry.kind, entry)
            }
            .width(min: 6, ideal: besideName[2], max: 18)
        }
    }

    /// An item's name: a folder's bold and ending in a slash. Typing finds it
    /// by the name alone, without the slash.
    private static func nameCell(_ entry: FileEntry) -> some View {
        cell(entry.displayName, entry, bold: entry.isFolder)
            .typeSelectEquivalent(entry.name)
    }

    /// A cell's text, in the faint tier where the row is dimmed
    /// (``FileEntry/isDimmed``), as a disabled row of a table draws.
    private static func cell(_ text: String, _ entry: FileEntry, bold: Bool = false) -> Text {
        let drawn = Text(text).bold(bold)
        return entry.isDimmed ? drawn.foregroundStyle(.palette.foregroundTertiary) : drawn
    }
}

/// The path of the folder a panel shows, after a button to the folder above.
struct FilePanelPathBar: View {
    let browser: FileBrowser

    /// The folder the path abbreviates as `~`.
    let home: URL

    /// The enclosing-folder button's glyph: ↰ (U+21B0), an arrow up and to
    /// the leading side, as a macOS panel's toolbar would show "enclosing
    /// folder". Neutral East Asian width, so one cell everywhere; a new
    /// chrome glyph, so a width-corpus row (`chrome_enclosing_folder`).
    static let enclosingFolderSymbol = "\u{21B0}"

    var body: some View {
        HStack(spacing: 1) {
            enclosingFolderButton
            Text(Self.displayPath(of: browser.directory, home: home))
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    /// The button to the folder above: in the link style, so the glyph in the
    /// accent and in its own cell, with no cells kept for a focus marker it
    /// never shows; lifted under the pointer, and dimmed at the root, which
    /// has no folder above it. Not a Tab stop, as a macOS panel's toolbar buttons
    /// are not in its key view loop: its keys are ← and Backspace in the
    /// folder's rows. macOS's ⌘↑ cannot be offered, since a key press never
    /// carries Command (`KeyPress.modifiers`).
    private var enclosingFolderButton: some View {
        let browser = browser
        return Button {
            browser.goUp()
        } label: {
            Text(verbatim: Self.enclosingFolderSymbol)
        }
        .buttonStyle(.link)
        .focusable(false)
        .disabled(browser.isAtRoot)
        .help(LocalizationService.shared.string(for: LocalizationKey.FilePanel.enclosingFolder))
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
