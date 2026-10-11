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

/// The symbol `SFSymbol.isFontAvailable` asks CoreText to draw. Any symbol in
/// the font would do; the emitter stops if this one ever leaves the table.
let fontProbeName = "star.fill"

/// Names per block of the front-coded name table: every 16th name is stored
/// in full, and the 15 after it each against the name before it. Blocks of 16
/// were measured against 32 and 64 and against the 2026-10 table (one string
/// per name, with an offset each): see README.md, "Why this shape".
let nameBlockSize = 16

/// FNV-1a (64-bit) of one `name<TAB>CODEPOINT<LF>` line per pair, in order,
/// the codepoint in upper-case hexadecimal (the lines of a `--pairs` file).
/// `SFSymbolTableTests` pins it, so a change to how the table is stored cannot
/// change the mapping unnoticed; a table regenerated from a newer SF Symbols
/// release changes it on purpose, and the run prints the value to pin.
func mappingDigest(_ pairs: [(name: String, codepoint: UInt32)]) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for pair in pairs {
        for byte in "\(pair.name)\t\(String(pair.codepoint, radix: 16, uppercase: true))\n".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }
    return hash
}

/// Emits the generated Swift source: the names front-coded in a `StaticString`,
/// an index of where each block starts, and the codepoints, all compile-time
/// literals with no `String` in storage, so a lookup parses nothing:
///   - `nameBlocks`: a `StaticString` of every name, sorted ascending, each
///     ended by a newline (the last one too), in blocks of `nameBlockSize`. A
///     block's first name (its head) is stored in full; each other name as one
///     byte, how many leading bytes it shares with the name before it, then
///     the rest of it. The byte is written as a `\u{…}` escape, so the literal
///     keeps one name to a line and a head reads as itself.
///   - `blockStarts`: `[UInt32]`, blocks + 1 entries: the byte offset of each
///     block's head, then the blob's length, so block `b` is the bytes
///     `blockStarts[b] ..< blockStarts[b + 1]`.
///   - `packedCodepointOffsets`: `[UInt64]`, each name's `codepoint - 0x100000`
///     packed four to an element, the first in the high 16 bits (so the hex
///     reads in table order); the last element's unused lanes are zero.
///     Packed because the optimiser folds an array literal element by element:
///     the same offsets as a `[UInt16]` of 8466 (16,932 bytes; packed, 16,936
///     with the last element's two unused lanes) cost a clean release build
///     four times the SIL optimisation (see README.md, "Why this shape").
/// And one constant beside them, `fontProbeScalar`: the codepoint of
/// `fontProbeName`, so `SFSymbol.isFontAvailable` probes CoreText without
/// searching the names.
func emitSource(pairs: [(name: String, codepoint: UInt32)]) -> String {
    // The representation relies on names of printable ASCII (so raw-byte order
    // equals Swift `String` order — what makes the binary search correct — and
    // a name holds no newline, which ends it, and no `\` or `"`, so it is
    // written into the literal as it is), on strictly ascending names (each is
    // stored against the one before it), and on PUA codepoints that fit a
    // UInt16 offset. Fail loudly at generation time if any of them breaks.
    for pair in pairs {
        precondition(
            !pair.name.isEmpty
                && pair.name.utf8.allSatisfy { (0x21...0x7E).contains($0) && $0 != 0x5C && $0 != 0x22 },
            "a name must be printable ASCII, without a backslash or a quote: \(pair.name)")
        precondition(
            pair.codepoint >= 0x10_0000 && pair.codepoint - 0x10_0000 <= 0xFFFF,
            "codepoint outside the UInt16 PUA window: \(pair.name)")
    }
    for (previous, next) in zip(pairs, pairs.dropFirst()) {
        precondition(
            previous.name.utf8.lexicographicallyPrecedes(next.name.utf8),
            "names not strictly ascending: \(previous.name), \(next.name)")
    }
    guard let fontProbe = pairs.first(where: { $0.name == fontProbeName }) else {
        preconditionFailure("the font probe's symbol is missing: \(fontProbeName)")
    }
    let fontProbeHex = String(fontProbe.codepoint, radix: 16, uppercase: true)

    // Front-code: a head in full, then per name its shared-prefix length (one
    // byte below 0x80, so one UTF-8 byte in the StaticString) and its suffix.
    // Every suffix is non-empty: a name sharing all of itself with the name
    // before it would be a prefix of that name, and so sort before it.
    var blobLength = 0
    var lines: [String] = []
    var blockStarts: [UInt32] = []
    for (index, pair) in pairs.enumerated() {
        let name = Array(pair.name.utf8)
        if index % nameBlockSize == 0 {
            blockStarts.append(UInt32(blobLength))
            lines.append(pair.name)
            blobLength += name.count
        } else {
            let previous = Array(pairs[index - 1].name.utf8)
            var shared = 0
            while shared < min(previous.count, name.count), previous[shared] == name[shared] { shared += 1 }
            precondition(shared < 0x80, "shares 128 bytes or more with the name before it: \(pair.name)")
            let suffix = String(decoding: name[shared...], as: UTF8.self)
            lines.append("\\u{\(String(shared, radix: 16, uppercase: true))}" + suffix)
            blobLength += 1 + name.count - shared
        }
        blobLength += 1  // the newline that ends every name
    }
    blockStarts.append(UInt32(blobLength))
    // The literal's text: one name to a line, and an empty line before the
    // closing delimiter so the last name is newline-ended too.
    let nameBlocks = lines.joined(separator: "\n")

    let offsets = pairs.map { UInt16($0.codepoint - 0x10_0000) }
    var packed: [String] = []
    for groupStart in stride(from: 0, to: offsets.count, by: 4) {
        let group = offsets[groupStart..<min(groupStart + 4, offsets.count)]
        let lanes = group.map { String($0, radix: 16, uppercase: true) }
            .map { String(repeating: "0", count: 4 - $0.count) + $0 }
        let padding = Array(repeating: "0000", count: 4 - lanes.count)
        packed.append("0x" + (lanes + padding).joined(separator: "_"))
    }
    let startsLiteral = wrapElements(blockStarts.map { String($0) })
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
    //  why). \(pairs.count) symbols, sorted by name and front-coded in blocks of
    //  \(nameBlockSize). `SFSymbol` binary-searches the block heads through
    //  `blockStarts`, then walks one block — no String, no runtime parsing.
    //  Gated to Apple platforms — SF Symbols never render elsewhere — so no other
    //  platform carries the weight.

    // swiftlint:disable file_length

    #if canImport(AppKit)

    extension SFSymbol {
        /// Number of symbols in the baked table.
        static let bakedCount = \(pairs.count)

        /// The codepoint of `\(fontProbeName)`, the symbol `isFontAvailable` asks
        /// CoreText to draw. A constant, so the font probe searches no names, and
        /// on a Mac without the SF Symbols font `canRender(named:)` answers
        /// without reading the table.
        static let fontProbeScalar: Unicode.Scalar = \"\\u{\(fontProbeHex)}\"

        /// Names per block of `nameBlocks`; the last block holds the rest.
        static let nameBlockSize = \(nameBlockSize)

        /// Every name, sorted ascending, each ended by a newline (the last one
        /// too), front-coded in blocks of `nameBlockSize`: a block's first name,
        /// its head, in full; every other name as one byte, how many leading
        /// bytes it shares with the name before it (written `\\u{…}`), then the
        /// rest of it. One name to a line. A `StaticString` — static bytes in
        /// the binary, never a `String`. Indexed via `blockStarts`.
        static let nameBlocks: StaticString = \"\"\"
    \(nameBlocks)

    \"\"\"

        /// Byte offset of each block's head in `nameBlocks`, then the blob's
        /// length: block `b` is `nameBlocks[blockStarts[b] ..< blockStarts[b + 1]]`.
        /// \(blockStarts.count) entries (blocks + 1).
        static let blockStarts: [UInt32] = [
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
        Data(
            """
            wrote \(pairs.count) symbols (\(source.utf8.count) bytes) to \(outputPath)
            mapping digest 0x\(String(mappingDigest(pairs), radix: 16, uppercase: true)) \
            (SFSymbolTableTests pins it: a new mapping changes it, a new format must not)

            """.utf8))
} catch {
    FileHandle.standardError.write(Data("error: writing \(outputPath): \(error)\n".utf8))
    exit(1)
}
