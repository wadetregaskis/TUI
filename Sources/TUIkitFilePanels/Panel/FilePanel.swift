//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanel.swift
//
//  The open panel TUIkit draws for `fileImporter`: a folder's items in a
//  table, the folder's path above it, and the buttons that end it below —
//  SwiftUI's system panel, adapted to a terminal.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation
import TUIkitPresentation
import TUIkitTables

/// The panel a file panel modifier presents in a sheet.
///
/// Composed of TUIkit's own controls, as ``ColorPickerPanel`` stands in for
/// the system's colour panel: a dialog's box titled for what is being chosen,
/// the folder's path, its items in a ``Table`` (Name, Size, Date Modified,
/// Kind; sortable by any, folders always first), and below them the hidden-
/// files switch and the Cancel and confirmation buttons.
///
/// The keys are a terminal file browser's:
/// - ↑ and ↓ move through the folder, and typing a name's first letters
///   finds it (the table's type-select);
/// - Return on a folder opens it; on a file, chooses it — or the whole
///   selection, when the cursor is in it;
/// - Space selects the item under the cursor, adding it to the selection
///   where several may be chosen;
/// - ← or Backspace goes to the enclosing folder, and `~` to the home folder;
/// - Escape cancels.
/// Every one of them is also a click: a double-click opens or chooses, the
/// `..` button goes up, and the buttons are buttons.
struct FilePanel: View {
    let request: FilePanelRequest

    /// Called once, when the panel ends.
    let finish: (FilePanelOutcome) -> Void

    /// The folder shown and what it holds: one per presentation.
    @State private var browser: FileBrowser

    /// The items selected, where several may be chosen.
    @State private var selection: Set<URL> = []

    /// The item selected, where one may be chosen.
    @State private var singleSelection: URL?

    init(request: FilePanelRequest, finish: @escaping (FilePanelOutcome) -> Void) {
        self.request = request
        self.finish = finish
        _browser = State(
            initialValue: FileBrowser(
                directory: request.startDirectory, rule: request.rule, showsHiddenFiles: request.showsHiddenFiles))
    }

    var body: some View {
        // A dialog's box, as ``Dialog`` draws one, but with a body that does
        // not scroll: the table is the part that scrolls, and it takes the
        // sheet's whole height, where a dialog's body is as tall as its
        // content and scrolls past the sheet's.
        makeContainer(
            title: request.title,
            config: ContainerConfig(
                titleColor: .palette.accent, padding: EdgeInsets(horizontal: 1, vertical: 0),
                footerAlignment: .trailing),
            content: VStack(alignment: .leading, spacing: 0) {
                FilePanelPathBar(browser: browser, home: request.homeDirectory)
                rows
            },
            footer: footer
        )
        .task(id: browser.refreshKey) { await browser.refresh() }
    }

    // MARK: - The folder's items

