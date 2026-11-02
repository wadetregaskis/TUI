//  🖥️ TUI — A Terminal UI framework for Swift
//  SixelPictureTests.swift
//
//  A picture on a host that speaks Sixel and no Kitty graphics: which hosts, what
//  the encoder writes, and what a frame owes the screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

private struct Signature: ImageStoreSignature {
    var name: String
    var storeBucket: String { name }
}

// MARK: - Which hosts

@Suite("Sixel: which hosts draw by it")
struct SixelHostTests {
    private static let saysFour = "\u{1B}[?64;1;2;4;6;17;18;21;22;52c"

    private func sixel(
        override: Bool? = nil, environment: [String: String] = [:], pictures: Bool? = false,
        attributes: String? = saysFour, tmux: Bool = false
    ) -> Bool {
        TerminalClient.sixelInUse(
            override: override, environment: environment, detectedPictures: pictures, primaryAttributes: attributes,
            isTmux: tmux)
    }

    @Test("Last of the paths: only a host with no Kitty that says 4")
    func order() {
        #expect(sixel())
        #expect(!sixel(pictures: true), "any Kitty placement goes first")
        #expect(!sixel(pictures: nil), "never asked")
        #expect(!sixel(attributes: "\u{1B}[?62;22c"), "does not say 4")
        #expect(!sixel(attributes: nil))
    }

    @Test("tmux says 4 of itself, so only TUI_GRAPHICS=sixel takes it there")
    func tmux() {
        #expect(!sixel(tmux: true))
        #expect(sixel(environment: ["TUI_GRAPHICS": "sixel"], tmux: true))
    }

    @Test("TUI_GRAPHICS=sixel prefers it over Kitty; the others and code say no")
    func forced() {
        #expect(sixel(environment: ["TUI_GRAPHICS": "sixel"], pictures: true, attributes: nil))
        for value in ["0", "1", "classic"] { #expect(!sixel(environment: ["TUI_GRAPHICS": value])) }
        #expect(!sixel(override: false, environment: ["TUI_GRAPHICS": "sixel"]))
        #expect(!sixel(override: true), "a claim about placements")
    }

    @Test("It is pictures, and no classic placement of its own")
    func ladders() {
        #expect(TerminalClient.graphicsSupported(override: nil, environment: ["TUI_GRAPHICS": "sixel"], detected: nil))
        #expect(
            !TerminalClient.classicPlacementsInUse(
                override: nil, environment: ["TUI_GRAPHICS": "sixel"], detectedPlacement: false, detectedClassic: true))
    }

    @Test("Attribute 4 is a whole parameter")
    func attributes() {
        #expect(TerminalClient.deviceAttributesAdvertiseSixel(Self.saysFour))
        #expect(!TerminalClient.deviceAttributesAdvertiseSixel("\u{1B}[?64;14;42c"))
        #expect(!TerminalClient.deviceAttributesAdvertiseSixel("4"))
    }

    @Test("The cell: Windows Terminal's is fixed, then TIOCGWINSZ, then CSI 16 t")
    func cell() {
        let reported = TerminalCellPixels(width: 14, height: 34)
        let asked = TerminalCellPixels(width: 7, height: 17)
        #expect(TerminalClient.sixelCell(reported: reported, asked: asked, isWindowsTerminal: false) == reported)
        #expect(TerminalClient.sixelCell(reported: nil, asked: asked, isWindowsTerminal: false) == asked)
        #expect(
            TerminalClient.sixelCell(reported: reported, asked: asked, isWindowsTerminal: true)
                == TerminalCellPixels(width: 10, height: 20))
    }

    @Test("Its questions' replies, and a host that does not answer one")
    func geometry() {
        let both = SixelGeometryQuery.parse(Array("\u{1B}[?1;0;256S\u{1B}[6;17;7t\u{1B}[0n".utf8))
        #expect(both.registers == 256)
        #expect(both.cell == TerminalCellPixels(width: 7, height: 17))
        let failed = SixelGeometryQuery.parse(Array("\u{1B}[?1;3;0S\u{1B}[0n".utf8))
        #expect(failed.registers == nil)
        #expect(failed.cell == nil)
        #expect(SixelGeometryQuery.parse(Array("\u{1B}[?1;0;4096S".utf8)).registers == 256)
    }
}

