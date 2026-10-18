//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShadowFieldTests.swift
//
//  The arithmetic of a shadow in cells (refusal review O6 (b)): the distance
//  transform it is spread with, the rings and their alphas, the cells a view
//  casts it from, and `ShadowStyle`'s values and layout.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@Suite("Shadow fields")
struct ShadowFieldTests {

    /// The squared distance from each cell to the nearest source, by looking at
    /// every source: what the two-pass transform must agree with.
    private func bruteForce(width: Int, height: Int, sources: Set<[Int]>) -> [Int?] {
        (0..<height).flatMap { row in
            (0..<width).map { column in
                sources.map { ($0[0] - column) * ($0[0] - column) + ($0[1] - row) * ($0[1] - row) }.min()
            }
        }
    }

    @Test("The two-pass distance transform is the nearest source's squared distance, everywhere")
    func distancesMatchBruteForce() {
        var generator = SplitMix(seed: 0x5AD0)
        for _ in 0..<40 {
            let width = Int(generator.next() % 13) + 1
            let height = Int(generator.next() % 9) + 1
            let density = generator.next() % 6
            var sources: Set<[Int]> = []
            for row in 0..<height {
                for column in 0..<width where generator.next() % 20 < density {
                    sources.insert([column, row])
                }
            }
            let fast = ShadowField.squaredDistances(width: width, height: height) { sources.contains([$0, $1]) }
            #expect(fast == bruteForce(width: width, height: height, sources: sources), "\(width)×\(height) \(sources)")
        }
    }

    @Test("Each ring takes an equal step of the peak, down to nothing past the radius")
    func alphaRamp() {
        #expect(ShadowField.alphaRamp(radius: 0, peak: 84) == [84, 0])
        #expect(ShadowField.alphaRamp(radius: 3, peak: 84) == [84, 63, 42, 21, 0])
        #expect(ShadowField.alphaRamp(radius: 1, peak: 255) == [255, 128, 0])
    }

    @Test("A cell's ring is its distance rounded, so a one-cell ring keeps square corners")
    func rings() {
        #expect(ShadowField.ring(of: 0, radius: 2) == 0)
        #expect(ShadowField.ring(of: 1, radius: 2) == 1)
        #expect(ShadowField.ring(of: 2, radius: 1) == 1, "1.4 cells off a corner is the first ring")
        #expect(ShadowField.ring(of: 5, radius: 2) == 2)
        #expect(ShadowField.ring(of: 8, radius: 2) == 3, "2.8 cells is past a radius of 2")
        #expect(ShadowField.ring(of: nil, radius: 2) == 3)
        #expect(ShadowField.ring(of: 400, radius: 2) == 3)
    }

    @Test("A view casts its shadow from the cells it paints: glyphs and stated fields, not bare blanks")
    func footprint() {
        let red = ANSIRenderer.backgroundCode(for: .rgb(255, 0, 0))
        let buffer = FrameBuffer(lines: ["a b", " " + red + " " + ANSIRenderer.reset + " "])
        let footprint = ShadowFootprint(buffer)
        #expect(footprint.width == 3 && footprint.height == 2)
        #expect((0..<3).map { footprint.paints(column: $0, row: 0) } == [true, false, true])
        #expect((0..<3).map { footprint.paints(column: $0, row: 1) } == [false, true, false])
        #expect(footprint.paints(column: -1, row: 0) == false && footprint.paints(column: 0, row: 2) == false)
        #expect(footprint.bounds?.minX == 0 && footprint.bounds?.maxX == 2)
        #expect(ShadowFootprint(FrameBuffer(lines: ["   "])).bounds == nil, "a blank view casts nothing")
    }

    @Test("A drop field is the footprint, moved, and its rings around it")
    func dropField() throws {
        let footprint = ShadowFootprint(FrameBuffer(lines: ["x"]))
        let field = try #require(ShadowField.drop(footprint: footprint, style: .drop(radius: 1, x: 2, y: -1), peak: 100))
        #expect(field.originX == 1 && field.originY == -2 && field.width == 3 && field.height == 3)
        #expect(field.alphas == [50, 50, 50, 50, 100, 50, 50, 50, 50])
        #expect(ShadowField.drop(footprint: footprint, style: .drop(radius: 1), peak: 0) == nil, "a clear colour")
    }

    @Test("An inner field darkens the painted cells nearest the unpainted ones, deepest away from the offset")
    func innerField() throws {
        let footprint = ShadowFootprint(FrameBuffer(lines: ["xxx", "xxx", "xxx"]))
        let soft = try #require(ShadowField.inner(footprint: footprint, style: .inner(radius: 1), peak: 100))
        #expect(soft.alphas == [50, 50, 50, 50, 0, 50, 50, 50, 50])
        let sharp = try #require(ShadowField.inner(footprint: footprint, style: .inner(radius: 0), peak: 100))
        #expect(sharp.isEmpty, "a sharp inner shadow with no offset falls on nothing")
        let offset = try #require(ShadowField.inner(footprint: footprint, style: .inner(radius: 0, x: 1, y: 1), peak: 100))
        #expect(offset.alphas == [100, 100, 100, 100, 0, 0, 100, 0, 0])
    }

    @Test("ShadowStyle's defaults are SwiftUI's: black at a third for a drop, a little over half inside")
    func styleDefaults() {
        #expect(ShadowStyle.drop(radius: 2).color == Color(.sRGBLinear, white: 0, opacity: 0.33))
        #expect(ShadowStyle.drop(radius: 2).color.alpha == 84)
        #expect(ShadowStyle.inner(radius: 2).color.alpha == 140)
        #expect(ShadowStyle.drop(radius: 2) != ShadowStyle.inner(radius: 2))
        let offset = ShadowStyle.drop(radius: 2, x: 1)
        #expect(offset == .drop(radius: 2, x: 1) && offset != .drop(radius: 2, y: 1))
        #expect(ShadowStyle.drop(radius: -3).radius == 0, "a negative radius is no radius")
    }

    @Test("ShadowStyle leaves no byte between its fields undefined")
    func styleLayout() {
        #expect(interiorPadding(of: ShadowStyle.self).isEmpty, "\(interiorPadding(of: ShadowStyle.self))")
        #expect(MemoryLayout<ShadowStyle>.size == 3 * 8 + MemoryLayout<Color>.size + 1)
    }
}

/// A small seeded generator, so the random masks are the same every run.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
