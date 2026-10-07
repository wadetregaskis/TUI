//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageResizingTests.swift
//
//  `Image.resizable(capInsets:resizingMode:)`: a resizable image fills its
//  frame unless a content mode keeps its aspect, and its caps keep their
//  scale while the middle stretches or tiles.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitImage

@testable import TUIkit

@MainActor
@Suite("Resizable images")
struct ImageResizingTests {

    private static let red = RGBA(r: 255, g: 0, b: 0)
    private static let blue = RGBA(r: 0, g: 0, b: 255)

    /// A solid square, already decoded.
    private func square(_ side: Int = 8) -> Image {
        Image(
            .url("tuikit-test://square-\(side)"),
            decoded: _DecodedImage(
                RGBAImage(width: side, height: side, pixels: Array(repeating: Self.red, count: side * side))))
    }

    /// The box `view` draws in, offered `width` × `height` at a cell aspect of 2.
    private func box(_ view: some View, width: Int, height: Int) -> (width: Int, height: Int) {
        let tui = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false), keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(), stateStorage: StateStorage())
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let buffer = renderToBuffer(view, context: context)
        return (buffer.width, buffer.height)
    }

    @Test("An image fits its frame; a resizable one fills it; a content mode keeps the aspect")
    func resizableStretches() {
        #expect(box(square(), width: 20, height: 4) == (8, 4))
        #expect(box(square().resizable(), width: 20, height: 4) == (20, 4))
        #expect(box(square().resizable().scaledToFit(), width: 20, height: 4) == (8, 4))
    }

    @Test("On an axis with no frame to fill, a resizable image takes the extent its aspect gives it")
    func openAxisFollowsTheAspect() {
        let budget = naturalExtentStartingBudget(forVisible: 0)
        #expect(box(square().resizable(), width: 20, height: budget) == (20, 10))
        #expect(box(square().resizable(), width: budget, height: 5) == (10, 5))
    }

    @Test("Resizable images that differ are unequal")
    func equality() {
        #expect(square() != square().resizable())
        #expect(square().resizable() == square().resizable(resizingMode: .stretch))
        #expect(square().resizable() != square().resizable(resizingMode: .tile))
        #expect(square().resizable() != square().resizable(capInsets: EdgeInsets(all: 2)))
    }

    /// A 12-pixel square: a 4-pixel red frame around a blue middle.
    private func framed() -> RGBAImage {
        let pixels = (0..<144).map { index -> RGBA in
            let (x, y) = (index % 12, index / 12)
            return (4..<8).contains(x) && (4..<8).contains(y) ? Self.blue : Self.red
        }
        return RGBAImage(width: 12, height: 12, pixels: pixels)
    }

    @Test("Caps keep the scale the whole image fits at; the middle stretches between them")
    func capsKeepTheirScale() {
        // 24 × 3 cells fits the whole square at 6 × 3: two pixels a column,
        // four a row. So a 4-pixel cap is two columns across and one row down.
        let insets = EdgeInsets(all: 4)
        let sliced = framed().sliced(
            _ImageResizing(capInsets: insets, mode: .stretch), columns: 24, rows: 3, cellAspect: 2)
        // Two samples a column, four a row.
        #expect(sliced.width == 48 && sliced.height == 12)
        let middleRow = Array(sliced.pixels[(6 * 48)..<(7 * 48)])
        #expect(middleRow.prefix(4).allSatisfy { $0 == Self.red })
        #expect(middleRow.dropFirst(4).prefix(40).allSatisfy { $0 == Self.blue })
        #expect(middleRow.suffix(4).allSatisfy { $0 == Self.red })
        #expect(sliced.pixels.prefix(4 * 48).allSatisfy { $0 == Self.red }, "the top cap is one row")

        // Stretched whole, the frame would be a third of the width each side.
        let stretched = framed().sliced(
            _ImageResizing(capInsets: EdgeInsets(), mode: .stretch), columns: 24, rows: 3, cellAspect: 2)
        let wholeRow = Array(stretched.pixels[(6 * 48)..<(7 * 48)])
        #expect(wholeRow.prefix(16).allSatisfy { $0 == Self.red } && wholeRow[16] == Self.blue)
    }

    @Test("A tiled middle repeats at the scale the whole image fits at")
    func tilingRepeats() {
        // 12 pixels fitted to 6 cells, drawn into 12: two samples a cell, so
        // the image repeats once across.
        let map = RGBAImage.sliceMap(source: 12, leading: 0, trailing: 0, cells: 12, fittedCells: 6, tiles: true)
        #expect(map == Array(0..<12) + Array(0..<12))
        let stretched = RGBAImage.sliceMap(
            source: 12, leading: 0, trailing: 0, cells: 12, fittedCells: 6, tiles: false)
        #expect(stretched == (0..<24).map { $0 / 2 })
    }

    @Test("Caps wider than the frame share it in proportion")
    func capsShareASmallFrame() {
        let map = RGBAImage.sliceMap(source: 12, leading: 6, trailing: 6, cells: 2, fittedCells: 6, tiles: false)
        // Three cells of cap each side, in two cells: one each, no middle.
        #expect(map.count == 4)
        #expect(map.prefix(2).allSatisfy { $0 < 6 } && map.suffix(2).allSatisfy { $0 >= 6 })
    }

    @Test("A drawn image in slices differs from the same image stretched whole")
    func slicesDraw() {
        let image = Image(.url("tuikit-test://framed"), decoded: _DecodedImage(framed()))
        let harness = InputChainHarness(width: 24, height: 3)
        let whole = harness.frame(image.resizable().imageColorMode(.trueColor).frame(width: 24, height: 3)).lines
        let capped = InputChainHarness(width: 24, height: 3).frame(
            image.resizable(capInsets: EdgeInsets(all: 4)).imageColorMode(.trueColor)
                .frame(width: 24, height: 3)).lines
        #expect(whole != capped)
    }
}