// MARK: - The encoder

@Suite("Sixel: the encoder")
struct SixelEncoderTests {
    private func solid(_ red: UInt8, _ green: UInt8, _ blue: UInt8, alpha: UInt8 = 255, count: Int) -> [UInt8] {
        (0..<count).flatMap { _ in [red, green, blue, alpha] }
    }

    private func encoded(_ rgba: [UInt8], width: Int, height: Int, background: SixelEncoder.Background? = nil) -> String {
        var palette = SixelEncoder.Palette(rgba: rgba, background: background)
        return SixelEncoder.encode(rgba: rgba, width: width, height: height, palette: &palette, background: background)
    }

    @Test("One colour: its raster size, one register, a run of whole bands")
    func oneColour() {
        let out = encoded(solid(255, 0, 0, count: 8 * 12), width: 8, height: 12)
        #expect(out.hasPrefix("\u{1B}P0;1;0q\"1;1;8;12#0;2;"))
        #expect(out.hasSuffix("#0!8~-#0!8~-\u{1B}\\"))
    }

    @Test("A height that is no multiple of six leaves the last band's lower bits unset")
    func partialBand() {
        // Two rows of a band: bits 0 and 1, which is 3, which is `B`.
        let out = encoded(solid(0, 255, 0, count: 4 * 2), width: 4, height: 2)
        #expect(out.hasSuffix("#0!4B-\u{1B}\\"))
    }

    @Test("A short run is spelled out, and each colour has its pass")
    func twoColours() {
        var rgba = solid(255, 0, 0, count: 3)
        rgba += solid(0, 0, 255, count: 3)
        let out = encoded(rgba, width: 3, height: 2)
        // A band of two rows: the top row's colour is bit 0, the next one's bit 1.
        #expect(out.hasSuffix("#0AAA$#1@@@-\u{1B}\\") || out.hasSuffix("#0@@@$#1AAA-\u{1B}\\"))
    }

    @Test("At most the colours asked for, whatever the picture")
    func palette() {
        var rgba: [UInt8] = []
        for red in stride(from: 0, to: 256, by: 8) {
            for green in stride(from: 0, to: 256, by: 8) { rgba += [UInt8(red), UInt8(green), 128, 255] }
        }
        #expect(SixelEncoder.Palette(rgba: rgba, background: nil, limit: 16).count == 16)
        #expect(SixelEncoder.Palette(rgba: rgba, background: nil, limit: 4096).count == 256)
        #expect(SixelEncoder.Palette(rgba: solid(1, 2, 3, count: 9), background: nil).count == 1)
    }

    @Test("Translucent pixels: flattened where the background is known, on or off where not")
    func alpha() {
        // Half of white over black is mid grey, about 50%.
        let flat = encoded(solid(255, 255, 255, alpha: 128, count: 6), width: 1, height: 6, background: (0, 0, 0))
        #expect(flat.contains(";2;50;50;50"))
        // Unknown: mostly transparent draws nothing, not a register's worth.
        let unset = encoded(solid(255, 255, 255, alpha: 40, count: 6), width: 1, height: 6)
        #expect(unset.hasSuffix("-\u{1B}\\"))
        #expect(!unset.contains("~"))
        let set = encoded(solid(255, 255, 255, alpha: 200, count: 6), width: 1, height: 6)
        #expect(set.contains("~"))
    }

