//  🖥️ TUI — A Terminal UI framework for Swift
//  FolderPath.swift
//
//  A folder as a file panel names it: standardized, and with the folder above
//  it, on every platform, a Windows drive's root among them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

extension URL {
    /// This location as a file panel names it: `standardizedFileURL`, its `.`
    /// and `..` taken out, everywhere but Windows.
    ///
    /// On Windows Foundation's standardizing loses the drive at its root
    /// (Swift 6.3.3 and 6.4.2, measured 2026-11-18): `C:\` became the folder
    /// `C:` inside the working directory, and so did `C:\Users`'s parent, so a
    /// panel could never show a drive's root, nor go up to one. There the
    /// panel takes the `.` and `..` out itself and keeps the drive
    /// (``FolderPath/standardizedOnWindows(_:)``).
    var panelStandardized: URL {
        FolderPath.standardizing?()
        #if os(Windows)
            return FolderPath.standardizedOnWindows(self)
        #else
            return standardizedFileURL
        #endif
    }
}

/// How a panel walks between folders by their paths.
enum FolderPath {
    /// Told of each ``Foundation/URL/panelStandardized``, for a test that
    /// counts them in a frame: a standardization costs some 6 µs (release,
    /// macOS 26), so one per row drawn is a frame's budget gone in a folder
    /// of thousands (`FilePanelColumnViewTests`); `nil`, and nothing told,
    /// everywhere else.
    @TaskLocal static var standardizing: TaskLocalReporter<Void>?

    /// `path` ending in a `/`, as the start of the paths inside it: `/`
    /// stays `/`, and a Windows drive's `C:/` stays `C:/`.
    static func withSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    /// The folder holding `folder`, standardized; `nil` at a root, which has
    /// none: `/`, and on Windows a drive's.
    static func parent(of folder: URL) -> URL? {
        let folder = folder.panelStandardized
        #if os(Windows)
            if driveRoot(of: folder.path) == folder.path { return nil }
        #endif
        let parent = folder.deletingLastPathComponent().panelStandardized
        return parent.path == folder.path ? nil : parent
    }

    #if os(Windows)
        /// The root of the drive `path` is on, `C:/` for `C:/Users` or `C:`
        /// alone, as Foundation spells a Windows path's (with `/`); `nil` for
        /// a path on no drive.
        static func driveRoot(of path: String) -> String? {
            let start = Array(path.prefix(3))
            guard start.count >= 2, start[0].isASCII, start[0].isLetter, start[1] == ":" else { return nil }
            guard start.count == 2 || start[2] == "/" || start[2] == "\\" else { return nil }
            return String(start[0]) + ":/"
        }

        /// `url` with its `.` and `..` taken out, kept on its drive: a `..` at
        /// the drive's root stays there, as Windows reads one. A path on no
        /// drive is Foundation's to standardize.
        static func standardizedOnWindows(_ url: URL) -> URL {
            let path = url.path
            guard let root = driveRoot(of: path) else { return url.standardizedFileURL }
            var components: [Substring] = []
            for component in path.dropFirst(2).split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
                switch component {
                case ".": continue
                case "..": _ = components.popLast()
                default: components.append(component)
                }
            }
            return URL(fileURLWithPath: root + components.joined(separator: "/"), isDirectory: url.hasDirectoryPath)
        }
    #endif
}
