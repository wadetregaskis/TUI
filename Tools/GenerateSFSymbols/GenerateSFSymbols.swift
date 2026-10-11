//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GenerateSFSymbols.swift
//
//  Created by LAYERED.work
//  License: MIT

//  Regenerates `Sources/TUIkitStrings/SFSymbols/SFSymbolTable.generated.swift` — the
//  baked SF Symbol name → Plane-16 PUA codepoint table that backs
//  `SFSymbol` / `Label(_:systemImage:)`.
//
//  WHY THIS EXISTS (and why it is a Tool, not part of the package build):
//
//  Apple ships the authoritative name → codepoint mapping inside the SF Symbols
//  app, in an OBFUSCATED (AES-encrypted) custom OpenType table named `symp` in
//  `SFSymbolsFallback.otf`. The app decrypts it at runtime via a private Swift
//  routine, `CoreGlyphsLib.Crypton.decryptObfuscatedFontTable(tableTag:from:)`.
//  Rather than re-implement (and chase) Apple's cipher, this generator calls
//  that routine directly — pointed at the app's own font and frameworks — so the
//  data we bake is exactly what the app itself uses. The result is a plain
//  functional mapping (symbol name ↔ Unicode codepoint), which carries no
//  creative expression and is committed as a generated source file.
//
//  This is DEVELOPER tooling, run by hand on macOS with the SF Symbols app
//  installed (mirroring `Tools/Profiling`, which likewise needs Instruments). It
//  is not compiled as part of TUIkit and end users never run it. If a future SF
//  Symbols release changes the table format or the decryptor's mangled name,
//  re-derive them and update this file — the baked table keeps working until you
//  regenerate it.
//
//  USAGE (see README.md for the exact swiftc invocation and dlopen flags):
//
//      Tools/GenerateSFSymbols/generate.sh
//      Tools/GenerateSFSymbols/generate.sh "/Applications/SF Symbols.app"
//      Tools/GenerateSFSymbols/generate.sh --pairs FILE
//
//  which compiles this file with dynamic-lookup linking and runs it, writing the
//  generated table into Sources/. Pass an explicit app path as the first
//  argument to override auto-detection, or `--pairs FILE` to read the mapping
//  from a file of `name<TAB>codepoint` lines instead of the app: on a machine
//  without the app, or to re-emit the committed mapping in a changed format.

import CoreText
import Foundation

// MARK: - Private decryptor binding
//
// `CoreGlyphsLib.Crypton.decryptObfuscatedFontTable(tableTag: UInt32,
//  from: CTFont) -> Data?` is a STATIC method on an internal Swift type. Its
// mangled symbol is bound here via `@_silgen_name` and resolved at run time by
// `dlopen`-ing CoreGlyphsLib (link with `-Xlinker -undefined -Xlinker
// dynamic_lookup`). The method ignores its metatype `self`, so calling it as a
// free function is sound. The trailing `FZ` marks it static; `tF` would be an
// instance method.
@_silgen_name(
    "$s13CoreGlyphsLib7CryptonV26decryptObfuscatedFontTable8tableTag4from10Foundation4DataVSgs6UInt32V_So9CTFontRefatFZ"
)
func cryptonDecryptObfuscatedFontTable(tableTag: UInt32, from: CTFont) -> Data?

// MARK: - Output format
//
// See `emitSource(pairs:)` below and README.md: a `StaticString` blob of the
// names, their byte offsets, and their codepoint offsets packed four to a
// `UInt64` — compile-time constants all, so a lookup parses nothing.

// MARK: - Locate the SF Symbols app