    @Test("Resampling: the same size is the same pixels; a shrink averages; a grow repeats")
    func resampling() {
        let rgba: [UInt8] = [0, 0, 0, 255, 100, 100, 100, 255]
        #expect(SixelEncoder.resampled(rgba: rgba, width: 2, height: 1, toWidth: 2, toHeight: 1) == rgba)
        #expect(SixelEncoder.resampled(rgba: rgba, width: 2, height: 1, toWidth: 1, toHeight: 1) == [50, 50, 50, 255])
        #expect(
            SixelEncoder.resampled(rgba: rgba, width: 2, height: 1, toWidth: 4, toHeight: 1)
                == [0, 0, 0, 255, 0, 0, 0, 255, 100, 100, 100, 255, 100, 100, 100, 255])
    }

    @Test("Half blocks: one a cell, its upper half in the ink and its lower in the ground")
    func halfBlocks() {
        let rgba: [UInt8] = [10, 20, 30, 255, 40, 50, 60, 255]
        let cells = SixelEncoder.halfBlocks(rgba: rgba, width: 1, height: 2, columns: 1, rows: 1, background: nil)
        #expect(cells == [["\u{1B}[38;2;10;20;30;48;2;40;50;60m\u{2580}"]])
    }

    @Test("Picture cells become a move past them, and nothing else changes")
    func skipping() {
        let cell = String(Character(.terminalImagePlaceholder))
        #expect(KittyGraphics.skippingPictureCells("a" + cell + cell + cell + "b") == "a\u{1B}[3Cb")
        #expect(KittyGraphics.skippingPictureCells("é\u{1B}[1m") == "é\u{1B}[1m")
        #expect(KittyGraphics.skippingPictureCells("\u{1B}[2Kab" + cell) == "ab\u{1B}[1C", "its erase would take the pixels")
        #expect(KittyGraphics.skippingPictureCells("\u{1B}[2Kab") == "\u{1B}[2Kab", "no picture, no change")
    }
}

// MARK: - The frame

@MainActor
@Suite("Sixel: what a frame owes")
struct SixelFrameTests {
    private static let cell = TerminalCellPixels(width: 4, height: 8)

    /// `body` as a Sixel host would run it.
    private func onSixel(_ body: () -> Void) {
        KittyGraphics.withSupport(true) {
            KittyGraphics.withClassicPlacements(true) {
                KittyGraphics.withClassicPlacementsCrop(false) {
                    KittyGraphics.withSixel(true, operation: body)
                }
            }
        }
    }

    private func picture(in store: TerminalImageStore, name: String = "a") -> [String] {
        store.placeholderRows(token: name, signature: Signature(name: name), columns: 10, rows: 6) {
            var bytes = [UInt8]()
            for y in 0..<48 {
                for x in 0..<40 { bytes += [UInt8(x * 6), UInt8(y * 5), 7] }
            }
            return (bytes, .rgb, 40, 48)
        } ?? []
    }

    @MainActor
    private struct Rig {
        let store = TerminalImageStore()
        let layer = SixelPictureLayer()
        let writer = FrameDiffWriter(program: .unidentified)
        var nanos: UInt64 = 1_000_000_000
    }

    /// One frame of `lines`, as `writeFrame` runs it, returning all it wrote.
    private func frame(_ lines: [String], rig: inout Rig, secondsLater: UInt64 = 60) -> (out: String, result: SixelPictureLayer.Result) {
        rig.nanos += secondsLater * 1_000_000_000
        let terminal = MockTerminal()
        let built = rig.writer.buildReusingOutputLines(
            buffer: FrameBuffer(lines: lines), terminalWidth: 40, terminalHeight: 24, bgCode: "", reset: "\u{1B}[0m")
        rig.writer.writeContentDiff(
            newLines: built, terminal: terminal, startRow: 1, terminalWidth: 40, bgCode: "", reset: "\u{1B}[0m")
        rig.layer.cell = Self.cell
        let result = rig.layer.draw(
            rows: rig.writer.imagePlaceholderRows, store: rig.store,
            background: nil, screenRows: 24, nowNanos: rig.nanos, on: terminal, startRow: 1)
        return (terminal.allOutput, result)
    }

    /// `rows` with a covering view over columns 4..<6 of rows 2..<4.
    private func covered(_ rows: [String]) -> [String] {
        rows.enumerated().map { index, row in
            guard (2..<4).contains(index) else { return row }
            let cells = KittyGraphics.extractingPlaceholders(row).runs.first
            let cell = { (column: Int) -> String in
                KittyGraphics.PlaceholderCell(id: cells?.image ?? 0, row: index, column: column).spelled
            }
            return (0..<4).map(cell).joined() + "\u{1B}[39mXX" + (6..<10).map(cell).joined() + "\u{1B}[39m"
        }
    }

    private func sixels(in out: String) -> Int { out.components(separatedBy: "\u{1B}P0;1;0q").count - 1 }

