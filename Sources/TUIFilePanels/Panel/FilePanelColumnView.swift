//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelColumnView.swift
//
//  A file panel's column view: Finder's Miller columns, a list of each folder
//  on the way to the one shown, side by side, the folder shown the last.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation
import TUILists

/// What a file panel's views can hold the focus in: the panel moves it among
/// them (`FilePanel`).
enum FilePanelField: Hashable {
    /// A save panel's name field.
    case name
    /// The go-to field `/` opens.
    case path
    /// The list view's table.
    case rows
    /// The column view's column of the folder at this path.
    case column(String)
}

/// The folder's items as Finder's column view shows them: a column for each
/// folder from the path control's first — the root, or the home folder — to
/// the folder shown, as many of the last as fit at ``minimumColumnWidth``
/// cells each, each a ``List`` of the folder's items; and after them, while a
/// file is selected, a column previewing it (``FilePanelPreview``).
///
/// The last column is the folder shown, and its selection is the panel's. In
/// the others the folder on the way is the one selected; choosing another row
/// there goes to it — a folder becomes the folder shown, a file is selected
/// in its own folder — and the columns after it go, as Finder's do. The
/// columns keep their cursors while they show, so ← back to a column finds
/// its cursor on the folder that was opened from it.
struct FilePanelColumnView: View {
    let browser: FileBrowser

    /// The folder the path abbreviates as `~`, where the columns start when
    /// the folder shown is in it.
    let home: URL

    /// Whether the last column takes ``selection`` rather than
    /// ``singleSelection``.
    let allowsMultipleSelection: Bool

    /// The items selected, where several may be chosen.
    let selection: Binding<Set<URL>>

    /// The item selected, where one may be chosen.
    let singleSelection: Binding<URL?>

    /// Where the panel's focus is, each column bound to its folder's path.
    let focus: FocusState<FilePanelField?>.Binding

    /// The narrowest a column is drawn, in cells: a name of about twenty
    /// cells, as the list view keeps one (``FilePanelColumns/nameRoom``).
    static let minimumColumnWidth = 24

    var body: some View {
        // Greedy, as the list view's reader is: the columns take the rest of
        // the sheet, and the panel keeps its size from folder to folder.
        GeometryReader { proxy in
            columns(width: proxy.size.width)
        }
    }

    /// The folders that have columns, from the first the path control shows
    /// to the folder shown: as many of the last as fit in `width` cells, a
    /// rule between each two.
    static func folders(of folder: URL, home: URL, width: Int) -> [String] {
        let all = FilePanelPathSegment.all(of: folder, home: home).map(\.path)
        let fit = max(1, (width + 1) / (minimumColumnWidth + 1))
        return Array(all.suffix(fit))
    }