/// Returns the font URL and the framework load order for the first SF Symbols
/// app found (an explicit path argument wins, then Beta, then release).
func locateApp(explicit: String?) -> (font: String, frameworks: [String])? {
    let candidates = [explicit, "/Applications/SF Symbols Beta.app", "/Applications/SF Symbols.app"]
        .compactMap { $0 }
    for app in candidates where FileManager.default.fileExists(atPath: app) {
        let font = "\(app)/Contents/Resources/Fonts/SFSymbolsFallback.otf"
        guard FileManager.default.fileExists(atPath: font) else { continue }
        let shared = "\(app)/Contents/Frameworks/SFSymbolsShared.framework/Versions/A"
        return (
            font,
            [
                "\(shared)/Frameworks/CoreGlyphsLib.framework/Versions/A/CoreGlyphsLib",
                "\(shared)/SFSymbolsShared",
                "\(app)/Contents/Frameworks/CoreSVG.framework/Versions/A/CoreSVG",
            ]
        )
    }
    return nil
}

// MARK: - Minimal quote-aware CSV

/// Splits one CSV record into fields, honouring `"`-quoted fields (which may
/// contain commas, newlines, and `""`-escaped quotes). Returns the fields and
/// the index just past the record's terminating newline (or end of input).
func parseCSVRecord(_ scalars: [UnicodeScalar], from start: Int) -> (fields: [String], next: Int) {
    var fields: [String] = []
    var field = ""
    var index = start
    var inQuotes = false
    while index < scalars.count {
        let scalar = scalars[index]
        if inQuotes {
            if scalar == "\"" {
                if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                    field.unicodeScalars.append("\"")
                    index += 2
                    continue
                }
                inQuotes = false
            } else {
                field.unicodeScalars.append(scalar)
            }
            index += 1
        } else {
            switch scalar {
            case "\"": inQuotes = true; index += 1
            case ",": fields.append(field); field = ""; index += 1
            case "\n": fields.append(field); return (fields, index + 1)
            case "\r": index += 1
            default: field.unicodeScalars.append(scalar); index += 1
            }
        }
    }
    fields.append(field)
    return (fields, index)
}

/// Parses the decrypted `symp` CSV into name → codepoint pairs, using the header
/// row to find the `Name` and `PUAs` columns.
func parsePairs(from csv: Data) -> [(name: String, codepoint: UInt32)] {
    let scalars = Array(String(decoding: csv, as: UTF8.self).unicodeScalars)
    var cursor = 0
    let header = parseCSVRecord(scalars, from: cursor)
    cursor = header.next
    guard
        let nameColumn = header.fields.firstIndex(of: "Name"),
        let puaColumn = header.fields.firstIndex(of: "PUAs")
    else {
        FileHandle.standardError.write(Data("error: CSV header missing Name / PUAs columns\n".utf8))
        return []
    }

    var pairs: [(name: String, codepoint: UInt32)] = []
    while cursor < scalars.count {
        let record = parseCSVRecord(scalars, from: cursor)
        cursor = record.next
        let fields = record.fields
        guard nameColumn < fields.count, puaColumn < fields.count else { continue }
        let name = fields[nameColumn].trimmingCharacters(in: .whitespaces)
        // A row may list more than one PUA; the first is the canonical glyph.
        let pua = fields[puaColumn]
            .split(whereSeparator: { $0 == ";" || $0 == "," }).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !name.isEmpty, !pua.isEmpty, let value = UInt32(pua, radix: 16) else { continue }
        pairs.append((name, value))
    }
    return pairs
}

// MARK: - Encode

/// Wraps array elements to a readable column width. Every element carries a
/// trailing comma (Swift allows a trailing comma on the last one), so a line
/// break never drops a separator.
func wrapElements(_ values: [String]) -> String {
    var lines: [String] = []
    var line = ""
    for value in values {
        let piece = "\(value),"
        if line.isEmpty {
            line = piece
        } else if line.count + 1 + piece.count > 96 {
            lines.append(line)
            line = piece
        } else {
            line += " \(piece)"
        }
    }
    if !line.isEmpty { lines.append(line) }
    return lines.joined(separator: "\n")
}

