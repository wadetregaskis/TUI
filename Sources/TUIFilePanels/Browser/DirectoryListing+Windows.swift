//  🖥️ TUI — A Terminal UI framework for Swift
//  DirectoryListing+Windows.swift
//
//  Reading a folder on Windows from its own enumeration, which holds each
//  item's attributes, size and time: no item is opened, so none can fail.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import WinSDK

extension DirectoryListing {
    /// The items of `directory`, each with what its row is made of, from the
    /// folder's enumeration (`FindFirstFileExW`): the attributes, the size and
    /// the time of each, which the file system keeps in the folder.
    ///
    /// Not `FileManager`, which on Windows (Swift 6.3.3 and 6.4.2, measured
    /// 2026-11-18) reads each item by opening it:
    /// - A file the system holds open (`pagefile.sys`, `NTUSER.DAT`) and a
    ///   junction whose folder denies listing (`Application Data`, `My
    ///   Documents`, kept in each profile for old programs) failed to read, and
    ///   listed as a visible file with no size, no time, and no way in: 13 of
    ///   38 items in a profile folder.
    /// - `contentsOfDirectory(at:)` with its keys prefetched throws for the
    ///   whole folder where one item fails so, or is a link that leads nowhere,
    ///   and read by name an item at a time a folder took 3 to 8 times as long
    ///   as here (68–85 ms against 11–26 ms for 246 items, and 2.3 s for
    ///   `System32`'s 4,557).
    ///
    /// A link (a symbolic link, or a junction) is a link, as `FileManager`
    /// reports one; whether it leads to a folder is asked of where it leads,
    /// as for every platform's link (`entry`).
    ///
    /// Each pointer is handed to a function by name rather than to a closure:
    /// Swift 6.2 and 6.3 count a closure taking a pointer as an unsafe
    /// expression and 6.4 does not, so no spelling of one is clean on all
    /// three, and a function's reference is unsafe to every one of them.
    ///
    /// - Throws: Foundation's error for the folder, where it cannot be listed,
    ///   so the panel's message reads as it does on every platform.
    static func windowsItems(of directory: URL) throws -> [(name: String, facts: ItemFacts)] {
        guard let pattern = unsafe directory.withUnsafeFileSystemRepresentation(searchPattern),
            let items = unsafe pattern.withCString(encodedAs: UTF16.self, find)
        else {
            // Foundation's error says why in the words every platform's does.
            return try foundationItems(of: directory)
        }
        // A shortcut is followed as a symbolic link is (`ShellShortcut`).
        return items.map { item in
            guard !item.facts.isDirectory, ShellShortcut.isShortcut(named: item.name) else { return item }
            var facts = item.facts
            facts.shortcutTarget = ShellShortcut.target(
                ofShortcutAt: directory.appendingPathComponent(item.name).path)
            return (item.name, facts)
        }
    }

    /// What finds every item in the folder at `path`, its native path:
    /// `C:\Users\*` for `C:\Users`.
    private static func searchPattern(_ path: UnsafePointer<CChar>?) -> String? {
        guard let path = unsafe path else { return nil }
        let native = unsafe String(cString: path)
        return native.hasSuffix("\\") || native.hasSuffix("/") ? native + "*" : native + "\\*"
    }

    /// The items `pattern` finds, less `.` and `..`; `nil` where the folder
    /// cannot be read.
    private static func find(_ pattern: UnsafePointer<UInt16>) -> [(name: String, facts: ItemFacts)]? {
        var data = WIN32_FIND_DATAW()
        let found = unsafe FindFirstFileExW(
            pattern, FindExInfoBasic, &data, FindExSearchNameMatch, nil, DWORD(FIND_FIRST_EX_LARGE_FETCH))
        guard let handle = unsafe found, unsafe handle != INVALID_HANDLE_VALUE else { return nil }
        defer { _ = unsafe FindClose(handle) }
        var items: [(name: String, facts: ItemFacts)] = []
        var typeNames: [String: String?] = [:]
        repeat {
            let name = Self.name(of: data)
            if name != ".", name != ".." {
                var facts = Self.facts(of: data)
                if !facts.isDirectory { facts.typeDescription = typeName(of: name, kept: &typeNames) }
                items.append((name, facts))
            }
        } while unsafe FindNextFileW(handle, &data)
        return items
    }

