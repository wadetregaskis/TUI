//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// it is, anything else relative to `base`, the folder shown.
    static func resolve(_ typed: String, relativeTo base: URL, home: URL) -> URL {
        let path = expandingTilde(typed.trimmingCharacters(in: .whitespaces), home: home)
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        return base.appendingPathComponent(path).standardizedFileURL
    }

    /// `typed` with its last component completed among the items of the
    /// folder it names, as a shell's Tab completes one: the one item that
    /// matches, with a `/` after a folder, or as much as every match shares.
    /// Unchanged when nothing matches or the matches share no more.
    ///
    /// Matched by case first and, where nothing matches by case, without it
    /// (a macOS volume ignores case). Hidden items match only a prefix that
    /// begins with a dot.
    static func complete(_ typed: String, relativeTo base: URL, home: URL) -> String {
        let slash = typed.lastIndex(of: "/")
        let folderPart = slash.map { String(typed[...$0]) } ?? ""
        let prefix = slash.map { String(typed[typed.index(after: $0)...]) } ?? typed
        let folder =
            folderPart.isEmpty ? base : resolve(folderPart, relativeTo: base, home: home)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return typed }
        let visible = prefix.hasPrefix(".") ? names : names.filter { !$0.hasPrefix(".") }
        var matches = visible.filter { $0.hasPrefix(prefix) }
        if matches.isEmpty {
            matches = visible.filter { $0.lowercased().hasPrefix(prefix.lowercased()) }
        }
        guard let first = matches.first else { return typed }
        if matches.count == 1 {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(first).path, isDirectory: &isDirectory)
            return folderPart + first + (exists && isDirectory.boolValue ? "/" : "")
        }
        let shared = matches.dropFirst().reduce(first) { commonPrefix($0, $1) }
        return shared.count > prefix.count ? folderPart + shared : typed
    }

    /// `path` with a leading `~` (alone, or before a `/`) made `home`'s path.
    private static func expandingTilde(_ path: String, home: URL) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return home.standardizedFileURL.path + path.dropFirst()
    }

    /// The longest start `a` and `b` share, by character.
    private static func commonPrefix(_ lhs: String, _ rhs: String) -> String {
        String(zip(lhs, rhs).prefix { $0 == $1 }.map(\.0))
    }
}
