//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FileBrowser+Folders.swift
//
//  The folders a file panel reads besides the one it shows: the list view's
//  outline branches, read as each is opened, and the column view's columns,
//  the folders on the way to the one shown.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

extension FileBrowser {
    /// Reads `folder` off the main actor, unless it has been read since the
    /// folder shown was last read again, or is being read: as the outline
    /// opens a branch (its placeholder row asks), or the column view shows a
    /// column. A folder that cannot be read has no items.
    ///
    /// Kept only while nothing has moved on: a read cancelled part-way, or
    /// begun before the folder shown was read again, is dropped, and the next
    /// ask reads it afresh.
    func loadFolder(_ folder: URL) async {
        let path = folder.standardizedFileURL.path
        guard folderListings[path] == nil, !foldersReading.contains(path), path != directory.path else { return }
        foldersReading.insert(path)
        defer { foldersReading.remove(path) }
        let started = generation
        let result = await DirectoryListing.load(URL(fileURLWithPath: path), rule: rule)
        guard !Task.isCancelled, generation == started else { return }
        // Named through the folder as it was asked for: a branch beneath a
        // link names its items through the link, as the listing names them.
        let read = (try? result.get()) ?? []
        let arranged = await Self.arrange(read, showsHiddenFiles: showsHiddenFiles, sortOrder: sortOrder)
        guard !Task.isCancelled, generation == started else { return }
        folderListings[path] = read
        folderRows[path] = arranged.rows
        for row in arranged.rows { index(row) }
        attachBranches()
    }

    /// The folders read, arranged again as `key` says: after the folder shown
    /// is, for a new order or the hidden-files switch.
    func arrangeFolders(as key: RefreshKey) async {
        guard !folderListings.isEmpty else { return }
        let listings = folderListings
        var arranged: [String: [FileEntry]] = [:]
        for (path, read) in listings {
            arranged[path] =
                await Self.arrange(read, showsHiddenFiles: key.showsHiddenFiles, sortOrder: key.sortOrder).rows
        }
        guard !Task.isCancelled, refreshKey == key else { return }
        folderRows = arranged
        folderIndex = [:]
        for rows in arranged.values {
            for row in rows { index(row) }
        }
        attachBranches()
    }

    /// Puts each folder read under its row, all the way down, as the
    /// outline's branches: a folder not read yet keeps its placeholder.
    func attachBranches() {
        guard !folderRows.isEmpty else { return }
        for index in rows.indices where rows[index].isFolder {
            rows[index].children = branch(of: rows[index].url)
        }
    }

    /// The rows beneath `folder` in the outline: its items, each folder among
    /// them with its own, or a placeholder where it is not read yet. Recursion
    /// goes only as deep as folders have been read, so a link that leads back
    /// up ends where the reading did.
    private func branch(of folder: URL) -> [FileEntry] {
        guard let items = folderRows[folder.standardizedFileURL.path] else { return [.placeholder(in: folder)] }
        return items.map { item in
            guard item.isFolder else { return item }
            var folder = item
            folder.children = branch(of: item.url)
            return folder
        }
    }

    /// Indexes `row` for the selection's lookups.
    private func index(_ row: FileEntry) {
        folderIndex[row.url] = row
        if let placeholder = row.children?.first, placeholder.isPlaceholder {
            folderIndex[placeholder.url] = placeholder
        }
    }

    /// Before the folder shown becomes `folder`: the folder shown joins the
    /// folders read, and only those on the way to `folder` — the folders above
    /// it, which the column view shows — are kept.
    func keepFolders(onTheWayTo folder: URL) {
        if state == .loaded, let listed, listed.directory.path == directory.path {
            folderListings[directory.path] = listed.entries
            folderRows[directory.path] = rows
        }
        let target = folder.standardizedFileURL.path
        let kept = folderListings.keys.filter { path in
            path == target || path == "/" || target.hasPrefix(path + "/")
        }
        folderListings = folderListings.filter { kept.contains($0.key) }
        folderRows = folderRows.filter { kept.contains($0.key) }
        folderIndex = folderIndex.filter { entry in
            let folder = entry.value.isPlaceholder ? entry.value.placeholderFolder : entry.key.deletingLastPathComponent()
            return kept.contains(folder.standardizedFileURL.path)
        }
    }

    /// Forgets every folder read but the one shown: they are read again as
    /// they are asked for.
    func forgetFolders() {
        folderListings = [:]
        folderRows = [:]
        folderIndex = [:]
    }
}
