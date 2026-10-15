//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppKitBridgeTests.swift
//
//  The bridges to Apple's colour types, which live in TUIkitAppKit so that
//  nothing TUIkit is built from imports AppKit — and the guard that keeps it
//  that way.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

#if canImport(AppKit)
    import AppKit
    import TUIkitAppKit
#endif

import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Bridges to AppKit")
struct AppKitBridgeTests {
    #if canImport(AppKit)
        @Test("A colour goes to NSColor and CGColor and comes back the same")
        func colourRoundTrips() {
            let colour = Color(red: 1, green: 0.5, blue: 0)
            let resolved = colour.resolve(in: EnvironmentValues())
            let fromNS = Color(nsColor: NSColor(colour)).resolve(in: EnvironmentValues())
            let fromCG = Color(cgColor: resolved.cgColor).resolve(in: EnvironmentValues())
            for back in [fromNS, fromCG] {
                #expect(abs(back.red - resolved.red) < 0.01)
                #expect(abs(back.green - resolved.green) < 0.01)
                #expect(abs(back.blue - resolved.blue) < 0.01)
            }
        }
    #endif

    /// The rule the module split exists for: no source of a module TUIkit is
    /// built from imports AppKit. A module that did would load SwiftUICore
    /// into every app that imports TUIkit, `internal import` or not, and put
    /// SwiftUI's own `FormatStyle.offset(to:)` and the rest beside TUIkit's.
    ///
    /// Held as a list of what these modules may import, not of what they may
    /// not: AppKit comes in through more frameworks than anyone would list —
    /// PDFKit, WebKit, MapKit, AVKit, SpriteKit, SceneKit, GameplayKit,
    /// StoreKit, MetalKit, QuickLookUI and Quartz each make `NSColor` visible
    /// on macOS (checked 2026-10-05 with `import X; let c = NSColor.red`).
    @Test("No module TUIkit is built from imports anything that could bring AppKit in")
    func noAppKitBelowTheBridges() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        // Every Sources/TUIkit… directory but the bridges themselves and the
        // two no library module depends on: read from the tree, not listed,
        // because the module split gives each planned module a directory of
        // its own (Sources/TUIkitFoundation, Sources/TUIkitLists …), and a
        // list would miss the next one. They may import each other.
        let notBuiltFrom: Set<String> = ["TUIkitAppKit", "TUIkitMacros", "TUIkitMacrosPlugin", "TUIkitWidthCorpus"]
        let modules = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasPrefix("TUIkit") && !notBuiltFrom.contains($0) }
            .sorted()
        #expect(
            ["TUIkit", "TUIkitCore", "TUIkitFoundation", "TUIkitImage", "TUIkitStyling", "TUIkitView"]
                .allSatisfy(modules.contains),
            "the scan finds the framework's directories: \(modules)")
        var offenders: [String] = []
        for module in modules {
            let directory = sources.appendingPathComponent(module)
            let walker = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            for case let file as URL in walker where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for imported in ImportScan.importedModules(in: text)
                where !ImportScan.allowed.contains(imported) && !modules.contains(imported) {
                    offenders.append("\(module)/\(file.lastPathComponent): \(imported)")
                }
            }
        }
        #expect(
            offenders.isEmpty,
            """
            \(offenders): a module not on ImportScan.allowed. Add it there once `import X; \
            let c = NSColor.red` fails to type-check on macOS, i.e. it does not bring AppKit in.
            """)
    }

    /// The scan is only as good as what it recognises as an import, so it is
    /// held to every spelling Swift accepts — and to what is not an import.
    @Test(
        "The guard reads every spelling of an import, and no comment",
        arguments: [
            ("import AppKit", "AppKit"),
            ("import SwiftUICore", "SwiftUICore"),
            ("import struct AppKit.NSColor", "AppKit"),
            ("import class AppKit.NSImage", "AppKit"),
            ("import func Cocoa.NSApplicationMain", "Cocoa"),
            ("@preconcurrency import AppKit.NSImage", "AppKit"),
            ("@_exported import SwiftUI", "SwiftUI"),
            ("@_implementationOnly import AppKit", "AppKit"),
            ("@_spi(Private) @preconcurrency import SwiftUICore", "SwiftUICore"),
            ("internal import AppKit", "AppKit"),
            ("public import Cocoa", "Cocoa"),
            ("package import AppKit", "AppKit"),
            ("    import AppKit  // the bridges", "AppKit"),
            ("import\tAppKit", "AppKit"),
            ("import Foundation; import AppKit", "AppKit"),
            ("/// import AppKit", nil),
            ("// import AppKit", nil),
            ("/* import AppKit */", nil),
            ("/*\n import AppKit\n*/", nil),
            ("let note = \"import AppKit\"", nil),
            ("let glob = \"Sources/*\"\nimport AppKit", "AppKit"),
            ("let glob = #\"Sources/*\"#\nimport AppKit", "AppKit"),
            ("let text = \"\"\"\n  /* not a comment\n  \"\"\"\nimport AppKit", "AppKit"),
            ("#if canImport(AppKit)\n    import AppKit\n#endif", "AppKit"),
            ("let text = \"\"\"\n  a line \\\n  continued /*\n  \"\"\"\nimport AppKit", "AppKit"),
            ("let path = \"\\\"/*\"\nimport AppKit", "AppKit"),
            ("let s = \"\\(x.replacingOccurrences(of: \"/*\", with: \"\"))\"\nimport AppKit", "AppKit"),
            ("let s = \"\\(\"/*\")\"\nimport AppKit", "AppKit"),
            ("let s = \"\\(f(\"a\", g(\")\")))\" + \"/*\"\nimport AppKit", "AppKit"),
            ("let s = #\"\\#(x[\"/*\"])\"#\nimport AppKit", "AppKit"),
            ("import AppKitShim", "AppKitShim"),
            ("import WebKit", "WebKit"),
            ("import Foundation // not AppKit", nil),
        ] as [(String, String?)])
    func importScan(source: String, refused: String?) {
        let found = ImportScan.importedModules(in: source).filter { !ImportScan.allowed.contains($0) }
        #expect(found == (refused.map { [$0] } ?? []), "\(source.debugDescription) → \(found)")
    }
}