    /// The columns, each the same kind of view whether or not it is the
    /// last, so a column keeps its identity — its cursor, and the focus — as
    /// folders open after it and close again.
    @ViewBuilder private func columns(width: Int) -> some View {
        // The file selected, previewed in a column of its own after the last
        // (`FilePanelPreview`), which the folders' columns make room for.
        let previewed = previewedFile
        let previewWidth = previewed == nil ? 0 : Self.previewWidth(in: width)
        let foldersWidth = previewed == nil ? width : max(Self.minimumColumnWidth, width - previewWidth - 1)
        let folders = Self.folders(of: browser.directory, home: home, width: foldersWidth)
        // Each column but the last at an even share; the last takes the rest.
        let share = max(1, (foldersWidth - (folders.count - 1)) / folders.count)
        HStack(spacing: 0) {
            ForEach(Array(folders.enumerated()), id: \.element) { index, path in
                if index > 0 {
                    Divider()
                }
                let isLast = index == folders.count - 1
                column(path, after: index > 0 ? folders[index - 1] : nil, next: isLast ? nil : folders[index + 1])
                    .frame(minWidth: share, maxWidth: isLast ? .infinity : .fixed(share), maxHeight: .infinity)
            }
            if let previewed {
                Divider()
                FilePanelPreview(entry: previewed)
                    .frame(width: previewWidth)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// The file selected in the folder shown, alone: what the preview column
    /// shows. A folder opens a column of its own instead, and several items
    /// selected have no one preview.
    private var previewedFile: FileEntry? {
        let url = allowsMultipleSelection ? (selection.wrappedValue.count == 1 ? selection.wrappedValue.first : nil)
            : singleSelection.wrappedValue
        guard let url else { return nil }
        return browser.rows.first { $0.url == url && !$0.isFolder && !$0.isPlaceholder }
    }

    /// The preview column's width in a column view `width` cells wide: a
    /// third of it, and never narrower than a folder's column.
    static func previewWidth(in width: Int) -> Int {
        max(minimumColumnWidth, width / 3)
    }

    /// The column of the folder at `path`, which comes `after` another and is
    /// followed by the folder `next` on the way, unless it is the last.
    ///
    /// Bound to the panel's focus as its folder's column. As it appears, it
    /// takes the focus from the column before it — the folder was opened from
    /// there, by Return or a click — so the keys follow into it, as Finder's
    /// do; a folder reached from the path control or the go-to field leaves
    /// the focus where it was.
    @ViewBuilder
    private func column(_ path: String, after previous: String?, next: String?) -> some View {
        let focus = focus
        Group {
            if allowsMultipleSelection {
                List(items(of: path), selection: multipleSelection(of: path, next: next)) { entry in
                    FilePanelColumns.nameCell(entry, browser: browser)
                }
                .listEmptyPlaceholder(emptyText(of: path))
            } else {
                List(items(of: path), selection: singleSelection(of: path, next: next)) { entry in
                    FilePanelColumns.nameCell(entry, browser: browser)
                }
                .listEmptyPlaceholder(emptyText(of: path))
            }
        }
        .listStyle(.plain)
        .modifier(RevealingFolderOnTheWay(target: next.flatMap { next in
            items(of: path).first { $0.url.standardizedFileURL.path == next }?.url
        }))
        .focused(focus, equals: .column(path))
        .onAppear {
            if let previous, focus.wrappedValue == .column(previous) { focus.wrappedValue = .column(path) }
        }
        .task(id: path) { await loadIfNeeded(path) }
    }

    /// The items of the folder at `path`: the folder shown's rows, or a
    /// folder on the way's, once read.
    private func items(of path: String) -> [FileEntry] {
        path == browser.directory.path ? browser.rows : browser.folderRows[path] ?? []
    }

    /// What a column says with no items: why, for the folder shown; else that
    /// it is being read, or is empty.
    private func emptyText(of path: String) -> String {
        if path == browser.directory.path { return browser.emptyText }
        return LocalizationService.shared.string(
            for: browser.folderRows[path] == nil ? LocalizationKey.FilePanel.loading : LocalizationKey.FilePanel.emptyFolder)
    }

    /// Reads a folder on the way, unless it is the folder shown, which the
    /// panel reads.
    private func loadIfNeeded(_ path: String) async {
        guard path != browser.directory.path else { return }
        await browser.loadFolder(URL(fileURLWithPath: path, isDirectory: true))
    }

    /// The last column's selection is the panel's; another's is the folder on
    /// the way, `next` (``onTheWay(in:next:folder:)``).
    private func singleSelection(of path: String, next: String?) -> Binding<URL?> {
        guard let next else { return singleSelection }
        let way = onTheWay(in: items(of: path), next: next, folder: path)
        return Binding(get: { way.wrappedValue }, set: { way.wrappedValue = $0 })
    }

    /// ``singleSelection(of:next:)``, where several may be chosen.
    private func multipleSelection(of path: String, next: String?) -> Binding<Set<URL>> {
        guard let next else { return selection }
        let way = onTheWay(in: items(of: path), next: next, folder: path)
        return Binding(
            get: { way.wrappedValue.map { [$0] } ?? [] },
            set: { urls in way.wrappedValue = urls.first { $0 != way.wrappedValue } ?? urls.first })
    }

    /// A column's selection: the row of the folder on the way, `next`; and a
    /// choice of another row goes there — a folder becomes the folder shown,
    /// a file is selected in the folder it is in, `folder`.
    private func onTheWay(in rows: [FileEntry], next: String, folder: String) -> Binding<URL?> {
        let browser = browser
        let selection = selection
        let singleSelection = singleSelection
        let multiple = allowsMultipleSelection
        return Binding(
            get: { rows.first { $0.url.standardizedFileURL.path == next }?.url },
            set: { url in
                guard let url, let entry = rows.first(where: { $0.url == url }) else { return }
                if entry.isFolder {
                    browser.open(entry.url)
                } else {
                    browser.open(URL(fileURLWithPath: folder, isDirectory: true))
                    guard !entry.isDimmed else { return }
                    if multiple {
                        selection.wrappedValue = [url]
                    } else {
                        singleSelection.wrappedValue = url
                    }
                }
            })
    }
}

/// Scrolls a column to the row of the folder on the way, as Finder's column
/// view shows each folder's selected row — as the column's items arrive, and
/// whenever the folder on the way changes: in a folder of thousands, the
/// column would otherwise show its top, the folder opened from it out of
/// sight. Between those, the user scrolls it.
private struct RevealingFolderOnTheWay: ViewModifier {
    /// The folder on the way's row, once the column lists it.
    let target: URL?

    /// The row the column shows, as its scroll position.
    @State private var shown: URL?

    func body(content: Content) -> some View {
        content
            .scrollPosition(id: $shown, anchor: .center)
            .onChange(of: target, initial: true) { _, target in
                if let target { shown = target }
            }
    }
}
