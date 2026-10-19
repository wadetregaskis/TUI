//  🖥️ TUIkit — Terminal UI Kit for Swift
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
import TUIkitFoundation

/// The state of one file panel's browsing.
///
/// A panel keeps one as `@State` for as long as it is presented. Its folder
/// changes on the main actor, at once (``open(_:)``, ``goUp()``); what the
/// folder holds follows when ``refresh()`` — run by the panel's
/// `.task(id: refreshKey)`, so that a newer folder or order cancels it —
/// has read it on another thread. Sorting is done there too: a change of
/// order or of the hidden-files switch re-sorts the folder already read,
/// without reading it again.
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
    let rule: FileChoiceRule

    /// What the panel shows of the folder.
    private(set) var state: State = .loading

    /// The rows, in order: the folder's items, hidden ones left out unless
    /// ``showsHiddenFiles``, folders first. Empty until the folder is read.
    private(set) var rows: [FileEntry] = []

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
    @ObservationIgnored private var listed: (directory: URL, generation: Int, entries: [FileEntry])?

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
            // (measured with Swift 6.3.3; TUIkitTables' `tableColumnDefault`
            // makes the same choice).
            KeyPathComparator(\FileEntry.name, comparator: String.StandardComparator.lexical)
        #endif
    }

    // MARK: - Moving around

    /// Shows `folder`.
    func open(_ folder: URL) {
        let folder = folder.standardizedFileURL
        guard folder != directory else { return }
        directory = folder
        rows = []
        hiddenCount = 0
        state = .loading
    }

    /// Shows the folder that holds this one; at the root, does nothing.
    func goUp() {
        let parent = directory.deletingLastPathComponent()
        // The root's parent is the root again.
        if parent.standardizedFileURL.path != directory.path { open(parent) }
    }

    /// Reads the folder again, as it is now.
    func reload() {
        generation += 1
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
        hiddenCount = arranged.hiddenCount
        state = .loaded
    }

    /// `entries` as the rows show them, off the main actor: hidden ones left
    /// out unless shown, folders first, each group in `sortOrder`.
    @concurrent
    nonisolated static func arrange(
        _ entries: [FileEntry], showsHiddenFiles: Bool, sortOrder: [KeyPathComparator<FileEntry>]
    ) async -> (rows: [FileEntry], hiddenCount: Int) {
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
        return (rows, hiddenCount)
    }
}
