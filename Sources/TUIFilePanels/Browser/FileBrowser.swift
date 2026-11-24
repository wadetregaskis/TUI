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

    /// How long a folder load waits before showing the "Loading…" placeholder,
    /// so fast folder loads avoid confusing visual flicker and wasted rendering.
    package static let loadingPlaceholderDelay: Duration = .milliseconds(250)

    /// What the panel shows of the folder.
    private(set) var state: State = .loading

    /// Whether the main folder loading placeholder has timed out and should be shown.
    package private(set) var showsLoadingPlaceholder = false

    /// The task driving the delay before showing the main folder's loading placeholder.
    @ObservationIgnored private(set) var loadingPlaceholderTask: Task<Void, Never>?

    /// The clock the loading delays run on: the machine's in an app, a test's
    /// own in a test, which steps it to either side of the delay rather than
    /// waiting it out (and racing it on a busy machine).
    @ObservationIgnored let clock: any Clock<Duration>

    /// Which folder paths have exceeded ``loadingPlaceholderDelay`` while reading
    /// and should display the "Loading…" placeholder.
    var foldersShowingLoading: Set<String> = []

    /// Timer tasks driving the delay before showing placeholders for individual folders.
    @ObservationIgnored var folderLoadingTimers: [String: Task<Void, Never>] = [:]

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

    /// The order and hidden-files switch ``rows`` were arranged for; `nil`
    /// while there are none.
    @ObservationIgnored var rowsArrangement: Arrangement?

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

    /// Why each of those folders that could not be read could not, by path:
    /// listed as having no items, so that it is not read again for each ask,
    /// but opened, it is read again — a folder peeked at in the column view
    /// or the outline that could not be read opened as "This folder is
    /// empty." — and its column says why it has none.
    var folderFailures: [String: DirectoryListingFailure] = [:]

    /// The outline branches currently open in list view, kept so that a reload
    /// (e.g. from changing file types) reloads their contents.
    @ObservationIgnored var openBranches: Set<URL> = []

    /// The same folders' items as rows: arranged as ``rows`` are, each a
    /// folder's own. The panel redraws as one arrives.
    var folderRows: [String: [FileEntry]] = [:]

    /// Each of those folders' rows' places in its ``folderRows``, by URL, for
    /// the selection's lookups (``entry(for:)``): a branch's items can be
    /// selected too. Kept a folder at a time, as ``arrange(_:showsHiddenFiles:sortOrder:)``
    /// makes it off the main actor, so that keeping a folder, or dropping
    /// one, is a dictionary's work: one index of every folder's rows was
    /// built again on the main actor after each refresh (45 ms for 50,000
    /// rows, release), and filtered on each ``open(_:)`` by a URL made for
    /// each row (350 ms for 50,000).
    @ObservationIgnored var folderIndex: [String: [URL: Int]] = [:]

    /// The "Loading…" rows of folders not read yet (``FileEntry/placeholder(in:)``),
    /// by URL: indexed, so the selection finds one dimmed and refuses it.
    @ObservationIgnored var placeholderIndex: [URL: FileEntry] = [:]

    /// The order and hidden-files switch each of those folders' rows were
    /// arranged for, by path: a folder arranged as the panel says now is not
    /// arranged again. Each was, for every folder opened — the parent of
    /// 50,000 items kept for the column view, a second's sort (release) —
    /// before the folder opened could show.
    @ObservationIgnored var folderArrangements: [String: Arrangement] = [:]

    /// The folders being read for ``loadFolder(_:)`` now, by path: each read's
    /// task, which every ask awaits, and the generation it began in.
    @ObservationIgnored var foldersReading: [String: (generation: Int, read: Task<Void, Never>)] = [:]

    init(
        directory: URL, rule: FileChoiceRule, showsHiddenFiles: Bool = false,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.clock = clock
        self.directory = directory.panelStandardized
        self.rule = rule
        self.showsHiddenFiles = showsHiddenFiles
        self.sortOrder = [Self.nameOrder]
        startLoadingPlaceholderTimer()
    }

    deinit {
        loadingPlaceholderTask?.cancel()
    }

    private func startLoadingPlaceholderTimer() {
        showsLoadingPlaceholder = false
        loadingPlaceholderTask?.cancel()
        let clock = clock
        loadingPlaceholderTask = Task { @MainActor [weak self] in
            try? await clock.sleep(for: Self.loadingPlaceholderDelay)
            guard !Task.isCancelled, let self, self.state == .loading else { return }
            self.showsLoadingPlaceholder = true
        }
    }

    private func cancelLoadingPlaceholderTimer() {
        loadingPlaceholderTask?.cancel()
        loadingPlaceholderTask = nil
        showsLoadingPlaceholder = false
    }

    /// The order a panel starts in: by name, as Finder compares names (so
    /// "item2" comes before "item10").
    nonisolated static var nameOrder: KeyPathComparator<FileEntry> {
        // Spelt out, not `.localizedStandard`: the argument is any
        // `SortComparator`, and on Linux the bare member finds an internal one.
        #if canImport(Darwin)
            KeyPathComparator(\FileEntry.name, comparator: String.StandardComparator.localizedStandard)
        #else
            // Foundation here has `localizedStandardCompare(_:)` but no
            // `.localizedStandard` comparator (`LocalizedStandardOrder`).
            KeyPathComparator(\FileEntry.name, comparator: LocalizedStandardOrder())
        #endif
    }

    // MARK: - Moving around

    /// Shows `folder`.
    ///
    /// The folder shown, and every other folder read that is on the way to
    /// the new one, stay read (the column view's columns), and the rest go;
    /// a folder already read shows at once.
    func open(_ folder: URL) {
        let folder = folder.panelStandardized
        guard folder.path != directory.path else { return }
        openBranches.removeAll()
        keepFolders(onTheWayTo: folder)
        directory = folder
        rowIndex = [:]
        hiddenCount = 0
        if folderFailures[folder.path] == nil, let read = folderListings[folder.path] {
            // Arranged when it was read; `refresh()` arranges it again.
            cancelLoadingPlaceholderTimer()
            listed = (folder, generation, read)
            rows = folderRows[folder.path] ?? []
            rowsArrangement = folderArrangements[folder.path]
            rowIndex =
                folderIndex[folder.path]
                ?? Dictionary(
                    rows.indices.lazy.map { (self.rows[$0].url, $0) }, uniquingKeysWith: { first, _ in first })
            state = .loaded
        } else {
            rows = []
            rowsArrangement = nil
            state = .loading
            startLoadingPlaceholderTimer()
        }
    }

    /// Shows the folder that holds this one; at the root, does nothing.
    func goUp() {
        if let parent = FolderPath.parent(of: directory) { open(parent) }
    }

    /// Reads the folder again, as it is now, and every other folder as it is
    /// asked for again.
    func reload() {
        generation += 1
        forgetFolders()
        state = .loading
        startLoadingPlaceholderTimer()
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
        FolderPath.parent(of: directory) == nil
    }

    // MARK: - Reading and sorting

    /// What ``refresh()`` depends on: a change of any part starts it again.
    struct RefreshKey: Equatable {
        let directory: URL
        let generation: Int
        let showsHiddenFiles: Bool
        let sortOrder: [KeyPathComparator<FileEntry>]

        /// The arrangement it asks for.
        var arrangement: Arrangement {
            Arrangement(showsHiddenFiles: showsHiddenFiles, sortOrder: sortOrder)
        }
    }

    /// What a folder's rows are arranged by: the hidden-files switch and the
    /// order.
    struct Arrangement: Equatable {
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
    /// rows — unless the task was cancelled meanwhile, its result stale —
    /// before it arranges the other folders read for a new order, so that
    /// the folder shown waits for none of theirs. A
    /// folder shown from those kept (``open(_:)``), its rows arranged as `key`
    /// says, is not sorted again: going back up to a parent of 50,000 items
    /// sorted it again, a second (release), for rows equal to those shown.
    func refresh() async {
        let key = refreshKey
        let entries: [FileEntry]
        var arrangedAlready = false
        if let listed, listed.directory == key.directory, listed.generation == key.generation {
            entries = listed.entries
            arrangedAlready = state == .loaded && rowsArrangement == key.arrangement
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
                cancelLoadingPlaceholderTimer()
                listed = nil
                rows = []
                rowsArrangement = nil
                rowIndex = [:]
                hiddenCount = 0
                state = .failed(failure)
                return
            }
        }
        let arranged: (rows: [FileEntry], rowIndex: [URL: Int], hiddenCount: Int)
        if arrangedAlready {
            arranged = (rows, rowIndex, entries.count { $0.isHidden })
        } else {
            arranged = await Self.arrange(
                entries, showsHiddenFiles: key.showsHiddenFiles, sortOrder: key.sortOrder)
        }
        // Published only while nothing has moved on: a refresh started for a
        // later folder or order owns the rows, whether or not this one was
        // cancelled in time.
        guard !Task.isCancelled, refreshKey == key else { return }
        cancelLoadingPlaceholderTimer()
        // The folder shown first: arranged after the others, it waited for
        // each of theirs, blank, a second for a parent of 50,000 items
        // (release). Its branches follow theirs, a moment in the old order.
        rows = branches(for: arranged.rows)
        rowIndex = arranged.rowIndex
        hiddenCount = arranged.hiddenCount
        rowsArrangement = key.arrangement
        state = .loaded
        if await arrangeFolders(as: key) { attachBranches() }
        guard !Task.isCancelled, refreshKey == key else { return }
        let toLoad = openBranches.filter { folderListings[$0.panelStandardized.path] == nil }
        if !toLoad.isEmpty {
            let tasks = toLoad.map { branch in
                Task { await self.loadFolder(branch) }
            }
            for task in tasks {
                await task.value
            }
        }
    }

    /// `entries` as the rows show them, off the main actor: hidden ones left
    /// out unless shown, folders first, each group in `sortOrder`; and each
    /// row's place, by its URL.
    @concurrent
    nonisolated static func arrange(
        _ entries: [FileEntry], showsHiddenFiles: Bool, sortOrder: [KeyPathComparator<FileEntry>]
    ) async -> (rows: [FileEntry], rowIndex: [URL: Int], hiddenCount: Int) {
        if let watch = FileArrangementWatch.current { await watch.heard(entries) }
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
            // A folder's row is a branch in the outline that starts with no children
            // until read or until the loading delay elapses.
            .map { entry in
                guard entry.expandsInPlace, entry.children == nil else { return entry }
                var folder = entry
                folder.children = []
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
        rowIndex[url].map { rows[$0] } ?? folderEntry(for: url)
    }

    /// The rows of `urls` the folder shown lists, in the rows' order, then
    /// those its branches list, by path: a lookup per URL, never a scan of
    /// the folder.
    func entries(for urls: some Sequence<URL>) -> [FileEntry] {
        var shown: [Int] = []
        var beneath: [FileEntry] = []
        // Only the branches beneath the folder shown: the column view reads
        // the folders above it too, which no selection here is in.
        let base = FolderPath.withSlash(directory.path)
        for url in urls {
            if let index = rowIndex[url] {
                shown.append(index)
            } else if let entry = folderEntry(for: url), entry.url.path.hasPrefix(base) {
                beneath.append(entry)
            }
        }
        return shown.sorted().map { rows[$0] } + beneath.sorted { $0.url.path < $1.url.path }
    }
}

/// What a test hears of each arrangement ``FileBrowser`` makes
/// (``FileBrowser/arrange(_:showsHiddenFiles:sortOrder:)``), the entries it
/// is given, before it sorts them: a test counts them, or looks at what the
/// panel shows while one waits. An arrangement of 50,000 items by name takes
/// a second (release, macOS 26), so which folders are arranged, and when,
/// is what a panel's wait is made of.
struct FileArrangementWatch: Sendable {
    /// The watch, while a test's task binds it; `nil`, and nothing heard,
    /// everywhere else.
    @TaskLocal static var current: Self?

    /// Hears the entries of one arrangement, which waits for it.
    let heard: @Sendable ([FileEntry]) async -> Void
}
