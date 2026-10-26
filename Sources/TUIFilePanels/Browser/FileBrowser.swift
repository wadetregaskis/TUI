//  🖥️ TUI — A Terminal UI framework for Swift
//  FileBrowser.swift
//
//  The state of one file panel's browsing: the folder it shows, what that
//  folder holds, and the rows it is shown as — read and sorted off the main
//  actor, so a folder of a hundred thousand items never holds up a frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// The state of one file panel's browsing.
///
/// A panel keeps one as `@State` for as long as it is presented. Its folder
/// changes on the main actor, at once (``open(_:)``, ``goUp()``); what the
/// folder holds follows when ``refresh()`` — run by the panel's
/// `.task(id: refreshKey)`, so that a newer folder or order cancels it —
/// has read it on another thread. Sorting is done there too: a change of
/// order or of the hidden-files switch re-sorts the folder already read,
/// without reading it again.
///
/// It reads other folders too, as the views ask for them
/// (``loadFolder(_:)``, `FileBrowser+Folders.swift`): the list view's
/// outline, a branch at a time, and the column view, a column for each
/// folder on the way to the one shown.
@MainActor
@Observable
final class FileBrowser {
    /// The folder the panel shows.
    private(set) var directory: URL

    /// How many times the folder has been asked to be read again: a change
    /// starts a new read of the same folder.
    private(set) var generation = 0

    /// Whether the hidden items are listed.
    var showsHiddenFiles: Bool

    /// The order of the rows, after the folders, which always come first. The
    /// table's columns write it.
    var sortOrder: [KeyPathComparator<FileEntry>]

    /// What the panel lets the user choose, and how it words its rows.
    private(set) var rule: FileChoiceRule

    /// What the panel shows of the folder.
    private(set) var state: State = .loading

    /// The rows, in order: the folder's items, hidden ones left out unless
    /// ``showsHiddenFiles``, folders first, each folder's with the rows
    /// beneath it in the outline (``FileEntry/children``). Empty until the
    /// folder is read. Written by the browser alone (here, and as branches
    /// arrive, `FileBrowser+Folders.swift`).
    var rows: [FileEntry] = []

    /// Each row's place in ``rows``, by its URL: how the panel finds the rows
    /// a selection names (``entry(for:)``, ``entries(for:)``). A scan of the
    /// rows for each URL made selecting every item of a folder of 3,000 take
    /// seconds, where a frame of it takes milliseconds.
    private(set) var rowIndex: [URL: Int] = [:]

    /// How many hidden items the folder holds, shown or not.
    private(set) var hiddenCount = 0

    /// What the panel shows of its folder.
    enum State: Equatable {
        /// The folder is being read.
        case loading
        /// The folder was read; ``rows`` are its items.
        case loaded
        /// The folder could not be read.
        case failed(DirectoryListingFailure)
    }

    /// The last folder read, kept so that re-sorting it needs no second read.
    @ObservationIgnored var listed: (directory: URL, generation: Int, entries: [FileEntry])?

    /// Other folders read — the outline's branches and the column view's
    /// columns — as read, by path, so a new order or the hidden-files switch
    /// arranges them again without reading them again.
    @ObservationIgnored var folderListings: [String: [FileEntry]] = [:]

    /// The same folders' items as rows: arranged as ``rows`` are, each a
    /// folder's own. The panel redraws as one arrives.
    var folderRows: [String: [FileEntry]] = [:]

    /// Each of those rows by its URL, for the selection's lookups
    /// (``entry(for:)``): a branch's items can be selected too.
    @ObservationIgnored var folderIndex: [URL: FileEntry] = [:]

    /// The folders being read for ``loadFolder(_:)`` now.
    @ObservationIgnored var foldersReading: Set<String> = []

    init(directory: URL, rule: FileChoiceRule, showsHiddenFiles: Bool = false) {
        self.directory = directory.standardizedFileURL
        self.rule = rule
        self.showsHiddenFiles = showsHiddenFiles
        self.sortOrder = [Self.nameOrder]
    }

    /// The order a panel starts in: by name, as Finder compares names (so
    /// "item2" comes before "item10"), where Foundation can.
    nonisolated static var nameOrder: KeyPathComparator<FileEntry> {
        // Spelt out, not `.localizedStandard`: the argument is any
        // `SortComparator`, and on Linux the bare member finds an internal one.
        #if canImport(Darwin)
            KeyPathComparator(\FileEntry.name, comparator: String.StandardComparator.localizedStandard)
        #else
            // The static Linux SDK's Foundation has no `.localizedStandard`
            // (measured with Swift 6.3.3; TUITables' `tableColumnDefault`
            // makes the same choice).
            KeyPathComparator(\FileEntry.name, comparator: String.StandardComparator.lexical)
        #endif
    }

    // MARK: - Moving around

    /// Shows `folder`.
    ///
    /// The folder shown, and every other folder read that is on the way to
    /// the new one, stay read (the column view's columns), and the rest go;
    /// a folder already read shows at once.
    func open(_ folder: URL) {
        let folder = folder.standardizedFileURL
        guard folder.path != directory.path else { return }
        keepFolders(onTheWayTo: folder)
        directory = folder
        rowIndex = [:]
        hiddenCount = 0
        if let read = folderListings[folder.path] {
            // Arranged when it was read; `refresh()` arranges it again.
            listed = (folder, generation, read)
            rows = folderRows[folder.path] ?? []
            rowIndex = Dictionary(
                rows.indices.lazy.map { (self.rows[$0].url, $0) }, uniquingKeysWith: { first, _ in first })
            state = .loaded
        } else {
            rows = []
            state = .loading
        }
    }