/// Emits the generated Swift source in the "name blob + offsets" representation
/// (benchmarked as the fastest to look up and compile of the correct options,
/// with no `String` in storage). Three native compile-time literals:
///   - `nameBlob`: a `StaticString` of every name, sorted ascending and
///     newline-separated with NO trailing newline — greppable line by line.
///   - `nameStarts`: `[UInt32]`, n+1 entries. Name `i` is the blob bytes
///     `nameStarts[i] ..< nameStarts[i+1] - 1` (the `-1` drops the separating
///     newline; the sentinel `nameStarts[n]` = blob length + 1 makes the last
///     name resolve the same way).
///   - `packedCodepointOffsets`: `[UInt64]`, each name's `codepoint - 0x100000`
///     packed four to an element, the first in the high 16 bits (so the hex
///     reads in table order); the last element's unused lanes are zero.
///     Packed because the optimiser folds an array literal element by element:
///     the same offsets as a `[UInt16]` of 8466 (16,932 bytes; packed, 16,936
///     with the last element's two unused lanes) cost a clean release build
///     four times the SIL optimisation (see README.md, "Why this shape").
func emitSource(pairs: [(name: String, codepoint: UInt32)]) -> String {
    // The representation relies on ASCII names (so raw-byte order equals Swift
    // `String` order — what makes the binary search correct) and PUA codepoints
    // that fit a UInt16 offset. Fail loudly at generation time if either breaks.
    for pair in pairs {
        precondition(pair.name.utf8.allSatisfy { $0 < 0x80 }, "non-ASCII name: \(pair.name)")
        precondition(
            pair.codepoint >= 0x10_0000 && pair.codepoint - 0x10_0000 <= 0xFFFF,
            "codepoint outside the UInt16 PUA window: \(pair.name)")
    }

    let nameBlob = pairs.map(\.name).joined(separator: "\n")

    var starts: [UInt32] = []
    starts.reserveCapacity(pairs.count + 1)
    var offset: UInt32 = 0
    for pair in pairs {
        starts.append(offset)
        offset += UInt32(pair.name.utf8.count) + 1  // +1 for the newline separator
    }
    starts.append(offset)  // sentinel = blob length + 1

    let offsets = pairs.map { UInt16($0.codepoint - 0x10_0000) }
    var packed: [String] = []
    for groupStart in stride(from: 0, to: offsets.count, by: 4) {
        let group = offsets[groupStart..<min(groupStart + 4, offsets.count)]
        let lanes = group.map { String($0, radix: 16, uppercase: true) }
            .map { String(repeating: "0", count: 4 - $0.count) + $0 }
        let padding = Array(repeating: "0000", count: 4 - lanes.count)
        packed.append("0x" + (lanes + padding).joined(separator: "_"))
    }
    let startsLiteral = wrapElements(starts.map { String($0) })
    let offsetsLiteral = wrapElements(packed)

    return """
    //  🖥️ TUIkit — Terminal UI Kit for Swift
    //  SFSymbolTable.generated.swift
    //
    //  Created by LAYERED.work
    //  License: MIT

    //  GENERATED — do not edit by hand.
    //
    //  Produced by `Tools/GenerateSFSymbols/generate.sh` from the SF Symbols
    //  app's authoritative name → codepoint table (see that tool for how and
    //  why). \(pairs.count) symbols, sorted by name. `SFSymbol` binary-searches
    //  `nameBlob` directly through `nameStarts` — no String, no runtime parsing.
    //  Gated to Apple platforms — SF Symbols never render elsewhere — so no other
    //  platform carries the weight.

    // swiftlint:disable file_length

    #if canImport(AppKit)

    extension SFSymbol {
        /// Number of symbols in the baked table.
        static let bakedCount = \(pairs.count)

        /// Every name, sorted ascending, newline-separated (no trailing newline).
        /// A `StaticString` — static bytes in the binary, never a `String`.
        /// Greppable verbatim. Indexed via `nameStarts`.
        static let nameBlob: StaticString = \"\"\"
    \(nameBlob)
    \"\"\"

        /// Byte offsets into `nameBlob`: name `i` is
        /// `nameBlob[nameStarts[i] ..< nameStarts[i + 1] - 1]`. \(starts.count) entries (n + 1).
        static let nameStarts: [UInt32] = [
    \(startsLiteral)
        ]

        /// Codepoint of name `i` as `codepoint - 0x100000` (reconstruct with
        /// `0x100000 + offset`), packed four to an element: name `i`'s is the
        /// 16 bits of element `i / 4` that lane `i % 4` names, lane 0 the
        /// highest. Read through `codepointOffset(at:)`.
        static let packedCodepointOffsets: [UInt64] = [
    \(offsetsLiteral)
        ]
    }

    #endif

    """
}

