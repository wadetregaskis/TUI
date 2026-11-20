//  🖥️ TUI — A Terminal UI framework for Swift
//  PathCompletion.swift
//
//  A typed path, as a shell reads one: `~` for the home folder, relative to
//  the folder shown, and completed with Tab.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// What a panel's go-to field makes of the path typed into it.
enum PathCompletion {
    /// `typed` as a location: `~` and `~/…` from `home`, an absolute path as
    /// it is, anything else relative to `base`, the folder shown. On Windows a
    /// drive alone, `D:`, is that drive's root, not a folder `D:` in the one
    /// shown.
    static func resolve(_ typed: String, relativeTo base: URL, home: URL) -> URL {
        var path = expandingTilde(typed.trimmingCharacters(in: .whitespaces), home: home)
        #if os(Windows)
            if path.count == 2, path.last == ":", let drive = path.first, drive.isASCII, drive.isLetter {
                path += "/"
            }
        #endif
        if isAbsolute(path) { return URL(fileURLWithPath: path).panelStandardized }
        return base.appendingPathComponent(path).panelStandardized
    }

    /// `typed` with its last component completed among the items of the
    /// folder it names, as a shell's Tab completes one: the one item that
    /// matches, with a `/` after a folder, or as much as every match shares.
    /// Unchanged when nothing matches or the matches share no more.
    ///
    /// Matched by case first and, where nothing matches by case, without it
    /// (a macOS volume ignores case). Hidden items match only a prefix that
    /// begins with a dot. On Windows, an item with the hidden attribute
    /// (`AppData`, `NTUSER.DAT`) matches only where no other item does, as
    /// case does above: `A` passes it by, and `AppD` still finds it.
    static func complete(_ typed: String, relativeTo base: URL, home: URL) -> String {
        let slash = typed.lastIndex(where: isSeparator)
        let folderPart = slash.map { String(typed[...$0]) } ?? ""
        let prefix = slash.map { String(typed[typed.index(after: $0)...]) } ?? typed
        let folder =
            folderPart.isEmpty ? base : resolve(folderPart, relativeTo: base, home: home)
        guard let (names, hidden) = items(of: folder) else { return typed }
        let undotted = prefix.hasPrefix(".") ? names : names.filter { !$0.hasPrefix(".") }
        let shown = undotted.filter { !hidden.contains($0) }
        var matches: [String] = []
        for candidates in [shown, undotted] where matches.isEmpty {
            matches = candidates.filter { $0.hasPrefix(prefix) }
            if matches.isEmpty {
                matches = candidates.filter { $0.lowercased().hasPrefix(prefix.lowercased()) }
            }
        }
        guard let first = matches.first else { return typed }
        if matches.count == 1 {
            var isDirectory: ObjCBool = false
            let exists = unsafe FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(first).path, isDirectory: &isDirectory)
            return folderPart + first + (exists && isDirectory.boolValue ? "/" : "")
        }
        let shared = matches.dropFirst().reduce(first) { commonPrefix($0, $1) }
        return shared.count > prefix.count ? folderPart + shared : typed
    }

    /// The names of the items in `folder`, and of those the file system marks
    /// hidden: on Windows by the hidden attribute, from the folder's own
    /// enumeration (``DirectoryListing``); elsewhere none, a dot being the
    /// mark. `nil` where the folder cannot be read.
    private static func items(of folder: URL) -> (names: [String], hidden: Set<String>)? {
        #if os(Windows)
            guard let items = try? DirectoryListing.windowsItems(of: folder) else { return nil }
            return (items.map(\.name), Set(items.filter(\.facts.isHidden).map(\.name)))
        #else
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
            return (names, [])
        #endif
    }

    /// `path` with a leading `~` (alone, or before a `/`) made `home`'s path.
    /// Whether `path` is named from a root rather than from the folder shown:
    /// `/…`, and on Windows a drive's `C:/…` or `C:\\…`, or a share's `\\\\…` — what
    /// a home folder there expands to, which does not start with a slash.
    static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") { return true }
        #if os(Windows)
            if path.hasPrefix("\\") { return true }
            let start = Array(path.prefix(3))
            return start.count == 3 && start[0].isASCII && start[0].isLetter && start[1] == ":"
                && isSeparator(start[2])
        #else
            return false
        #endif
    }

    /// Whether `character` separates a path's components: `/`, and on Windows
    /// its own `\\` as well.
    static func isSeparator(_ character: Character) -> Bool {
        #if os(Windows)
            character == "/" || character == "\\"
        #else
            character == "/"
        #endif
    }

    private static func expandingTilde(_ path: String, home: URL) -> String {
        guard path == "~" || (path.first == "~" && path.dropFirst().first.map(isSeparator) == true) else { return path }
        return home.panelStandardized.path + path.dropFirst()
    }

    /// The longest start `a` and `b` share, by character.
    private static func commonPrefix(_ lhs: String, _ rhs: String) -> String {
        String(zip(lhs, rhs).prefix { $0 == $1 }.map(\.0))
    }
}
