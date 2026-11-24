//  🖥️ TUI — A Terminal UI framework for Swift
//  FileBrowser+Folders.swift
//
//  The folders a file panel reads besides the one it shows: the list view's
//  outline branches, read as each is opened, and the column view's columns,
//  the folders on the way to the one shown.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

extension FileBrowser {
    /// Reads `folder` off the main actor, unless it has been read since the
    /// folder shown was last read again, and returns once it is read: as the
    /// outline opens a branch (its placeholder row asks), or the column view
    /// shows a column. A folder that cannot be read has no items, and why is
    /// kept beside them (``folderFailures``).
    ///
    /// The read is the folder's, not the asker's: one task of its own, which
    /// every ask while it lasts awaits, and which the asker's cancellation
    /// does not reach. Owned by the first asker, a read was thrown away when
    /// that asker was cancelled — a column that left — and the next ask,
    /// finding the folder "being read", went away too: a column selected,
    /// left and selected again drew "Loading…" until it was left once more.
    func loadFolder(_ folder: URL) async {
        let path = folder.panelStandardized.path
        guard folderListings[path] == nil, path != directory.path else { return }
        // A read begun before the folder shown was read again is not this
        // generation's: it publishes nothing, so this ask reads afresh.
        if let reading = foldersReading[path], reading.generation == generation {
            await reading.read.value
            return
        }
        let started = generation
        let clock = clock
        let timer = Task { @MainActor [weak self] in
            try? await clock.sleep(for: Self.loadingPlaceholderDelay)
            guard !Task.isCancelled, let self else { return }
            if self.foldersReading[path]?.generation == started {
                self.foldersShowingLoading.insert(path)
                self.attachBranches()
            }
        }
        folderLoadingTimers[path] = timer
        let read = Task { await self.read(path, generation: started) }
        foldersReading[path] = (started, read)
        await read.value
    }

    /// Reads the folder at `path` for ``loadFolder(_:)``, and publishes it
    /// unless the folder shown has been read again since `generation`.
    private func read(_ path: String, generation started: Int) async {
        defer {
            if foldersReading[path]?.generation == started {
                foldersReading[path] = nil
                folderLoadingTimers[path]?.cancel()
                folderLoadingTimers[path] = nil
                foldersShowingLoading.remove(path)
            }
        }
        let result = await DirectoryListing.load(URL(fileURLWithPath: path), rule: rule)
        guard generation == started else { return }
        // Named through the folder as it was asked for: a branch beneath a
        // link names its items through the link, as the listing names them.
        // A folder that cannot be read has no items, and the reason is kept
        // for its column, and so that opening it reads it again.
        let read = (try? result.get()) ?? []
        let failure: DirectoryListingFailure?
        if case .failure(let reason) = result { failure = reason } else { failure = nil }
        // Arranged as the panel says when it is published: a new order or
        // the hidden-files switch while it was arranged arranges it again,
        // since `arrangeFolders(as:)` may have run already without it.
        var arranged: (rows: [FileEntry], rowIndex: [URL: Int], hiddenCount: Int)
        var hidden: Bool
        var order: [KeyPathComparator<FileEntry>]
        repeat {
            (hidden, order) = (showsHiddenFiles, sortOrder)
            arranged = await Self.arrange(read, showsHiddenFiles: hidden, sortOrder: order)
            guard generation == started else { return }
        } while showsHiddenFiles != hidden || sortOrder != order
        folderListings[path] = read
        folderFailures[path] = failure
        folderRows[path] = arranged.rows
        folderIndex[path] = arranged.rowIndex
        folderArrangements[path] = Arrangement(showsHiddenFiles: hidden, sortOrder: order)
        attachBranches()
    }

    /// The folders read, arranged again as `key` says: after the folder shown
    /// is, for a new order or the hidden-files switch. Only those arranged
    /// otherwise (``folderArrangements``): opening a folder changes no other
    /// folder's order, and sorted again, a kept parent of 50,000 items held
    /// the folder opened blank for a second (release).
    ///
    /// A folder read while they are arranged is arranged too, as the rest
    /// are. The rows were replaced by those of the folders there were when
    /// this began, which dropped such a folder's rows while its listing
    /// stayed — so nothing read it again, and its column drew "Loading…".
    func arrangeFolders(as key: RefreshKey) async {
        let arrangement = key.arrangement
        var pending = folderListings.filter { folderArrangements[$0.key] != arrangement }
        while !pending.isEmpty {
            var arranged: [String: (rows: [FileEntry], rowIndex: [URL: Int], hiddenCount: Int)] = [:]
            for (path, read) in pending {
                arranged[path] =
                    await Self.arrange(read, showsHiddenFiles: key.showsHiddenFiles, sortOrder: key.sortOrder)
            }
            guard !Task.isCancelled, refreshKey == key else { return }
            for (path, result) in arranged {
                folderRows[path] = result.rows
                folderIndex[path] = result.rowIndex
                folderArrangements[path] = arrangement
            }
            pending = folderListings.filter { folderArrangements[$0.key] != arrangement }
        }
    }