    private func rasters(in out: String) -> [String] {
        out.components(separatedBy: "\"1;1;").dropFirst().map { String($0.prefix { $0 != "#" }) }
    }

    @Test("The store sends no APC at all: not the picture, not a delete")
    func noAPC() {
        onSixel {
            var rig = Rig()
            _ = picture(in: rig.store)
            #expect(rig.store.takePending().isEmpty)
            rig.store.release(token: "a")
            #expect(rig.store.takeDeletes().isEmpty)
            #expect(rig.store.farewell().isEmpty)
            rig.nanos = 0
        }
    }

    @Test("A picture draws once, at its cells' own pixels, and no placeholder reaches the wire")
    func drawsOnce() {
        onSixel {
            var rig = Rig()
            let rows = picture(in: rig.store)
            let first = frame(rows, rig: &rig)
            #expect(sixels(in: first.out) == 1)
            #expect(rasters(in: first.out) == ["40;48"])
            #expect(!first.out.unicodeScalars.contains(.terminalImagePlaceholder))
            #expect(!first.out.contains("\u{1B}_G"))
            #expect(first.result.bytes > 0)
            #expect(first.result.retryNanos == nil)
            let second = frame(rows, rig: &rig)
            #expect(second.out.isEmpty, "an unchanged picture is not sent again")
        }
    }

    @Test("A view opening over a picture costs no Sixel, and closing costs what it uncovers")
    func coverAndUncover() {
        onSixel {
            var rig = Rig()
            let rows = picture(in: rig.store)
            _ = frame(rows, rig: &rig)
            let opened = frame(covered(rows), rig: &rig)
            #expect(sixels(in: opened.out) == 0)
            #expect(opened.out.contains("XX"))
            let closed = frame(rows, rig: &rig)
            #expect(rasters(in: closed.out) == ["8;16"], "two cells across, two rows down")
            #expect(!closed.out.contains("XX"))
            // The writer moves past the cells it leaves to the pixels.
            #expect(closed.out.contains("\u{1B}[10C") || closed.out.contains("\u{1B}[2C"))
        }
    }

    @Test("A row written beside a picture does not touch its cells")
    func besideAPicture() {
        onSixel {
            var rig = Rig()
            let rows = picture(in: rig.store)
            _ = frame(rows.map { $0 + "\u{1B}[39m spin" }, rig: &rig)
            let next = frame(rows.map { $0 + "\u{1B}[39m spun" }, rig: &rig)
            #expect(sixels(in: next.out) == 0)
            #expect(next.out.contains("n"))
        }
    }

    @Test("Past the bound on bytes: a blank cell gets a half block, and a later frame the pixels")
    func budget() {
        onSixel {
            var rig = Rig()
            let rows = picture(in: rig.store)
            let moved = rows.map { "  " + $0 }
            let first = frame(rows, rig: &rig)
            #expect(first.result.bytes > 0)
            let soon = frame(moved, rig: &rig, secondsLater: 0)
            #expect(sixels(in: soon.out) == 0, "still paying for the first")
            #expect(soon.out.contains("\u{2580}"), "the column nothing showed in")
            #expect(soon.result.retryNanos != nil)
            #expect(soon.result.styled)
            // The same frame again writes no glyph it has already written.
            let again = frame(moved, rig: &rig, secondsLater: 0)
            #expect(!again.out.contains("\u{2580}"))
            let later = frame(moved, rig: &rig)
            #expect(sixels(in: later.out) >= 1)
            #expect(later.result.retryNanos == nil)
        }
    }

    @Test("A picture on the last row asks for the cursor beside it, and no other does")
    func lastRow() {
        onSixel {
            var rig = Rig()
            let rows = picture(in: rig.store)
            let top = frame(rows, rig: &rig)
            #expect(!top.out.contains("?8452"))
            let terminal = MockTerminal()
            rig.nanos += 60_000_000_000
            rig.layer.invalidate()
            _ = rig.layer.draw(
                rows: rig.writer.imagePlaceholderRows, store: rig.store, background: nil,
                screenRows: 6, nowNanos: rig.nanos, on: terminal, startRow: 1)
            #expect(terminal.allOutput.contains("\u{1B}[?8452h"))
            #expect(terminal.allOutput.contains("\u{1B}[?8452l"))
        }
    }
}
