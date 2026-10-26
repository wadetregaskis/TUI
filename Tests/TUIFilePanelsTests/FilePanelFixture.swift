//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelFixture.swift
//
//  A small folder tree in a temporary directory, for the file panel tests:
//  never the real home folder.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A temporary folder tree:
///
/// ```
/// <root>/
///   .hidden            (a hidden file)
///   Alpha/             (a folder)
///     inner.txt
///   beta.txt
///   gamma.pdf          (1 KiB)
///   linked -> Alpha    (a symbolic link to a folder)
///   notes.md
/// ```
///
/// Removed by ``remove()``, which a test calls in a `defer` — not in a
/// `deinit`, which ARC may run at the fixture's last use, before the test
/// has finished with the files.
struct FilePanelFixture {
    /// The tree's root.
    let root: URL

    init() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TUIFilePanels-\(UUID().uuidString)", isDirectory: true)
        // The temporary directory is reached through a symbolic link on macOS
        // (/var → /private/var); the panel standardizes the paths it shows, so
        // the fixture's root is the resolved one, and comparisons hold.
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base.resolvingSymlinksInPath()
        let alpha = root.appendingPathComponent("Alpha", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try write("inner", to: alpha.appendingPathComponent("inner.txt"))
        try write("beta", to: url("beta.txt"))
        try Data(repeating: 0x25, count: 1024).write(to: url("gamma.pdf"))
        try write("notes", to: url("notes.md"))
        try write("hidden", to: url(".hidden"))
        try FileManager.default.createSymbolicLink(at: url("linked"), withDestinationURL: alpha)
    }

    /// The item `name` in the root.
    func url(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    /// Deletes the tree.
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }
}
