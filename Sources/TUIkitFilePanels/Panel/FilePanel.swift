//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanel.swift
//
//  The open and save panel TUIkit draws for `fileImporter`, `fileMover` and
//  `fileExporter`: a folder's items in a table, the folder's path above it,
//  a name field to save, and the buttons that end it below — SwiftUI's
//  system panels, adapted to a terminal.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation
import TUIkitPresentation
import TUIkitTables

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

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
/// - `/` turns the path bar into a field to type a path in, which Tab
///   completes and Return goes to, as at a shell prompt;
/// - Escape cancels (or closes that field).
/// Every one of them is also a click: a double-click opens or chooses, the
/// `..` button goes up, and the buttons are buttons.
///
/// To save, a name field sits above the folder and takes the focus first;
/// Return in it saves. A file of a type the panel saves as is not dimmed, and
/// Return on it puts its name in the field. Saving over an existing file asks
/// first; a name that is an existing folder cannot be saved under.
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

    /// The name typed in a save panel's field.
    @State private var name: String

    /// The file a save would replace, while the panel asks whether to.
    @State private var replacing: URL?

    /// The path typed in the go-to field, while it is open (`/` opens it).
    @State private var typedPath: String?

    /// Which of the panel's fields holds the focus, where the panel moves it:
    /// to the name field when Return puts a file's name there, to the go-to
    /// field when `/` opens it, and back to the folder when it closes.
    @FocusState private var focus: Field?

    /// The panel's fields, for ``focus``.
    private enum Field: Hashable {
        case name, path, rows
    }

    init(request: FilePanelRequest, finish: @escaping (FilePanelOutcome) -> Void) {
        self.request = request
        self.finish = finish
        _browser = State(
            initialValue: FileBrowser(
                directory: request.startDirectory, rule: request.rule, showsHiddenFiles: request.showsHiddenFiles))
        _name = State(initialValue: request.defaultFilename ?? "")
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
            content: replaceAlert(on: panelContent),
            footer: footer
        )
        .task(id: browser.refreshKey) { await browser.refresh() }
    }

    /// What the box holds: the message, a save panel's name field, the path
    /// and the folder's items.
    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = request.message {
                Text(message).foregroundStyle(.palette.foregroundSecondary)
            }
            if request.saveContentTypes != nil {
                FilePanelNameField(
                    label: request.filenameLabel
                        ?? LocalizationService.shared.string(for: LocalizationKey.FilePanel.saveAs),
                    name: $name
                )
                .focused($focus, equals: .name)
                .onSubmit { confirm() }
            }
            if typedPath != nil {
                FilePanelGoToField(path: Binding(get: { typedPath ?? "" }, set: { typedPath = $0 }))
                    .focused($focus, equals: .path)
                    .onSubmit { goToTypedPath() }
                    .onKeyPress(.tab) {
                        completeTypedPath()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        closeGoToField()
                        return .handled
                    }
            } else {
                FilePanelPathBar(browser: browser, home: request.homeDirectory)
            }
            rows
        }
    }

    /// The alert a save asks before replacing a file, on `content`: inside
    /// the box, not on it, since the box takes the sheet's size and clears it
    /// for what it holds, and an alert presented where the sheet's size is
    /// still in the environment took that size too.
    private func replaceAlert(on content: some View) -> some View {
        content.alert(
            replaceTitle, isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })
        ) {
            Button(LocalizationService.shared.string(for: LocalizationKey.Button.cancel), role: .cancel) {}
            Button(LocalizationService.shared.string(for: LocalizationKey.Button.replace), role: .destructive) {
                if let replacing { finish(.chose([replacing], ending)) }
            }
        } message: {
            Text(
                String(
                    format: LocalizationService.shared.string(for: LocalizationKey.FilePanel.replaceMessage),
                    DirectoryListing.displayName(of: browser.directory)))
        }
    }

    /// The replace alert's title, naming the file.
    private var replaceTitle: String {
        String(
            format: LocalizationService.shared.string(for: LocalizationKey.FilePanel.replaceTitle),
            replacing?.lastPathComponent ?? "")
    }

    // MARK: - The folder's items

    /// The table of the folder's items, one selection binding or the other.
    @ViewBuilder private var rows: some View {
        Group {
            if request.allowsMultipleSelection {
                Table(browser.rows, selection: selectable, sortOrder: sortOrder) {
                    FilePanelColumns.all
                }
                .tableEmptyPlaceholder(emptyText)
            } else {
                Table(browser.rows, selection: selectableSingle, sortOrder: sortOrder) {
                    FilePanelColumns.all
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
        .onKeyPress("/") {
            openGoToField()
            return .handled
        }
        .focused($focus, equals: .rows)
        // Escape among them: items a presented sheet's content declares take
        // the place of the sheet's own Escape item, and without one here a
        // page's "⎋ back" outside the sheet answered Escape, taking the page
        // away from under the panel (`StatusBarState.registerSectionItems`).
        .statusBarItems {
            StatusBarItem(
                shortcut: Shortcut.escape, label: LocalizationService.shared.string(for: LocalizationKey.StatusBar.cancel)
            ) {
                finish(.cancelled(ending))
            }
            StatusBarItem(
                shortcut: Shortcut.arrowLeft,
                label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusEnclosingFolder))
            StatusBarItem(
                shortcut: "~", label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusHome))
            StatusBarItem(
                shortcut: "/", label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusGoTo))
        }
    }

    /// The selection, through a binding that refuses an item that can be
    /// neither chosen nor opened (``FileEntry/isDimmed``): the cursor still
    /// lands on one, as on a macOS panel, but Space does not select it.
    ///
    /// Not `.selectionDisabled()` on the rows, which would also take the
    /// cursor past them: that needs the table's row builder, which builds
    /// every row's traits on every frame — 195 ms a frame for a folder of
    /// 20,000 items in a debug build, where the data form takes 22.
    private var selectable: Binding<Set<URL>> {
        Binding(
            get: { selection },
            set: { urls in selection = urls.filter { !dimmedURLs.contains($0) } })
    }

    /// ``selectable``, for a single selection.
    private var selectableSingle: Binding<URL?> {
        Binding(
            get: { singleSelection },
            set: { url in singleSelection = url.flatMap { dimmedURLs.contains($0) ? nil : $0 } })
    }

    /// The dimmed rows' URLs: read only when the selection changes.
    private var dimmedURLs: Set<URL> {
        Set(browser.rows.lazy.filter(\.isDimmed).map(\.url))
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
                finish(.cancelled(ending))
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
        if request.saveContentTypes != nil { return saveDestination != nil }
        return !confirmable.isEmpty || openableSelection != nil
    }

    /// Where a save panel saves now: the folder shown and the name resolved
    /// (``SaveName/resolve(_:contentTypes:)``); `nil` for a name no file can
    /// have, or one that is a folder's in the folder shown.
    private var saveDestination: URL? {
        guard let types = request.saveContentTypes, let resolved = SaveName.resolve(name, contentTypes: types)
        else { return nil }
        let destination = browser.directory.appendingPathComponent(resolved)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return nil
        }
        return destination
    }

    /// The one folder selected, when the selection is one folder that cannot
    /// be chosen: the confirmation button opens it.
    private var openableSelection: URL? {
        let entries = selectedEntries
        guard entries.count == 1, let entry = entries.first, entry.isFolder, !entry.isChoosable else { return nil }
        return entry.url
    }

    /// Where the panel is now, for the presenter to keep.
    private var ending: FilePanelEnding {
        FilePanelEnding(directory: browser.directory, showsHiddenFiles: browser.showsHiddenFiles)
    }

    /// The URL the caller is handed for `entry`.
    private func chosenURL(_ entry: FileEntry) -> URL {
        entry.chosenURL(resolvingLinks: request.resolvesSymbolicLinks)
    }

    /// The confirmation button.
    private func confirm() {
        if request.saveContentTypes != nil {
            save()
            return
        }
        if let folder = openableSelection {
            browser.open(folder)
            return
        }
        let urls = confirmable
        guard !urls.isEmpty else { return }
        finish(.chose(urls, ending))
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
        // To save, a file is a name to save under, not a choice.
        if request.saveContentTypes != nil {
            if let entry = entries.first(where: \.isChoosable) {
                name = entry.name
                focus = .name
            }
            return
        }
        let chosen = entries.filter(\.isChoosable).map(chosenURL)
        guard !chosen.isEmpty, request.allowsMultipleSelection || chosen.count == 1 else { return }
        finish(.chose(chosen, ending))
    }

    /// Saves under the name typed, in the folder shown — once the user says
    /// to replace the file already there, if there is one.
    private func save() {
        guard let destination = saveDestination else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            replacing = destination
            return
        }
        finish(.chose([destination], ending))
    }

    // MARK: - Going to a typed path

    /// Opens the go-to field on the folder shown, written as the path bar
    /// writes it, and moves the focus there.
    private func openGoToField() {
        let shown = FilePanelPathBar.displayPath(of: browser.directory, home: request.homeDirectory)
        typedPath = shown.hasSuffix("/") ? shown : shown + "/"
        focus = .path
    }

    /// Closes the go-to field and gives the folder the focus again.
    private func closeGoToField() {
        typedPath = nil
        focus = .rows
    }

    /// Return in the go-to field: a folder opens; a file opens the folder it
    /// is in, and to save gives its name to the name field; a path to
    /// nothing leaves the field open to be mended.
    private func goToTypedPath() {
        guard let typed = typedPath else { return }
        let url = PathCompletion.resolve(typed, relativeTo: browser.directory, home: request.homeDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            browser.open(url)
        } else {
            browser.open(url.deletingLastPathComponent())
            if request.saveContentTypes != nil { name = url.lastPathComponent }
        }
        closeGoToField()
    }

    /// Tab in the go-to field: the path's last part completed, as a shell
    /// completes it.
    private func completeTypedPath() {
        guard let typed = typedPath else { return }
        typedPath = PathCompletion.complete(typed, relativeTo: browser.directory, home: request.homeDirectory)
    }
}