    /// Shows the folder that holds this one; at the root, does nothing.
    func goUp() {
        let parent = directory.deletingLastPathComponent()
        // The root's parent is the root again.
        if parent.standardizedFileURL.path != directory.path { open(parent) }
    }

    /// Reads the folder again, as it is now, and every other folder as it is
    /// asked for again.
    func reload() {
        generation += 1
        forgetFolders()
    }

    /// Lets the user choose files of `types` — `nil` for the caller's own,
    /// empty for every file — and reads the folder again, which is where an
    /// item's choosability is worked out (the type pop-up's choice).
    func filterFiles(by types: [UTType]?) {
        guard rule.fileTypes != types else { return }
        rule.fileTypes = types
        reload()
    }

    /// Whether the folder shown is the file system's root, which has no folder
    /// above it.
    var isAtRoot: Bool {
        directory.deletingLastPathComponent().standardizedFileURL.path == directory.path
    }

    // MARK: - Reading and sorting

    /// What ``refresh()`` depends on: a change of any part starts it again.
    struct RefreshKey: Equatable {
        let directory: URL
        let generation: Int
        let showsHiddenFiles: Bool
        let sortOrder: [KeyPathComparator<FileEntry>]
    }

    /// The panel's `.task(id:)` key.
    var refreshKey: RefreshKey {
        RefreshKey(
            directory: directory, generation: generation, showsHiddenFiles: showsHiddenFiles, sortOrder: sortOrder)
    }

    /// Reads the folder, unless the last read was of this folder and this
    /// generation, then sorts it, both off the main actor, and publishes the
    /// rows — unless the task was cancelled meanwhile, its result stale.
    func refresh() async {
        let key = refreshKey
        let entries: [FileEntry]
        if let listed, listed.directory == key.directory, listed.generation == key.generation {
            entries = listed.entries
        } else {
            let result = await DirectoryListing.load(key.directory, rule: rule)
            guard !Task.isCancelled, refreshKey.directory == key.directory, generation == key.generation else {
                return
            }
            switch result {
            case .success(let read):
                listed = (key.directory, key.generation, read)
                entries = read
            case .failure(let failure):
                listed = nil
                rows = []
                rowIndex = [:]
                hiddenCount = 0
                state = .failed(failure)
                return
            }
        }
        let arranged = await Self.arrange(
            entries, showsHiddenFiles: key.showsHiddenFiles, sortOrder: key.sortOrder)
        // Published only while nothing has moved on: a refresh started for a
        // later folder or order owns the rows, whether or not this one was
        // cancelled in time.
        guard !Task.isCancelled, refreshKey == key else { return }
        rows = arranged.rows
        rowIndex = arranged.rowIndex
        hiddenCount = arranged.hiddenCount
        state = .loaded
        await arrangeFolders(as: key)
    }

    /// `entries` as the rows show them, off the main actor: hidden ones left
    /// out unless shown, folders first, each group in `sortOrder`; and each
    /// row's place, by its URL.
    @concurrent
    nonisolated static func arrange(
        _ entries: [FileEntry], showsHiddenFiles: Bool, sortOrder: [KeyPathComparator<FileEntry>]
    ) async -> (rows: [FileEntry], rowIndex: [URL: Int], hiddenCount: Int) {
        let hiddenCount = entries.count { $0.isHidden }
        let shown = showsHiddenFiles ? entries : entries.filter { !$0.isHidden }
        let rows = shown.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            for comparator in sortOrder {
                switch comparator.compare(lhs, rhs) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
            // A folder's row stands for its items in the outline until it is
            // read (``FileEntry/placeholder(in:)``).
            .map { entry in
                guard entry.isFolder, entry.children == nil else { return entry }
                var folder = entry
                folder.children = [.placeholder(in: entry.url)]
                return folder
            }
        // A folder names each item once; should a URL come twice all the
        // same, the first row is the one found, rather than a trap.
        let rowIndex = Dictionary(
            rows.indices.lazy.map { (rows[$0].url, $0) }, uniquingKeysWith: { first, _ in first })
        return (rows, rowIndex, hiddenCount)
    }

    // MARK: - Finding rows

    /// The row of `url`, if the folder shown lists it or an outline's branch
    /// read beneath it does.
    func entry(for url: URL) -> FileEntry? {
        rowIndex[url].map { rows[$0] } ?? folderIndex[url]
    }

    /// The rows of `urls` the folder shown lists, in the rows' order, then
    /// those its branches list, by path: a lookup per URL, never a scan of
    /// the folder.
    func entries(for urls: some Sequence<URL>) -> [FileEntry] {
        var shown: [Int] = []
        var beneath: [FileEntry] = []
        // Only the branches beneath the folder shown: the column view reads
        // the folders above it too, which no selection here is in.
        let base = directory.path == "/" ? "/" : directory.path + "/"
        for url in urls {
            if let index = rowIndex[url] {
                shown.append(index)
            } else if let entry = folderIndex[url], entry.url.path.hasPrefix(base) {
                beneath.append(entry)
            }
        }
        return shown.sorted().map { rows[$0] } + beneath.sorted { $0.url.path < $1.url.path }
    }
}
