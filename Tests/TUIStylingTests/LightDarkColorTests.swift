//  🖥️ TUI — A Terminal UI framework for Swift
//  LightDarkColorTests.swift
//
//  A colour with a light and a dark value of its own (an asset catalogue's
//  colour set, a dynamic `NSColor`), kept as its place in the process-wide,
//  value-keyed table of (light, dark) pairs and chosen where it is resolved
//  (decisions B-D6M-4, the owner's ruling B-D6M-1 option 3).
//
//  Every test here makes pairs no other test makes (each draws its own
//  components), but sharing the table could not disturb them anyway: a pair's
//  place is found by the pair, and a place never changes once given.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIStyling

@Suite("Light-and-dark colours")
struct LightDarkColorTests {
    private static let light = Color.rgb(204, 102, 51)
    private static let dark = Color.rgb(16, 128, 255)

    private func made(_ light: Color = Self.light, _ dark: Color = Self.dark) throws -> Color {
        try #require(Color.lightDark(light: light, dark: dark))
    }

    @Test("A pair keeps two bytes in the colour, which stays five bytes with no padding")
    func layout() throws {
        #expect(MemoryLayout<Color.LightDarkIndex>.size == 2)
        #expect(MemoryLayout<Color.LightDarkIndex>.alignment == 1, "a UInt16 would align Color to two: stride 6")
        #expect(MemoryLayout<Color>.size == 5)
        #expect(MemoryLayout<Color>.stride == 5)
        guard case .lightDark = try made().value else {
            Issue.record("not a light-and-dark colour: \(try made())")
            return
        }
    }

    @Test("Resolved, it is the value for the palette's scheme, its alpha carried")
    func resolvesByScheme() throws {
        let colour = try made()
        #expect(colour.resolve(with: NamedColourPagePalette(background: .rgb(250, 250, 250))) == Self.light)
        #expect(colour.resolve(with: NamedColourPagePalette(background: .rgb(10, 10, 10))) == Self.dark)
        let faded = try made(Color.rgb(204, 102, 52).opacity(0.5), Color.rgb(16, 128, 254).opacity(0.5))
        let resolved = faded.resolve(with: NamedColourPagePalette(background: .rgb(10, 10, 10)))
        #expect(resolved.value == .rgb(red: 16, green: 128, blue: 254))
        #expect(resolved.alpha == faded.alpha && faded.alpha == 128)
        // A further opacity composes with it, as on any colour.
        #expect(faded.opacity(0.5).resolve(with: NamedColourPagePalette(background: .rgb(10, 10, 10))).alpha == 64)
    }

    @Test("Unresolved, as a body measures it, it is the light value")
    func unresolvedIsLight() throws {
        let colour = try made()
        #expect(colour.rgbComponents! == (204, 102, 51))
        #expect(colour.estimatedRGB! == (204, 102, 51))
        #expect(colour.downsampledToPalette256() == Self.light.downsampledToPalette256())
        #expect(!colour.isTerminalDefined)
        #expect(colour.description == "#CC6633FF light, #1080FFFF dark")
    }

    @Test("The same pair is the same colour, however often and wherever it is made")
    func equality() throws {
        let first = try made()
        let second = try made()
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(try made(Self.dark, Self.light) != first, "the pair is ordered: light, then dark")
        #expect(first != Self.light, "a light-and-dark colour is not its light value, as a named colour is not")
    }

    @Test("One colour twice is that colour, with no table entry")
    func samePairIsPlain() {
        let before = LightDarkColorTable.shared.count
        let plain = Color.rgb(1, 2, 250)
        #expect(Color.lightDark(light: plain, dark: plain) == plain)
        #expect(Color.lightDark(light: .red, dark: .red) == .red)
        #expect(LightDarkColorTable.shared.count >= before)  // others may add; this one did not need to
    }

    @Test("A pair that is not two plain colours of one alpha is not kept: the caller chooses now")
    func unkeptPairs() {
        #expect(Color.lightDark(light: .rgb(1, 2, 3), dark: Color.rgb(4, 5, 6).opacity(0.5)) == nil, "two alphas")
        #expect(Color.lightDark(light: .rgb(1, 2, 3), dark: .red) == nil, "a named colour")
        #expect(Color.lightDark(light: .palette.accent, dark: .rgb(1, 2, 3)) == nil, "a palette role")
        #expect(Color.lightDark(light: .ansi(.red), dark: .rgb(1, 2, 3)) == nil, "a terminal slot")
    }

    @Test("Colours made from many tasks at once share places by pair, and each reads back its own")
    func concurrentCreation() async throws {
        // 64 tasks, each making the same 200 pairs in its own order: each pair
        // must get one place, the same in every task, and read back as itself.
        let pairs = (0..<200).map { index in
            (light: Color.rgb(UInt8(index), 7, 77), dark: Color.rgb(UInt8(index), 77, 7))
        }
        let results = await withTaskGroup(of: [Color?].self) { group in
            for task in 0..<64 {
                group.addTask {
                    let order = task.isMultiple(of: 2) ? Array(pairs.indices) : pairs.indices.reversed()
                    var made = [Color?](repeating: nil, count: pairs.count)
                    for index in order {
                        made[index] = Color.lightDark(light: pairs[index].light, dark: pairs[index].dark)
                    }
                    return made
                }
            }
            return await group.reduce(into: [[Color?]]()) { $0.append($1) }
        }
        let first = try #require(results.first)
        for result in results { #expect(result == first) }
        #expect(Set(first.compactMap { $0 }).count == pairs.count, "two pairs share a place")
        let darkPage = NamedColourPagePalette(background: .rgb(10, 10, 10))
        for (index, colour) in first.enumerated() {
            let colour = try #require(colour)
            #expect(colour.rgbComponents! == (UInt8(index), 7, 77))
            #expect(colour.resolve(with: darkPage) == pairs[index].dark)
        }
    }

    @Test("A full table keeps no new pair, and the pairs it has still find their places")
    func overflow() throws {
        let table = LightDarkColorTable(capacity: 2)
        let pair = { (blue: UInt8) in
            LightDarkColorTable.Pair(light: .init(red: 1, green: 2, blue: blue), dark: .init(red: 3, green: 4, blue: blue))
        }
        let first = try #require(table.index(of: pair(1)))
        let second = try #require(table.index(of: pair(2)))
        #expect(table.index(of: pair(3)) == nil, "past capacity")
        #expect(table.index(of: pair(1)) == first)
        #expect(table.index(of: pair(2)) == second)
        #expect(table.pair(at: second) == pair(2))
        #expect(table.count == 2)
        // Through the colour: a pair a full table cannot keep is nil, which the
        // catalogue and `Color(nsColor:)` answer by choosing the variant now.
        #expect(Color.lightDark(light: .rgb(5, 5, 6), dark: .rgb(6, 5, 5), in: table) == nil)
        #expect(Color.lightDark(light: .rgb(5, 5, 6), dark: .rgb(5, 5, 6), in: table) == .rgb(5, 5, 6))
        #expect(LightDarkColorTable.shared.capacity == 65_536)
    }
}
