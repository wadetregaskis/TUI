//  🖥️ TUI — A Terminal UI framework for Swift
//  DirectoryListing.swift
//
//  Reading a folder into a file panel's rows: one `FileManager` listing,
//  every value a row shows read and formatted with it, off the main actor.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// What a panel lets the user choose among a folder's items, and how it
/// words them: the half of a listing that depends on the panel, not the disk.
struct FileChoiceRule: Sendable {
    /// The types the panel takes; empty takes every type.
    var allowedContentTypes: [UTType] = []

    /// Whether a file of an allowed type can be chosen. An open panel's files
    /// can; a mover's, whose choice is a folder, cannot.
    var choosesFiles = true

    /// Whether a package — an `.app`, say — is listed as the folder it is,
    /// to be opened, rather than as one file (`.enumeratePackages`).
    var enumeratesPackages = false

    /// The files the panel takes now, where its type pop-up has narrowed or
    /// widened the caller's types: `nil` for ``allowedContentTypes``, empty
    /// for every file (``FileTypeChoice``). Folders are not filtered by it.
    var fileTypes: [UTType]?

    /// A test the caller puts each item's URL to; one it fails cannot be
    /// chosen (`fileDialogURLEnabled(_:)`).
    var urlEnabled: Predicate<URL>?

    /// The locale the sizes and dates are written in.
    var locale = Locale.current

    /// Whether a folder can be chosen, rather than only opened: when a type the
    /// panel takes is one a folder conforms to (`.folder`, `.directory`,
    /// `.item`).
    var choosesFolders: Bool {
        allowedContentTypes.contains { UTType.folder.conforms(to: $0) }
    }

    /// Whether the panel takes an item of `type`, in the folder or file role.
    func allows(_ type: UTType, isFolder: Bool) -> Bool {
        if isFolder { return choosesFolders }
        guard choosesFiles else { return false }
        let types = fileTypes ?? allowedContentTypes
        return types.isEmpty || types.contains { type.conforms(to: $0) }
    }
}

/// Why a folder could not be listed.
struct DirectoryListingFailure: Error, Sendable, Equatable {
    /// The folder's name, for the message the panel shows.
    let folderName: String

    /// The file system's own account of the failure.
    let reason: String
}

