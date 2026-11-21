//  🖥️ TUI — A Terminal UI framework for Swift
//  ShellShortcut+Windows.swift
//
//  Where a Windows shortcut (`.lnk`) leads, so a file panel can follow it as
//  it follows a symbolic link.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import TUICore
import WinSDK

/// A Windows shortcut file: what Explorer, the Start menu and a Desktop
/// point at other files and folders with.
enum ShellShortcut {
    /// Whether an item named `name` is a shortcut, by its extension, as the
    /// shell knows one.
    static func isShortcut(named name: String) -> Bool {
        (name as NSString).pathExtension.caseInsensitiveCompare("lnk") == .orderedSame
    }

    /// The file or folder the shortcut at `path` leads to, where it leads to
    /// one that exists: `nil` for a shortcut to something with no path (File
    /// Explorer's, a Control Panel item's) and for one whose target is gone, so
    /// either is listed as the file it is.
    ///
    /// Read as the shell stores it (`IShellLinkW`, loaded through
    /// `IPersistFile`), its environment strings expanded (`%USERPROFILE%`), and
    /// never resolved (`IShellLinkW::Resolve`), which can search the disk for a
    /// moved target or show a dialog. Measured 2026-11-20: shortcuts to a
    /// folder, a file and an environment string read as their paths; a
    /// missing target's path is answered, and is refused here; File Explorer's
    /// answers `S_FALSE` and no path.
    static func target(ofShortcutAt path: String) -> URL? {
        guard let target = WindowsCOM.withApartment({ storedTarget(path) }),
            FileManager.default.fileExists(atPath: target)
        else { return nil }
        return URL(fileURLWithPath: target)
    }

    /// The path the shortcut at `path` stores, or `nil`.
    private static func storedTarget(_ path: String) -> String? {
        var clsid = CLSID_ShellLink
        var iid = IID_IShellLinkW
        var made: UnsafeMutableRawPointer?
        guard unsafe CoCreateInstance(&clsid, nil, DWORD(CLSCTX_INPROC_SERVER.rawValue), &iid, &made) == S_OK,
            let made = unsafe made
        else { return nil }
        let link = unsafe made.assumingMemoryBound(to: IShellLinkW.self)
        defer { _ = unsafe link.pointee.lpVtbl.pointee.Release(link) }
        var fileIID = IID_IPersistFile
        var persisted: UnsafeMutableRawPointer?
        guard unsafe link.pointee.lpVtbl.pointee.QueryInterface(link, &fileIID, &persisted) == S_OK,
            let persisted = unsafe persisted
        else { return nil }
        let file = unsafe persisted.assumingMemoryBound(to: IPersistFile.self)
        defer { _ = unsafe file.pointee.lpVtbl.pointee.Release(file) }
        let wide = Array(path.utf16) + [0]
        guard unsafe file.pointee.lpVtbl.pointee.Load(file, wide, DWORD(STGM_READ)) == S_OK else { return nil }
        // The longest path Windows has, with its `\\?\` prefix.
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        guard unsafe link.pointee.lpVtbl.pointee.GetPath(link, &buffer, Int32(buffer.count), nil, 0) == S_OK else {
            return nil
        }
        let target = String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
        return target.isEmpty ? nil : target
    }
}

#endif
