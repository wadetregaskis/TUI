//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FileEntry.swift
//
//  One item of a folder as a file panel lists it: what the file system says
//  about it, read once off the main actor, and the words its row shows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// One item of a folder, as a file panel's table shows it.
///
/// Everything a row draws or sorts by is read and formatted when the folder
/// is listed (`DirectoryListing`), off the main actor, so that drawing a row
/// costs no file-system call and no formatter.
struct FileEntry: Identifiable, Sendable {
    /// The item's location, as the folder's listing named it: a symbolic link
    /// is its own URL, not its target's.
    let url: URL

    /// The item's name: the URL's last path component.
    let name: String

    /// Whether a panel opens the item as a folder rather than taking it as a
    /// file: a directory, or a symbolic link to one — but not a package
    /// (an `.app`, say) unless the panel enumerates packages, as a macOS panel
    /// shows a package as one file.
    let isFolder: Bool

    /// Whether the file system hides the item: a name that begins with a dot,
    /// or (on macOS) the hidden flag.
    let isHidden: Bool

    /// Whether the item is a symbolic link, which a panel chooses as the item
    /// it leads to unless told not to (`fileDialogImportsUnresolvedAliases(_:)`).
    let isSymbolicLink: Bool

    /// The item's content type.
    let contentType: UTType

    /// The item's size in bytes, for a file; `nil` for a folder, or a file whose
    /// size could not be read.
    let size: Int64?

    /// When the item's contents last changed, if that could be read.
    let modified: Date?

    /// The size as its column shows it: "12 KB", or "--" for a folder.
    let sizeText: String

    /// The modification date as its column shows it, in the panel's locale.
    let modifiedText: String

    /// What kind of item it is, in words: the system's own description of the
    /// type where it has one ("PDF document", "Folder").
    let kind: String

    /// Whether the panel lets the user choose the item: its type is one the
    /// caller allows and the caller's URL predicate does not refuse it. A
    /// folder that cannot be chosen can still be opened.
    let isChoosable: Bool

    var id: URL { url }

    /// Whether the row is drawn dimmed: an item that can be neither chosen
    /// nor opened — a file of a type the panel does not take.
    var isDimmed: Bool { !isChoosable && !isFolder }

    /// The URL a panel hands its caller for the item: a symbolic link's
    /// target, when links are resolved, and otherwise the item's own.
    func chosenURL(resolvingLinks: Bool) -> URL {
        isSymbolicLink && resolvingLinks ? url.resolvingSymlinksInPath() : url
    }

    /// The size the Size column sorts by: a folder before every file.
    var sortSize: Int64 { size ?? -1 }

    /// The date the Date Modified column sorts by: an unreadable date first.
    var sortDate: Date { modified ?? .distantPast }

    /// The name the Name column shows: a folder's ends in a slash, as `ls -F`
    /// marks one, so a folder reads as one without a glyph that some terminals
    /// draw at another width.
    var displayName: String { isFolder ? name + "/" : name }
}