    /// Attaches the read folders to `rows` all the way down, as the
    /// outline's branches.
    func branches(for rows: [FileEntry]) -> [FileEntry] {
        guard !folderRows.isEmpty || !foldersShowingLoading.isEmpty else { return rows }
        var updated = rows
        for index in updated.indices where updated[index].expandsInPlace {
            updated[index].children = branch(of: updated[index].url)
        }
        return updated
    }

    /// Puts each folder read under its row, all the way down, as the
    /// outline's branches: a folder not read yet keeps its placeholder once delay elapses.
    func attachBranches() {
        rows = branches(for: rows)
    }

    /// The rows beneath `folder` in the outline: its items, each folder among
    /// them with its own, or a placeholder where it is not read yet once the
    /// loading delay has elapsed. Recursion goes only as deep as folders have
    /// been read, so a link that leads back up ends where the reading did.
    private func branch(of folder: URL) -> [FileEntry] {
        guard let items = folderRows[folder.panelStandardized.path] else {
            if foldersShowingLoading.contains(folder.panelStandardized.path) {
                // Indexed, so the selection finds it dimmed and refuses it.
                let placeholder = FileEntry.placeholder(in: folder)
                placeholderIndex[placeholder.url] = placeholder
                return [placeholder]
            }
            return []
        }
        return items.map { item in
            guard item.expandsInPlace else { return item }
            var folder = item
            folder.children = branch(of: item.url)
            return folder
        }
    }

    /// The row of `url` among the folders read besides the one shown: found
    /// in its own folder's index, by the folder its URL names.
    func folderEntry(for url: URL) -> FileEntry? {
        if let placeholder = placeholderIndex[url] { return placeholder }
        // A row's URL is its folder's, as read, and its name
        // (`DirectoryListing`), so the folder it names is the one whose path
        // keys it; the standardized spelling, the one the paths are kept
        // under, where that differs.
        let folder = url.deletingLastPathComponent()
        if let entry = keptEntry(for: url, in: folder.path) { return entry }
        let standardized = folder.panelStandardized.path
        return standardized == folder.path ? nil : keptEntry(for: url, in: standardized)
    }

    /// The row of `url` in the folder read at `path`.
    private func keptEntry(for url: URL, in path: String) -> FileEntry? {
        guard let place = folderIndex[path]?[url], let rows = folderRows[path], rows.indices.contains(place) else {
            return nil
        }
        return rows[place]
    }

    /// Before the folder shown becomes `folder`: the folder shown joins the
    /// folders read, and only those on the way to `folder` are kept — the
    /// folders above it, and those inside it, which the column view shows as
    /// the way back down after going up. Dropped, the folder come from was
    /// read again for its column, which drew "Loading…" until then.
    ///
    /// The folder shown joins them only as read in this generation: read
    /// before a ``reload()`` — New Folder reloads, then opens the folder it
    /// made — its listing is out of date, and kept, it was what going back
    /// showed, without the new folder.
    func keepFolders(onTheWayTo folder: URL) {
        if state == .loaded, let listed, listed.directory.path == directory.path, listed.generation == generation {
            folderListings[directory.path] = listed.entries
            folderRows[directory.path] = rows
            folderIndex[directory.path] = rowIndex
            folderArrangements[directory.path] = rowsArrangement
        }
        let target = folder.panelStandardized.path
        let inside = FolderPath.withSlash(target)
        let isKeptPath: (String) -> Bool = { path in
            path == target || path == "/" || target.hasPrefix(FolderPath.withSlash(path)) || path.hasPrefix(inside)
        }
        folderListings = folderListings.filter { isKeptPath($0.key) }
        folderFailures = folderFailures.filter { isKeptPath($0.key) }
        folderRows = folderRows.filter { isKeptPath($0.key) }
        folderIndex = folderIndex.filter { isKeptPath($0.key) }
        folderArrangements = folderArrangements.filter { isKeptPath($0.key) }
        placeholderIndex = placeholderIndex.filter { isKeptPath($0.value.placeholderFolder.panelStandardized.path) }
        for (path, timer) in folderLoadingTimers where !isKeptPath(path) {
            timer.cancel()
            folderLoadingTimers.removeValue(forKey: path)
            foldersShowingLoading.remove(path)
        }
    }

    /// Forgets every folder read but the one shown: they are read again as
    /// they are asked for.
    func forgetFolders() {
        folderLoadingTimers.values.forEach { $0.cancel() }
        folderLoadingTimers = [:]
        foldersShowingLoading = []
        folderListings = [:]
        folderFailures = [:]
        folderRows = [:]
        folderIndex = [:]
        folderArrangements = [:]
        placeholderIndex = [:]
    }
}
