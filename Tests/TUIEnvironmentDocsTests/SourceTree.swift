//  🖥️ TUI — A Terminal UI framework for Swift
//  SourceTree.swift
//
//  Reading the repository's text, for the tests that hold the table to it. By
//  bytes, not regular expressions: it runs over every source file in the package.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

enum SourceTree {
    /// The repository this file is in.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TUIEnvironmentDocsTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()

    /// The contents of the file at `path`, relative to ``root``.
    static func text(of path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The files under `directory`, relative to ``root``, with one of `extensions`.
    /// Skips what a build, a package manager or a tool's output leaves there.
    static func files(under directory: String, extensions: Set<String>) -> [URL] {
        let start = root.appendingPathComponent(directory)
        guard
            let walker = FileManager.default.enumerator(
                at: start, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        var found: [URL] = []
        for case let file as URL in walker {
            if ["node_modules", "__pycache__", "dist", "__Snapshots__"].contains(file.lastPathComponent) {
                walker.skipDescendants()
            } else if extensions.contains(file.pathExtension) {
                found.append(file)
            }
        }
        return found
    }

    /// The bytes of `url`, or none where it isn't readable.
    static func bytes(of url: URL) -> [UInt8] {
        (try? Data(contentsOf: url)).map(Array.init) ?? []
    }

    /// The text of `url`, or none where it isn't readable.
    static func string(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Every `TUI_` name in `bytes`, whole words in capitals, so neither
    /// `SWIFTUI_MODULES` nor the resource bundle `TUI_TUIStrings`.
    static func tuiNames(in bytes: [UInt8]) -> Set<String> {
        let prefix = Array("TUI_".utf8)
        var names: Set<String> = []
        var index = 0
        while index + prefix.count <= bytes.count {
            guard bytes[index] == prefix[0], Array(bytes[index..<index + prefix.count]) == prefix else {
                index += 1
                continue
            }
            let start = index
            index += prefix.count
            while index < bytes.count, isWordByte(bytes[index]) { index += 1 }
            let word = bytes[start..<index]
            let startsWhole = start == 0 || !isWordByte(bytes[start - 1])
            if startsWhole, word.count > prefix.count, word.allSatisfy(isCapitalsByte) {
                names.insert(String(bytes: word, encoding: .utf8) ?? "")
            }
        }
        return names
    }

    /// Every string literal in `bytes` that's a name in capitals: `"TERM"`, `"NO_COLOR"`.
    static func capitalLiterals(in bytes: [UInt8]) -> Set<String> {
        let quote = UInt8(ascii: "\"")
        var names: Set<String> = []
        var index = 0
        while index < bytes.count {
            guard bytes[index] == quote else {
                index += 1
                continue
            }
            var end = index + 1
            while end < bytes.count, isCapitalsByte(bytes[end]) { end += 1 }
            if end < bytes.count, bytes[end] == quote, end > index + 1, isLetter(bytes[index + 1]) {
                names.insert(String(bytes: bytes[index + 1..<end], encoding: .utf8) ?? "")
            }
            index = end
        }
        return names
    }

    /// Whether a Swift file's text reads the environment in one of the ways the
    /// package does. Wide on purpose: a file that matches and reads nothing costs at
    /// most a name in ``InternalVariables/notVariables``, and one that reads and
    /// doesn't match would hide a variable from the test.
    static func readsEnvironment(_ bytes: [UInt8]) -> Bool {
        let text = String(bytes: bytes, encoding: .utf8) ?? ""
        return ["getenv(", "processInfo.environment", "environment[", "env[", "environment: [String: String]", "Context.environment"]
            .contains { text.contains($0) }
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "_") || isLetter(byte) || (byte >= 0x30 && byte <= 0x39)
            || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
    }

    private static func isCapitalsByte(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "_") || isLetter(byte) || (byte >= 0x30 && byte <= 0x39)
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")
    }
}