/// Reads the modules a Swift source imports, the way the compiler reads an
/// import declaration — for the guard above, which must not be fooled by a
/// spelling it did not think of, nor by a comment.
private enum ImportScan {
    /// The modules TUIkit's own may import: each other (the guard also allows
    /// every module directory it scans, so the split's modules need no entry
    /// here), the standard
    /// libraries of the platforms it builds on, and the Apple frameworks
    /// checked not to bring AppKit (and with it SwiftUICore) in. Anything
    /// else — AppKit, Cocoa, SwiftUI, SwiftUICore, or a framework that
    /// re-exports one of them — fails the guard.
    static let allowed: Set<String> = [
        "TUIkit", "TUIkitCore", "TUIkitStyling", "TUIkitView", "TUIkitImage", "CSTBImage",
        "Foundation", "FoundationEssentials", "FoundationNetworking", "Observation", "Dispatch",
        "Synchronization",
        "Darwin", "Glibc", "Musl", "WASILibc", "ucrt", "WinSDK", "os",
        "CoreGraphics", "CoreText", "ImageIO", "UniformTypeIdentifiers",
        // The symbol effects' types (decisions A35). Checked 2026-10-05 as the
        // rest were: with only `import Symbols`, `NSColor` is not in scope, and
        // neither is SwiftUICore's `FormatStyle.offset(to:)`.
        "Symbols",
    ]

    /// The kinds a scoped import names (`import struct AppKit.NSColor`).
    private static let kinds: Set<Substring> = [
        "typealias", "struct", "class", "enum", "protocol", "let", "var", "func",
    ]

