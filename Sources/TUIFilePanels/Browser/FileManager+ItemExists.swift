//  🖥️ TUI — A Terminal UI framework for Swift
//  FileManager+ItemExists.swift
//
//  Whether a name in a folder is taken, a link that leads nowhere included:
//  what a panel asks before it saves, or makes a folder, under a name.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension FileManager {
    /// Whether anything has the name `path`: a file, a folder, or a symbolic
    /// link, whether or not it leads anywhere — `lstat`'s view.
    ///
    /// Not `fileExists(atPath:)`, which follows a link (it is `stat`), and so
    /// calls a dangling link's name free: a save panel chose it without asking
    /// to replace it, and the app then replaced the link, or wrote through it.
    func itemExists(atPath path: String) -> Bool {
        (try? attributesOfItem(atPath: path)) != nil
    }
}
