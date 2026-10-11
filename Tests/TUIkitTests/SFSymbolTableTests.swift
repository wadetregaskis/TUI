//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SFSymbolTableTests.swift
//
//  Created by LAYERED.work
//  License: MIT

#if canImport(AppKit)
    import Foundation
    import Testing

    @testable import TUIkitStrings

    /// The baked SF Symbols table as data: that it still holds the mapping the
    /// SF Symbols app gave, that every name in it is found, and that nothing
    /// else is. ``SFSymbolTests`` covers what the rest of TUIkit does with it.
    @Suite("SF Symbols table")
    struct SFSymbolTableTests {

        /// FNV-1a (64-bit) of one `name<TAB>CODEPOINT<LF>` line per symbol, in
        /// table order, the codepoint in upper-case hexadecimal: the lines of a
        /// `Tools/GenerateSFSymbols/generate.sh --pairs` file.
        private static func mappingDigest(_ entries: [SFSymbol.Entry]) -> UInt64 {
            var hash: UInt64 = 0xCBF2_9CE4_8422_2325
            for entry in entries {
                let codepoint = entry.glyph.unicodeScalars.first?.value ?? 0
                for byte in "\(entry.name)\t\(String(codepoint, radix: 16, uppercase: true))\n".utf8 {
                    hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
                }
            }
            return hash
        }

        @Test("The table maps every name to the codepoint the SF Symbols app gave it, pair for pair")
        func mappingIsUnchanged() {
            // A change to how the table is stored must leave this alone. A
            // table regenerated from a newer SF Symbols release changes it on
            // purpose: the generator prints the new digest to pin here.
            let all = SFSymbol.all
            #expect(all.count == 8466)
            #expect(Self.mappingDigest(all) == 0x94D6_0238_9810_B4C2)
        }

        @Test("Every name in the table resolves to its own glyph")
        func everyNameResolves() {
            let wrong = SFSymbol.all.filter { SFSymbol.glyph(named: $0.name) != $0.glyph }.map(\.name)
            #expect(wrong.isEmpty, "\(wrong.prefix(5))")
        }

        @Test(
            "A name that is not in the table misses",
            arguments: [
                "",  // empty
                "0", ".",  // sort before the first name, `0.circle`; `0` is a prefix of it
                "zzz0", "zzzz", "~",  // sort after the last, `zzz`
                "star.fil", "0.circl",  // proper prefixes of real names
                "star.fillx", "star.fill.", "zzz.",  // real names plus a suffix
                "STAR.FILL",
                "stär.fill", "star.fill\u{301}", "\u{2B50}\u{FE0F}", "\u{1002C3}",  // not ASCII
                "star.fill\n", "star\nfill", "star\u{0}fill",  // the bytes that end a name, and NUL
                "\u{9}hi", "\u{8}.ar",  // a stored line with its shared-prefix byte
            ])
        func missesAreMisses(name: String) {
            #expect(SFSymbol.glyph(named: name) == nil)
        }

        @Test("A name falling between two names of the table misses, at block edges and inside blocks")
        func absentNamesBetweenNeighboursMiss() {
            let all = SFSymbol.all
            let size = SFSymbol.nameBlockSize
            // `name + "!"` sorts after `name` and before the name after it, as no
            // name holds a `!`. Positions: the last name of a block (so the miss
            // falls between it and the next block's head), and names inside
            // blocks, the last (short) block's head among them.
            let lastHead = (all.count - 1) / size * size
            let blockEnds = [size - 1, 2 * size - 1, 265 * size - 1, lastHead - 1]
            let insideBlocks = [0, 1, size / 2 - 1, 300 * size + size / 2 - 1, lastHead]
            for index in blockEnds + insideBlocks {
                let absent = all[index].name + "!"
                #expect(SFSymbol.glyph(named: absent) == nil, "\(absent)")
            }
            // A block head less its last byte, where that is not a name itself.
            let names = Set(all.map(\.name))
            for head in stride(from: 0, to: all.count, by: size) {
                let shorter = String(all[head].name.dropLast())
                guard !names.contains(shorter) else { continue }
                #expect(SFSymbol.glyph(named: shorter) == nil, "\(shorter)")
            }
        }

        @Test("Queries next to every name answer as the set of names does: their own glyph if a name, else nil")
        func nearMissesAgreeWithTheNames() {
            // Every proper prefix of a name; every name with one byte moved up
            // or down by one; and splices `earlier.prefix(cut) + name.dropFirst(cut)`
            // of two names in one block, `cut` being where `name` leaves the
            // name before it. That cut is where the walk compares a name's
            // suffix, so a walk that kept going past a name that rose above the
            // query would line up its stale match with a later name there
            // (with the walk's `shared < matched` exit deleted, "scape" found
            // scope's glyph).
            let all = SFSymbol.all
            let size = SFSymbol.nameBlockSize
            var glyphs: [String: String] = [:]
            glyphs.reserveCapacity(all.count)
            for entry in all { glyphs[entry.name] = entry.glyph }
            var wrong: [String] = []
            var checked = 0
            func check(_ bytes: [UInt8]) {
                let query = String(unsafeUninitializedCapacity: bytes.count) { $0.initialize(fromContentsOf: bytes) }
                checked += 1
                if SFSymbol.glyph(named: query) != glyphs[query] { wrong.append(query) }
            }
            let names = all.map { Array($0.name.utf8) }
            for (index, name) in names.enumerated() {
                var edited = name
                for position in name.indices {
                    check(Array(name[..<position]))
                    for byte in [name[position] &- 1, name[position] &+ 1] {
                        edited[position] = byte
                        check(edited)
                    }
                    edited[position] = name[position]
                }
                let head = index / size * size
                guard index > head else { continue }
                let cut = zip(names[index - 1], name).prefix { $0 == $1 }.count
                for earlier in names[head..<index] where earlier.count >= cut {
                    check(Array(earlier[..<cut]) + name[cut...])
                }
            }
            #expect(checked > 600_000)
            let wrongCount = wrong.count  // so a failure prints the count, not every query
            #expect(wrongCount == 0, "e.g. \(wrong.prefix(5))")
        }

        @Test("The block index points at each block's head, and each block's first and last names resolve")
        func blockHeadsAndEdges() {
            let all = SFSymbol.all
            let size = SFSymbol.nameBlockSize
            let blocks = SFSymbol.blockStarts.count - 1
            #expect(blocks == (all.count + size - 1) / size)
            // The sentinel is the blob's length: the last name's newline ends it.
            #expect(Int(SFSymbol.blockStarts[blocks]) == SFSymbol.nameBlocks.utf8CodeUnitCount)
            // A head is stored in full where the index points: the name itself.
            var heads: [String] = []
            SFSymbol.nameBlocks.withUTF8Buffer { blob in
                for block in 0..<blocks {
                    let start = Int(SFSymbol.blockStarts[block])
                    var end = start
                    while blob[end] != UInt8(ascii: "\n") { end += 1 }
                    heads.append(String(bytes: blob[start..<end], encoding: .utf8) ?? "")
                }
            }
            let expectedHeads = stride(from: 0, to: all.count, by: size).map { all[$0].name }
            #expect(heads == expectedHeads)
            // The first and last names of blocks at both ends and in the middle;
            // the last block holds what is left over (two names, today).
            for block in [0, 1, blocks / 2, blocks - 2, blocks - 1] {
                let first = block * size
                for index in [first, min(first + size, all.count) - 1] {
                    #expect(SFSymbol.glyph(named: all[index].name) == all[index].glyph, "\(all[index].name)")
                }
            }
        }

        @Test("A bridged NSString without contiguous UTF-8 is looked up through its copied bytes")
        func bridgedStringUsesTheCopyingFallback() throws {
            // Long enough not to become a tagged pointer, and UTF-16 data, which
            // is what leaves the bridged string without contiguous UTF-8 (probed
            // 2026-10-11: built from a Swift string or from characters, an ASCII
            // NSString bridges contiguous, and the fallback is not reached).
            let name = "figure.seated.side.right.windshield.front.and.heat.waves.air.distribution.upper.and.middle.and.lower"
            for (query, expected) in [(name, SFSymbol.glyph(named: name)), (name + "s", nil)] {
                let data = try #require(query.data(using: .utf16LittleEndian))
                let object = try #require(NSString(data: data, encoding: String.Encoding.utf16LittleEndian.rawValue))
                let bridged = object as String
                let isContiguous = bridged.utf8.withContiguousStorageIfAvailable { _ in true } ?? false
                try #require(!isContiguous, "the bridged string must take the fallback path")
                #expect(SFSymbol.glyph(named: bridged) == expected)
            }
            #expect(SFSymbol.glyph(named: name) != nil)
        }
    }
#endif