    /// The access levels an import may carry (`internal import AppKit`).
    private static let accessLevels: Set<Substring> = [
        "public", "package", "internal", "fileprivate", "private",
    ]

    /// Every module `source` imports — the top-level module of each import
    /// declaration, the part before any `.` — outside comments.
    static func importedModules(in source: String) -> [String] {
        var modules: [String] = []
        let keyword = Array("import".utf8)
        for bytes in withoutCommentsAndStrings(source).split(separator: Byte.newline) {
            // Only a line that says `import` is read as text: the guard reads
            // some twelve megabytes of source, and almost none of it is.
            guard bytes.firstRange(of: keyword) != nil, let line = String(bytes: bytes, encoding: .utf8) else {
                continue
            }
            for statement in line.split(separator: ";") {
                if let module = importedModule(statement) { modules.append(module) }
            }
        }
        return modules
    }

    /// The module one statement imports, or `nil` if it is no import.
    private static func importedModule(_ statement: Substring) -> String? {
        var words = statement.split(whereSeparator: \.isWhitespace)[...]
        // Attributes (`@preconcurrency`, `@_exported`, `@_spi(Name)`) and an
        // access level come first, in any order the compiler takes.
        while let first = words.first, first.hasPrefix("@") || accessLevels.contains(first) {
            words = words.dropFirst()
        }
        guard words.first == "import" else { return nil }
        words = words.dropFirst()
        if let first = words.first, kinds.contains(first) { words = words.dropFirst() }
        guard let path = words.first else { return nil }
        return path.split(separator: ".").first.map(String.init)
    }

    /// `source`'s UTF-8 with its comments and string literals blanked,
    /// newlines kept: `//` to the end of the line, `/* … */` nested as Swift nests
    /// them, and `"…"`, `"""…"""` and raw `#"…"#` strings — so neither a
    /// commented-out import nor a `/*` inside a string (which would open a
    /// comment that hides the imports after it) can fool the scan.
    ///
    /// Walks UTF-8 bytes, not characters: every delimiter is ASCII, and the
    /// guard reads some twelve megabytes of source.
    private static func withoutCommentsAndStrings(_ source: String) -> [UInt8] {
        let bytes = Array(source.utf8)
        var kept: [UInt8] = []
        kept.reserveCapacity(bytes.count)
        var index = 0
        func pair(_ first: UInt8, _ second: UInt8) -> Bool {
            index + 1 < bytes.count && bytes[index] == first && bytes[index + 1] == second
        }
        while index < bytes.count {
            if pair(Byte.slash, Byte.slash) {
                while index < bytes.count, bytes[index] != Byte.newline { index += 1 }
            } else if pair(Byte.slash, Byte.star) {
                var depth = 0
                repeat {
                    if pair(Byte.slash, Byte.star) {
                        depth += 1
                        index += 2
                    } else if pair(Byte.star, Byte.slash) {
                        depth -= 1
                        index += 2
                    } else {
                        if bytes[index] == Byte.newline { kept.append(Byte.newline) }
                        index += 1
                    }
                } while depth > 0 && index < bytes.count
            } else if bytes[index] == Byte.quote || (bytes[index] == Byte.hash && opensRawString(bytes, at: index)) {
                index = endOfString(bytes, from: index, keepingNewlinesIn: &kept)
            } else {
                kept.append(bytes[index])
                index += 1
            }
        }
        return kept
    }

    /// The ASCII bytes the scan looks for.
    private enum Byte {
        static let slash = UInt8(ascii: "/")
        static let star = UInt8(ascii: "*")
        static let quote = UInt8(ascii: "\"")
        static let hash = UInt8(ascii: "#")
        static let backslash = UInt8(ascii: "\\")
        static let newline = UInt8(ascii: "\n")
        static let openParen = UInt8(ascii: "(")
        static let closeParen = UInt8(ascii: ")")
    }

