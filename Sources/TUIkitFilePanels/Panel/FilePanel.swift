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
/// the folder's path as a segmented path control (``FilePanelPathBar``), its
/// items in a ``Table`` (Name, Size, Date Modified,
/// Kind; sortable by any, folders always first; the last three giving way in
/// a narrow panel, ``FilePanelColumns``), and below them the hidden-files
/// switch and the Cancel and confirmation buttons.
///
/// The keys are a terminal file browser's:
/// - ↑ and ↓ move through the folder, and typing a name's first letters
///   finds it (the table's type-select);
/// - Return on a folder opens it; on a file, chooses it — or the whole
///   selection, when the cursor is in it;
/// - Space selects the item under the cursor, adding it to the selection
///   where several may be chosen;
/// - → opens a folder in place, in the outline the table is, and ← closes
///   it, or goes from an item to its folder's row (the outline's keys);
/// - Backspace goes to the enclosing folder, and `~` to the home folder;
/// - `/` turns the path bar into a field to type a path in, which Tab
///   completes and Return goes to, as at a shell prompt;
/// - Escape cancels (or closes that field).
/// Every one of them is also a click: a double-click opens or chooses, the
/// ↰ button before the path goes up, a segment of the path goes to its
/// folder, and the buttons are buttons. The focus starts in the folder's
/// rows, or to save in the name field.
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

    /// What an open panel's type pop-up has chosen (``FileTypeChoice``).
    @State private var typeChoice: FileTypeChoice

    /// Which of the panel's fields holds the focus, where the panel moves it:
    /// to the name field when Return puts a file's name there, to the go-to
    /// field when `/` opens it, and back to the folder when it closes.
    @FocusState private var focus: Field?

    /// The panel's fields, for ``focus``.
    private enum Field: Hashable {
        case name, path, rows
    }

    /// The control size in force, which decides how much room the panel's
    /// parts have between them (``spacing(controlSize:verticalSizeClass:)``).
    @Environment(\.controlSize) private var controlSize

    /// Whether the terminal is short of rows, where the panel stays dense.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(request: FilePanelRequest, finish: @escaping (FilePanelOutcome) -> Void) {
        self.request = request
        self.finish = finish
        _browser = State(
            initialValue: FileBrowser(
                directory: request.startDirectory, rule: request.rule, showsHiddenFiles: request.showsHiddenFiles))
        _name = State(initialValue: request.defaultFilename ?? "")
        _typeChoice = State(initialValue: request.initialTypeChoice)
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
    /// and the folder's items, with the room between them the control size
    /// gives (``spacing(controlSize:verticalSizeClass:)``).
    private var panelContent: some View {
        let spacing = Self.spacing(controlSize: controlSize, verticalSizeClass: verticalSizeClass)
        return VStack(alignment: .leading, spacing: spacing) {
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
            if let choices = request.typeChoices {
                FilePanelTypePopUp(
                    choices: choices, selection: request.saveContentTypes != nil ? formatChoice : filterChoice,
                    saves: request.saveContentTypes != nil)
            }
        }
        // The focus starts in the name field to save and in the folder to
        // open, as a macOS panel's does: not on the path control, the first
        // control in reading order.
        .defaultFocus($focus, request.saveContentTypes != nil ? .name : .rows)
    }

    /// The blank rows between the panel's parts — the message, the name
    /// field, the path and the folder: none at the small control sizes, as
    /// dense as a terminal panel can be; one at `.regular` and `.large`, to
    /// set the parts apart as a macOS panel's margins do; two at
    /// `.extraLarge`. None, whatever the size, where the vertical size class
    /// is compact: a short terminal keeps its rows for the folder.
    static func spacing(controlSize: ControlSize, verticalSizeClass: UserInterfaceSizeClass?) -> Int {
        if verticalSizeClass == .compact { return 0 }
        switch controlSize {
        case .mini, .small: return 0
        case .regular, .large: return 1
        case .extraLarge: return 2
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

    /// The table of the folder's items, with the columns its width has room
    /// for (``FilePanelColumns/shown(inWidth:)``).
    @ViewBuilder private var rows: some View {
        // A reader is greedy: the table has the rest of the sheet's height,
        // however few the rows, and the panel is the same size from one
        // folder to the next.
        GeometryReader { proxy in
            table(width: proxy.size.width)
        }
        // A folder is a new table: its cursor starts on the first row and its
        // scroll at the top, rather than at the place the last folder's were.
        .id(browser.directory)
        .contextMenu(forSelectionType: URL.self) { _ in
        } primaryAction: { urls in
            activate(urls)
        }
        // Backspace, not ←: the outline's ← closes a branch or goes to the
        // row a branch is under, as an outline view's does.
        .onKeyPress(keys: [.delete], phases: [.down, .repeat]) { press in
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
        // Added to the sheet's own Escape item, which presses the Cancel
        // button (`StatusBarState.keepPresentationItem`).
        .statusBarItems {
            StatusBarItem(
                shortcut: Shortcut.backspace,
                label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusEnclosingFolder))
            StatusBarItem(
                shortcut: "~", label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusHome))
            StatusBarItem(
                shortcut: "/", label: LocalizationService.shared.string(for: LocalizationKey.FilePanel.statusGoTo))
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
            } else if request.allowsMultipleSelection {
                Table(browser.rows, children: \.children, selection: selectable, sortOrder: sortOrder) {
                    FilePanelColumns.fitting(width, browser: browser)
                }
                .tableEmptyPlaceholder(emptyText)
            } else {
                Table(browser.rows, children: \.children, selection: selectableSingle, sortOrder: sortOrder) {
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
        if request.allowsMultipleSelection {
            Table(browser.rows, selection: selectable, sortOrder: sortOrder) {
                FilePanelColumns.fitting(width, browser: browser)
            }
            .tableEmptyPlaceholder(emptyText)
        } else {
            Table(browser.rows, selection: selectableSingle, sortOrder: sortOrder) {
                FilePanelColumns.fitting(width, browser: browser)
            }
            .tableEmptyPlaceholder(emptyText)
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
    ///
    /// Each URL offered is looked up (``FileBrowser/entry(for:)``): a URL the
    /// folder does not list is kept, as the selection keeps what was chosen
    /// in another folder, and only a dimmed row is refused.
    private var selectable: Binding<Set<URL>> {
        Binding(
            get: { selection },
            set: { urls in selection = urls.filter { browser.entry(for: $0)?.isDimmed != true } })
    }

    /// ``selectable``, for a single selection.
    private var selectableSingle: Binding<URL?> {
        Binding(
            get: { singleSelection },
            set: { url in singleSelection = url.flatMap { browser.entry(for: $0)?.isDimmed == true ? nil : $0 } })
    }

    /// The table's order, which the browser keeps.
    private var sortOrder: Binding<[KeyPathComparator<FileEntry>]> {
        Binding(get: { browser.sortOrder }, set: { browser.sortOrder = $0 })
    }

    /// An open panel's type pop-up's choice, which narrows or widens the
    /// files the browser lets the user choose.
    private var filterChoice: Binding<FileTypeChoice> {
        Binding(
            get: { typeChoice },
            set: { choice in
                typeChoice = choice
                browser.filterFiles(by: choice.fileTypes)
            })
    }

    /// A save panel's Format pop-up's choice: the type the name's extension
    /// names, and a choice gives the name the chosen type's extension
    /// (``SaveName/renamed(_:as:among:)``) — one truth, the name, as macOS's
    /// pop-up rewrites the name.
    private var formatChoice: Binding<FileTypeChoice> {
        let types = request.saveContentTypes ?? []
        return Binding(
            get: { SaveName.type(for: name, among: types).map(FileTypeChoice.type) ?? .supported },
            set: { choice in
                if case .type(let type) = choice { name = SaveName.renamed(name, as: type, among: types) }
            })
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

    /// The items of the folder shown that are selected now, in the rows'
    /// order: looked up, so that it costs the selection's size, not the
    /// folder's, on every body.
    private var selectedEntries: [FileEntry] {
        if request.allowsMultipleSelection { return browser.entries(for: selection) }
        return browser.entries(for: singleSelection.map { [$0] } ?? [])
    }

    /// What the confirmation button chooses now, of `selected`: its
    /// choosable items, or else the folder shown when a folder may be chosen.
    private func confirmable(_ selected: [FileEntry]) -> [URL] {
        let chosen = selected.filter(\.isChoosable).map(chosenURL)
        if !chosen.isEmpty { return chosen }
        return request.rule.choosesFolders && selected.isEmpty ? [browser.directory] : []
    }

    /// Whether the confirmation button does anything: it chooses, or it opens
    /// the one folder selected, as a macOS panel's Open opens a folder that
    /// cannot be chosen.
    private var canConfirm: Bool {
        if request.saveContentTypes != nil { return saveDestination != nil }
        let selected = selectedEntries
        return !confirmable(selected).isEmpty || openableSelection(selected) != nil
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

    /// The one folder of `selected`, when it is one folder that cannot be
    /// chosen: the confirmation button opens it.
    private func openableSelection(_ selected: [FileEntry]) -> URL? {
        guard selected.count == 1, let entry = selected.first, entry.isFolder, !entry.isChoosable else { return nil }
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
        let selected = selectedEntries
        if let folder = openableSelection(selected) {
            browser.open(folder)
            return
        }
        let urls = confirmable(selected)
        guard !urls.isEmpty else { return }
        finish(.chose(urls, ending))
    }

    /// Return or a double-click on `urls`: the rows under the cursor, or the
    /// selection when the cursor is in it. One folder opens; otherwise the
    /// items that can be chosen are.
    private func activate(_ urls: Set<URL>) {
        let entries = browser.entries(for: urls)
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
