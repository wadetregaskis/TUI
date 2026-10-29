//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelPathBar.swift
//
//  The path bar above a file panel's folder: a button to the folder above,
//  and the folder's path as a segmented control, a segment per folder on the
//  way, as a macOS path control has one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIChrome
import TUIFoundation
import TUIPickers

/// The path of the folder a panel shows, after a button to the folder above,
/// and before the view switcher and the Preview button.
///
/// The path is a path control, as macOS draws one (`NSPathControl`): a
/// segment per folder from the root — or from the home folder, written `~`,
/// as a shell prompt writes it — to the folder shown, each its own target
/// under the pointer, and a click on one goes there. It is a segmented
/// ``Picker`` whose selection is the folder shown, so the keys are a segmented
/// control's (one Tab stop; ← and → move among the segments, Space or Return
/// goes to the one under the cursor) and the folder shown is the segment
/// drawn as chosen.
///
/// Too narrow for every segment, the path keeps its first and as many of its
/// last as fit, with a `…` segment between them for the folders left out,
/// which goes to the deepest of them; narrower still, the `…` and the folder
/// shown; and then the folder's name is shortened in the middle
/// (``FilePanelPathSegment/fitting(_:width:controlSize:)``).
struct FilePanelPathBar: View {
    let browser: FileBrowser

    /// The folder the path abbreviates as `~`.
    let home: URL

    /// How the panel shows the folder, which the view switcher at the bar's
    /// end chooses.
    let viewMode: Binding<FilePanelViewMode>

    /// Whether the preview shows, which the Preview button after the view
    /// switcher opens and closes (``FilePanelPreviewToggle``).
    let showsPreview: Binding<Bool>

    /// The size the path control is drawn at, which decides what its
    /// segments' chrome costs.
    @Environment(\.controlSize) private var controlSize

    /// The enclosing-folder button's glyph: ↰ (U+21B0), an arrow up and to
    /// the leading side, as a macOS panel's toolbar would show "enclosing
    /// folder". Neutral East Asian width, so one cell everywhere; a new
    /// chrome glyph, so a width-corpus row (`chrome_enclosing_folder`).
    static let enclosingFolderSymbol = "\u{21B0}"

    var body: some View {
        HStack(spacing: 1) {
            enclosingFolderButton
            // A reader for the width the path has, one row tall: the
            // segments that fit are chosen for it.
            GeometryReader { proxy in
                pathControl(width: proxy.size.width)
            }
            .frame(height: 1)
            FilePanelViewModePicker(mode: viewMode)
            FilePanelPreviewToggle(isOn: showsPreview)
        }
    }

    /// The path control, `width` cells wide at most.
    private func pathControl(width: Int) -> some View {
        let browser = browser
        let segments = FilePanelPathSegment.fitting(
            FilePanelPathSegment.all(of: browser.directory, home: home), width: width, controlSize: controlSize)
        // No label: an empty one reserves nothing, and the segments say
        // what the control is.
        return Picker(
            "",
            selection: Binding(
                get: { browser.directory.path },
                set: { browser.open(URL(fileURLWithPath: $0, isDirectory: true)) })
        ) {
            ForEach(segments, id: \.path) { segment in
                Text(verbatim: segment.label).tag(segment.path)
            }
        }
        .pickerStyle(.segmented)
    }

    /// The button to the folder above: in the link style, so the glyph in the
    /// accent and in its own cell, with no cells kept for a focus marker it
    /// never shows; lifted under the pointer, and dimmed at the root, which
    /// has no folder above it. Not a Tab stop, as a macOS panel's toolbar buttons
    /// are not in its key view loop: its key is Backspace in the
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

/// One segment of a file panel's path control: a folder on the way to the one
/// shown, or the `…` that stands for several.
struct FilePanelPathSegment: Equatable {
    /// What the segment shows: the folder's name, `~` for the home folder, `/`
    /// for the root, or `…`.
    let label: String

    /// The `…` segment's label, as a truncated text marks what it leaves out.
    static let ellipsis = "\u{2026}"

    /// The folder a click on the segment goes to: its own, or for a `…` the
    /// deepest of the folders it stands for. A path, not a URL, so that the
    /// segment of the folder shown is the picker's selection however a URL
    /// spells the folder (with a trailing slash or none).
    let path: String

    /// The segments of `folder`'s path, from the root, or from `home`, which
    /// is written `~`, when the folder is in it.
    static func all(of folder: URL, home: URL) -> [Self] {
        let path = folder.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        var segments: [Self]
        var rest: Substring
        if homePath.count > 1, path == homePath || path.hasPrefix(homePath + "/") {
            segments = [Self(label: "~", path: homePath)]
            rest = path.dropFirst(homePath.count)
        } else {
            segments = [Self(label: "/", path: "/")]
            rest = Substring(path)
        }
        var walked = segments[0].path == "/" ? "" : segments[0].path
        for name in rest.split(separator: "/") {
            walked += "/" + name
            segments.append(Self(label: String(name), path: walked))
        }
        return segments
    }

    /// The cells a segmented control of `segments` takes at `controlSize`:
    /// its end caps, each label with its padding either side, and a rule
    /// between each two — the segmented picker's own sums
    /// (`_PickerSegmentsCore`).
    static func width(of segments: [Self], controlSize: ControlSize) -> Int {
        let padding = controlSize.padding(regular: 1)
        let caps = controlSize.drawsEndCaps ? 2 : 0
        let labels = segments.reduce(0) { $0 + $1.label.strippedLength + 2 * padding }
        return caps + labels + max(0, segments.count - 1)
    }

    /// As much of `segments` as fits in `width` cells: all of them; else the
    /// first, a `…` for the folders left out and as many of the last as fit;
    /// else the `…` and the last, with the last's name shortened in the
    /// middle if it must be. A `…` goes to the deepest folder it stands for.
    /// A path of two segments keeps both, the last shortened, since a `…`
    /// would stand for the first alone.
    static func fitting(_ segments: [Self], width: Int, controlSize: ControlSize) -> [Self] {
        guard let last = segments.last else { return [] }
        if Self.width(of: segments, controlSize: controlSize) <= width { return segments }
        let count = segments.count
        // Keep the first and the last `kept`; `…` stands for the ones between.
        if count > 2 {
            for kept in stride(from: count - 2, through: 1, by: -1) {
                let hidden = segments[count - kept - 1]
                let candidate =
                    [segments[0], Self(label: ellipsis, path: hidden.path)]
                    + segments.suffix(kept)
                if Self.width(of: candidate, controlSize: controlSize) <= width { return candidate }
            }
        }
        // The `…`, or the first itself where it is the only one left out.
        var tail = [last]
        if count == 2 {
            tail.insert(segments[0], at: 0)
        } else if count > 2 {
            tail.insert(Self(label: ellipsis, path: segments[count - 2].path), at: 0)
        }
        let chrome = Self.width(of: tail, controlSize: controlSize) - last.label.strippedLength
        let shortened = last.label.truncatedToWidth(max(1, width - chrome), mode: .middle)
        tail[tail.count - 1] = Self(label: shortened, path: last.path)
        return tail
    }
}