    /// The table of the folder's items, one selection binding or the other.
    @ViewBuilder private var rows: some View {
        Group {
            if request.allowsMultipleSelection {
                Table(of: FileEntry.self, selection: $selection, sortOrder: sortOrder) {
                    FilePanelColumns.all
                } rows: {
                    rowContent
                }
                .tableEmptyPlaceholder(emptyText)
            } else {
                Table(of: FileEntry.self, selection: $singleSelection, sortOrder: sortOrder) {
                    FilePanelColumns.all
                } rows: {
                    rowContent
                }
                .tableEmptyPlaceholder(emptyText)
            }
        }
        // Inset, not bordered: the panel's box is the table's border.
        .tableStyle(.inset)
        // The rest of the sheet's height, however few the rows: the panel is the
        // same size from one folder to the next.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A folder is a new table: its cursor starts on the first row and its
        // scroll at the top, rather than at the place the last folder's were.
        .id(browser.directory)
        .contextMenu(forSelectionType: URL.self) { _ in
        } primaryAction: { urls in
            activate(urls)
        }
        .onKeyPress(keys: [.leftArrow, .delete], phases: [.down, .repeat]) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            browser.goUp()
            return .handled
        }
        .onKeyPress("~") {
            browser.open(request.homeDirectory)
            return .handled
        }
        .statusBarItems {
            StatusBarItem(
                shortcut: Shortcut.arrowLeft,
                label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusEnclosingFolder))
            StatusBarItem(
                shortcut: "~", label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusHome))
        }
    }

    /// Each item, a row that cannot be selected when it can be neither
    /// chosen nor opened: drawn dimmed, and passed over by the cursor.
    @TableRowBuilder<FileEntry> private var rowContent: some TableRowContent<FileEntry> {
        ForEach(browser.rows) { entry in
            TableRow(entry).selectionDisabled(!entry.isChoosable && !entry.isFolder)
        }
    }

    /// The table's order, which the browser keeps.
    private var sortOrder: Binding<[KeyPathComparator<FileEntry>]> {
        Binding(get: { browser.sortOrder }, set: { browser.sortOrder = $0 })
    }

    /// What the table says when it has no rows: why.
    private var emptyText: String {
        switch browser.state {
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

    // MARK: - The buttons

    @ViewBuilder private var footer: some View {
        HStack(spacing: 2) {
            Toggle(
                LocalizationService.shared.string(for: LocalizationKey.FilePanel.showHiddenFiles),
                isOn: Binding(get: { browser.showsHiddenFiles }, set: { browser.showsHiddenFiles = $0 }))
            Spacer()
            Button(LocalizationService.shared.string(for: LocalizationKey.Button.cancel)) {
                finish(.cancelled)
            }
            .keyboardShortcut(.cancelAction)
            Button(request.confirmationLabel) {
                confirm()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canConfirm)
        }
    }

    // MARK: - Choosing

    /// The items selected now, in the rows' order.
    private var selectedEntries: [FileEntry] {
        let chosen: Set<URL> = request.allowsMultipleSelection ? selection : Set(singleSelection.map { [$0] } ?? [])
        return browser.rows.filter { chosen.contains($0.url) }
    }

    /// What the confirmation button chooses now: the selection's choosable
    /// items, or else the folder shown when a folder may be chosen.
    private var confirmable: [URL] {
        let chosen = selectedEntries.filter(\.isChoosable).map(chosenURL)
        if !chosen.isEmpty { return chosen }
        return request.rule.choosesFolders && selectedEntries.isEmpty ? [browser.directory] : []
    }

    /// Whether the confirmation button does anything: it chooses, or it opens
    /// the one folder selected, as a macOS panel's Open opens a folder that
    /// cannot be chosen.
    private var canConfirm: Bool {
        !confirmable.isEmpty || openableSelection != nil
    }

    /// The one folder selected, when the selection is one folder that cannot
    /// be chosen: the confirmation button opens it.
    private var openableSelection: URL? {
        let entries = selectedEntries
        guard entries.count == 1, let entry = entries.first, entry.isFolder, !entry.isChoosable else { return nil }
        return entry.url
    }

    /// The URL the caller is handed for `entry`.
    private func chosenURL(_ entry: FileEntry) -> URL {
        entry.chosenURL(resolvingLinks: request.resolvesSymbolicLinks)
    }

    /// The confirmation button.
    private func confirm() {
        if let folder = openableSelection {
            browser.open(folder)
            return
        }
        let urls = confirmable
        guard !urls.isEmpty else { return }
        finish(.chose(urls, in: browser.directory))
    }

    /// Return or a double-click on `urls`: the rows under the cursor, or the
    /// selection when the cursor is in it. One folder opens; otherwise the
    /// items that can be chosen are.
    private func activate(_ urls: Set<URL>) {
        let entries = browser.rows.filter { urls.contains($0.url) }
        if entries.count == 1, let entry = entries.first, entry.isFolder {
            browser.open(entry.url)
            return
        }
        let chosen = entries.filter(\.isChoosable).map(chosenURL)
        guard !chosen.isEmpty, request.allowsMultipleSelection || chosen.count == 1 else { return }
        finish(.chose(chosen, in: browser.directory))
    }
}