    /// What Windows calls a file of `name`'s type, in its own words and
    /// language, as Explorer's Type column does ("Text Document", "TOML
    /// File"); `nil` where it says nothing. Asked of the extension alone
    /// (`SHGetFileInfoW` with `SHGFI_USEFILEATTRIBUTES`, which opens nothing),
    /// once a listing for each: about 160 µs an answer, off the main thread and
    /// without COM (measured 2026-11-20).
    private static func typeName(of name: String, kept: inout [String: String?]) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        if let known = kept[ext] { return known }
        let named = unsafe (ext.isEmpty ? "file" : "file." + ext).withCString(encodedAs: UTF16.self, shellTypeName)
        kept[ext] = named
        return named
    }

    /// `SHGetFileInfoW`'s type name for the file name at `path`.
    private static func shellTypeName(_ path: UnsafePointer<UInt16>) -> String? {
        var info = unsafe SHFILEINFOW()
        let flags = UINT(SHGFI_TYPENAME | SHGFI_USEFILEATTRIBUTES)
        guard
            unsafe SHGetFileInfoW(
                path, DWORD(FILE_ATTRIBUTE_NORMAL), &info, UINT(MemoryLayout<SHFILEINFOW>.size), flags) != 0
        else { return nil }
        // A C array, imported as a tuple of code units: read through a mirror,
        // as `ConsoleFont` reads its face name.
        let units = unsafe Mirror(reflecting: info.szTypeName).children.compactMap { $0.value as? WCHAR }
        let typeName = String(decoding: units.prefix { $0 != 0 }, as: UTF16.self)
        return typeName.isEmpty ? nil : typeName
    }

    /// What the enumeration found of one item.
    private static func facts(of data: WIN32_FIND_DATAW) -> ItemFacts {
        let attributes = data.dwFileAttributes
        var facts = ItemFacts()
        facts.isDirectory = attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0
        facts.isHidden = attributes & DWORD(FILE_ATTRIBUTE_HIDDEN) != 0
        // A reparse point's tag is in `dwReserved0`: a symbolic link's or a
        // junction's makes it a link; others (a cloud file's placeholder, a
        // deduplicated file) are the file or folder they stand for.
        facts.isSymbolicLink =
            attributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) != 0
            && (data.dwReserved0 == DWORD(IO_REPARSE_TAG_SYMLINK) || data.dwReserved0 == DWORD(IO_REPARSE_TAG_MOUNT_POINT))
        facts.size = Int64(data.nFileSizeHigh) << 32 | Int64(data.nFileSizeLow)
        facts.modified = date(of: data.ftLastWriteTime)
        return facts
    }

    /// The item's name, from the record's fixed array of UTF-16 code units.
    private static func name(of data: WIN32_FIND_DATAW) -> String {
        let units = unsafe withUnsafeBytes(of: data.cFileName, codeUnits)
        return String(decoding: units.prefix { $0 != 0 }, as: UTF16.self)
    }

    /// `bytes` as UTF-16 code units.
    private static func codeUnits(_ bytes: UnsafeRawBufferPointer) -> [UInt16] {
        unsafe Array(bytes.bindMemory(to: UInt16.self))
    }

    /// A `FILETIME`, 100-nanosecond ticks since 1601, as a date; `nil` for
    /// none (0).
    private static func date(of time: FILETIME) -> Date? {
        let ticks = UInt64(time.dwHighDateTime) << 32 | UInt64(time.dwLowDateTime)
        guard ticks > 0 else { return nil }
        // 11,644,473,600 seconds from 1601 to 1970.
        return Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
    }

    /// The items by `FileManager`, by name, each read one by one: for a folder
    /// the enumeration could not open, so its error is Foundation's.
    private static func foundationItems(of directory: URL) throws -> [(name: String, facts: ItemFacts)] {
        let keySet = Set(keys)
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).map { name in
            let values = try? directory.appendingPathComponent(name).resourceValues(forKeys: keySet)
            return (name, ItemFacts(values))
        }
    }
}

#endif