/// Reads folders into ``FileEntry`` rows.
enum DirectoryListing {
    /// What a listing reads of each item, in one pass the file system can
    /// answer from the directory itself: `contentsOfDirectory` prefetches them.
    static var keys: [URLResourceKey] {
        var keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey, .fileSizeKey,
            .contentModificationDateKey,
        ]
        #if canImport(UniformTypeIdentifiers)
            keys += [.contentTypeKey, .localizedTypeDescriptionKey]
        #endif
        return keys
    }

    /// Lists `directory` off the main actor, hidden items included (the panel
    /// filters them, so showing them needs no second read).
    ///
    /// - Returns: The items in the order the file system gave them, or why
    ///   the folder could not be read. Empty, if the task was cancelled
    ///   part-way: its caller has moved on and will discard it.
    @concurrent
    static func load(_ directory: URL, rule: FileChoiceRule) async -> Result<[FileEntry], DirectoryListingFailure> {
        read(directory, rule: rule) { Task.isCancelled }
    }

    /// Lists `directory` on the calling thread.
    ///
    /// - Parameter isCancelled: Asked every few hundred items; `true` stops the
    ///   read, which then returns what it has.
    static func read(
        _ directory: URL, rule: FileChoiceRule, isCancelled: () -> Bool = { false }
    ) -> Result<[FileEntry], DirectoryListingFailure> {
        let items: [(name: String, facts: ItemFacts)]
        do {
            #if os(Windows)
                items = try windowsItems(of: directory)
            #else
                items = try FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: keys, options: []
                ).map { ($0.lastPathComponent, ItemFacts(try? $0.resourceValues(forKeys: Set(keys)))) }
            #endif
        } catch {
            return .failure(
                DirectoryListingFailure(folderName: displayName(of: directory), reason: error.localizedDescription))
        }
        let formats = Formats(locale: rule.locale)
        // Each type's kind, worked out once a listing: a folder holds few
        // types, and the conformance walk cost 8% of listing 20,000 files of
        // ten types (106 ms of 1.32 s, debug) before it was kept.
        var kinds: [String: FileKind] = [:]
        var entries: [FileEntry] = []
        entries.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if index % 256 == 255, isCancelled() { break }
            entries.append(
                entry(named: item.name, facts: item.facts, in: directory, rule: rule, formats: formats, kinds: &kinds))
        }
        return .success(entries)
    }

    /// What a row is made of, as the listing read it of an item: the values
    /// `contentsOfDirectory` prefetched, or on Windows the folder's own
    /// enumeration (``windowsItems(of:)``).
    struct ItemFacts {
        var isDirectory = false
        var isPackage = false
        var isHidden = false
        var isSymbolicLink = false
        var size: Int64?
        var modified: Date?
        /// The type the system names, on Apple platforms.
        var contentType: UTType?
        /// The system's words for the type, on Apple platforms and Windows.
        var typeDescription: String?

        /// Where the item leads, for a shortcut file the platform follows
        /// (a Windows `.lnk`, ``ShellShortcut``) whose target exists.
        var shortcutTarget: URL?

        init() {}

        /// From prefetched values; all defaults where they could not be read.
        init(_ values: URLResourceValues?) {
            isDirectory = values?.isDirectory ?? false
            isPackage = values?.isPackage ?? false
            isHidden = values?.isHidden ?? false
            isSymbolicLink = values?.isSymbolicLink ?? false
            size = values?.fileSize.map(Int64.init)
            modified = values?.contentModificationDate
            #if canImport(UniformTypeIdentifiers)
                contentType = values?.contentType
                typeDescription = values?.localizedTypeDescription
            #endif
        }
    }

    /// The name a panel calls a folder by: its last component, or `/` for the
    /// root, whose last component is empty.
    static func displayName(of folder: URL) -> String {
        let name = folder.lastPathComponent
        return name.isEmpty ? folder.path : name
    }

    /// One item's row, from what the listing read of it.
    ///
    /// The row's URL is the folder's with the item's name appended, not the one
    /// the listing returned, which can spell the folder differently: on macOS
    /// it resolves the folder's own path (`/var/…` lists as `/private/var/…`),
    /// and a panel hands back what its user navigated to.
    private static func entry(
        named name: String, facts: ItemFacts, in directory: URL, rule: FileChoiceRule, formats: Formats,
        kinds: inout [String: FileKind]
    ) -> FileEntry {
        let url = directory.appendingPathComponent(name)
        let isSymbolicLink = facts.isSymbolicLink
        let shortcutTarget = facts.shortcutTarget
        let isPackage = facts.isPackage
        var isDirectory = facts.isDirectory
        if let shortcutTarget {
            // A shortcut is a folder where its target is, and has the type its
            // target has, so the panel's types are asked of what it leads to.
            var leadsToDirectory: ObjCBool = false
            isDirectory =
                unsafe FileManager.default.fileExists(atPath: shortcutTarget.path, isDirectory: &leadsToDirectory)
                && leadsToDirectory.boolValue
        } else if isSymbolicLink {
            // A link to a folder opens as one: the link's own values describe
            // the link, so ask what it leads to. `fileExists(atPath:isDirectory:)`
            // follows the link (it is `stat`); `resolvingSymlinksInPath()` does
            // not on WASI, where Foundation answers with the link's own path, and
            // a link to a folder listed as a file (WasmKit, 2026-11-10).
            var leadsToDirectory: ObjCBool = false
            isDirectory =
                unsafe FileManager.default.fileExists(atPath: url.path, isDirectory: &leadsToDirectory)
                && leadsToDirectory.boolValue
        }
        let isFolder = isDirectory && (!isPackage || rule.enumeratesPackages)
        let type =
            shortcutTarget.map { contentType(of: $0, facts: ItemFacts(), isFolder: isFolder) }
            ?? contentType(of: url, facts: facts, isFolder: isFolder)
        let size = isFolder ? nil : facts.size
        var isChoosable = rule.allows(type, isFolder: isFolder)
        if isChoosable, let predicate = rule.urlEnabled {
            isChoosable = (try? predicate.evaluate(url)) ?? false
        }
        let isHidden = facts.isHidden || url.lastPathComponent.hasPrefix(".")
        return FileEntry(
            url: url, name: url.lastPathComponent, isFolder: isFolder, isHidden: isHidden,
            isSymbolicLink: isSymbolicLink, shortcutTarget: shortcutTarget,
            contentType: type, size: size, modified: facts.modified,
            sizeText: size.map(formats.size) ?? "--", modifiedText: facts.modified.map(formats.date) ?? "",
            kind: kind(of: type, facts: facts, isFolder: isFolder), isChoosable: isChoosable,
            fileKind: fileKind(
                of: type, isFolder: isFolder, isSymbolicLink: isSymbolicLink || shortcutTarget != nil, kinds: &kinds))
    }

    /// ``FileKind/of(_:isFolder:isSymbolicLink:)``, a file type's worked out
    /// once a listing and kept in `kinds`.
    private static func fileKind(
        of type: UTType, isFolder: Bool, isSymbolicLink: Bool, kinds: inout [String: FileKind]
    ) -> FileKind {
        guard !isFolder, !isSymbolicLink else { return FileKind.of(type, isFolder: isFolder, isSymbolicLink: isSymbolicLink) }
        if let kept = kinds[type.identifier] { return kept }
        let kind = FileKind.of(type, isFolder: false, isSymbolicLink: false)
        kinds[type.identifier] = kind
        return kind
    }

    /// The type of an item: what the file system says it is, where it says
    /// (Apple platforms read it from Launch Services, which knows a package
    /// and a file with no extension), else a folder for a folder and the type
    /// its extension names for a file, as `UTType(filenameExtension:)` names it.
    private static func contentType(of url: URL, facts: ItemFacts, isFolder: Bool) -> UTType {
        if isFolder { return .folder }
        if let type = facts.contentType { return type }
        return url.pathExtension.isEmpty ? .data : UTType(filenameExtension: url.pathExtension) ?? .data
    }

    /// An item's kind, in words: the system's description where it has one
    /// (localized, on Apple platforms and Windows), the type's own (English) where it
    /// does not, else the extension in capitals ("TOML") or "Document".
    private static func kind(of type: UTType, facts: ItemFacts, isFolder: Bool) -> String {
        if let description = facts.typeDescription { return description }
        if isFolder { return LocalizationService.shared.string(for: .kindFolder) }
        if !type.isDynamic, let description = type.localizedDescription { return description }
        if let name = type.preferredFilenameExtension { return name.uppercased() }
        return LocalizationService.shared.string(for: .kindDocument)
    }

    /// The formats a listing writes its sizes and dates in, made once a listing.
    private struct Formats {
        let sizeStyle: ByteCountFormatStyle
        let dateStyle: Date.FormatStyle

        init(locale: Locale) {
            sizeStyle = ByteCountFormatStyle(style: .file, locale: locale)
            dateStyle = Date.FormatStyle(date: .numeric, time: .shortened, locale: locale)
        }

        func size(_ bytes: Int64) -> String { sizeStyle.format(bytes) }
        func date(_ date: Date) -> String { dateStyle.format(date) }
    }
}
