//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelPathBar.swift
//
//  The path bar above a file panel's folder: the folder's path, after a
//  button to the folder above.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitChrome
import TUIkitFoundation

/// The path of the folder a panel shows, after a button to the folder above.
struct FilePanelPathBar: View {
    let browser: FileBrowser

    /// The folder the path abbreviates as `~`.
    let home: URL

    /// The enclosing-folder button's glyph: ↰ (U+21B0), an arrow up and to
    /// the leading side, as a macOS panel's toolbar would show "enclosing
    /// folder". Neutral East Asian width, so one cell everywhere; a new
    /// chrome glyph, so a width-corpus row (`chrome_enclosing_folder`).
    static let enclosingFolderSymbol = "\u{21B0}"

    var body: some View {
        HStack(spacing: 1) {
            enclosingFolderButton
            Text(Self.displayPath(of: browser.directory, home: home))
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    /// The button to the folder above: in the link style, so the glyph in the
    /// accent and in its own cell, with no cells kept for a focus marker it
    /// never shows; lifted under the pointer, and dimmed at the root, which
    /// has no folder above it. Not a Tab stop, as a macOS panel's toolbar buttons
    /// are not in its key view loop: its keys are ← and Backspace in the
    /// folder's rows. macOS's ⌘↑ cannot be offered, since a key press never
    /// carries Command (`KeyPress.modifiers`).
    private var enclosingFolderButton: some View {
        let browser = browser
        return Button {
            browser.goUp()
        } label: {
            Text(verbatim: Self.enclosingFolderSymbol)
        }
        .buttonStyle(.link)
        .focusable(false)
        .disabled(browser.isAtRoot)
        .help(LocalizationService.shared.string(for: LocalizationKey.FilePanel.enclosingFolder))
    }

    /// `folder`'s path as a shell prompt writes it: the home folder as `~`.
    nonisolated static func displayPath(of folder: URL, home: URL) -> String {
        let path = folder.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard homePath.count > 1 else { return path }
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