    /// Whether the `#`s at `index` open a raw string (`#"`), rather than a
    /// directive (`#if`).
    private static func opensRawString(_ bytes: [UInt8], at index: Int) -> Bool {
        var cursor = index
        while cursor < bytes.count, bytes[cursor] == Byte.hash { cursor += 1 }
        return cursor < bytes.count && bytes[cursor] == Byte.quote
    }

    /// The index just past the string literal that opens at `index`, with
    /// the newlines a multi-line one spans appended to `kept`. A string on
    /// one line ends at the line's end at the latest.
    private static func endOfString(_ bytes: [UInt8], from index: Int, keepingNewlinesIn kept: inout [UInt8]) -> Int {
        var cursor = index
        var hashes = 0
        while bytes[cursor] == Byte.hash {
            hashes += 1
            cursor += 1
        }
        let isMultiline =
            cursor + 2 < bytes.count && bytes[cursor + 1] == Byte.quote && bytes[cursor + 2] == Byte.quote
        let quotes = isMultiline ? 3 : 1
        cursor += quotes
        while cursor < bytes.count {
            if let open = interpolationOpening(bytes, at: cursor, hashes: hashes) {
                // `\(…)` (`\#(…)` in a raw string) is code, with strings of
                // its own: one of them holding `"` or `/*` must not end this
                // string, nor open a comment.
                cursor = endOfInterpolation(bytes, from: open, keepingNewlinesIn: &kept)
                continue
            }
            if bytes[cursor] == Byte.backslash, hashes == 0 {
                // An escape, or a multi-line string's line continuation,
                // whose newline still ends a line.
                if cursor + 1 < bytes.count, bytes[cursor + 1] == Byte.newline { kept.append(Byte.newline) }
                cursor += 2
                continue
            }
            if bytes[cursor] == Byte.newline {
                guard isMultiline else { return cursor }
                kept.append(Byte.newline)
            }
            if closes(bytes, at: cursor, quotes: quotes, hashes: hashes) { return cursor + quotes + hashes }
            cursor += 1
        }
        return cursor
    }

    /// The index just past the `(` of an interpolation that starts at
    /// `index` — a backslash, the string's `hashes` hashes, then `(` — or
    /// `nil` if none does.
    private static func interpolationOpening(_ bytes: [UInt8], at index: Int, hashes: Int) -> Int? {
        guard bytes[index] == Byte.backslash else { return nil }
        let paren = index + 1 + hashes
        guard paren < bytes.count, bytes[paren] == Byte.openParen,
            (0..<hashes).allSatisfy({ bytes[index + 1 + $0] == Byte.hash })
        else { return nil }
        return paren + 1
    }

    /// The index just past the `)` that closes an interpolation whose code
    /// starts at `index`, stepping over its own parentheses and strings.
    private static func endOfInterpolation(_ bytes: [UInt8], from index: Int, keepingNewlinesIn kept: inout [UInt8]) -> Int {
        var cursor = index
        var depth = 1
        while cursor < bytes.count {
            switch bytes[cursor] {
            case Byte.quote:
                cursor = endOfString(bytes, from: cursor, keepingNewlinesIn: &kept)
                continue
            case Byte.hash where opensRawString(bytes, at: cursor):
                cursor = endOfString(bytes, from: cursor, keepingNewlinesIn: &kept)
                continue
            case Byte.openParen:
                depth += 1
            case Byte.closeParen:
                depth -= 1
                if depth == 0 { return cursor + 1 }
            case Byte.newline:
                kept.append(Byte.newline)
            default:
                break
            }
            cursor += 1
        }
        return cursor
    }

    /// Whether `quotes` quotes and then `hashes` hashes start at `index`: the
    /// end of a string opened with them.
    private static func closes(_ bytes: [UInt8], at index: Int, quotes: Int, hashes: Int) -> Bool {
        guard index + quotes + hashes <= bytes.count else { return false }
        return (0..<quotes).allSatisfy { bytes[index + $0] == Byte.quote }
            && (0..<hashes).allSatisfy { bytes[index + quotes + $0] == Byte.hash }
    }
}