// MARK: - Main

/// Decrypts the SF Symbols app's `symp` table (the app at `explicitPath`, or
/// the first one found) and parses its name → codepoint pairs.
func readPairsFromApp(explicitPath: String?) -> [(name: String, codepoint: UInt32)] {
    guard let app = locateApp(explicit: explicitPath) else {
        FileHandle.standardError.write(
            Data("error: SF Symbols app not found (pass its path, or --pairs FILE)\n".utf8))
        exit(1)
    }

    for framework in app.frameworks where dlopen(framework, RTLD_NOW) == nil {
        let message = dlerror().map { String(cString: $0) } ?? "unknown error"
        FileHandle.standardError.write(Data("warning: dlopen failed for \(framework): \(message)\n".utf8))
    }

    let fontURL = URL(fileURLWithPath: app.font) as CFURL
    guard
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as? [CTFontDescriptor],
        let descriptor = descriptors.first
    else {
        FileHandle.standardError.write(Data("error: could not read font descriptors from \(app.font)\n".utf8))
        exit(1)
    }
    let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)

    // 'symp' big-endian table tag.
    guard let csv = cryptonDecryptObfuscatedFontTable(tableTag: 0x73_79_6D_70, from: font) else {
        FileHandle.standardError.write(
            Data("error: decryptObfuscatedFontTable returned nil (cipher or symbol changed?)\n".utf8))
        exit(1)
    }
    return parsePairs(from: csv)
}

/// Reads `name<TAB>codepoint` lines, the codepoint in hexadecimal as the app's
/// `PUAs` column spells it (`star.fill<TAB>1002C3`). Empty lines are skipped;
/// any other line that is not a name, one tab and a hexadecimal codepoint
/// stops the run, so a mangled file never becomes a smaller table.
func readPairs(fromFile path: String) -> [(name: String, codepoint: UInt32)] {
    guard let data = FileManager.default.contents(atPath: path) else {
        FileHandle.standardError.write(Data("error: cannot read \(path)\n".utf8))
        exit(1)
    }
    var pairs: [(name: String, codepoint: UInt32)] = []
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
    for (number, line) in lines.enumerated() where !line.isEmpty {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 2, !fields[0].isEmpty, let codepoint = UInt32(fields[1], radix: 16) else {
            FileHandle.standardError.write(Data("error: \(path):\(number + 1): not name<TAB>hex codepoint\n".utf8))
            exit(1)
        }
        pairs.append((String(fields[0]), codepoint))
    }
    return pairs
}

let arguments = Array(CommandLine.arguments.dropFirst())
var pairs: [(name: String, codepoint: UInt32)]
if arguments.first == "--pairs" {
    guard arguments.count == 2 else {
        FileHandle.standardError.write(Data("usage: GenerateSFSymbols [APP_PATH | --pairs FILE]\n".utf8))
        exit(1)
    }
    pairs = readPairs(fromFile: arguments[1])
} else {
    pairs = readPairsFromApp(explicitPath: arguments.first)
}
pairs.sort { $0.name < $1.name }
guard !pairs.isEmpty else {
    FileHandle.standardError.write(Data("error: no name/codepoint pairs parsed\n".utf8))
    exit(1)
}

let source = emitSource(pairs: pairs)

let outputPath = "Sources/TUIkitStrings/SFSymbols/SFSymbolTable.generated.swift"
do {
    try source.write(toFile: outputPath, atomically: true, encoding: .utf8)
    FileHandle.standardError.write(
        Data("wrote \(pairs.count) symbols (\(source.utf8.count) bytes) to \(outputPath)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("error: writing \(outputPath): \(error)\n".utf8))
    exit(1)
}
