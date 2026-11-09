//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageDrawnSizeDecodeTests.swift
//
//  A file's picture is kept at the size it is drawn, not the size it is: the
//  Example's Tab Views page held five mascots at full size (2.1 MB each) to
//  draw them four cells wide. Decoded at a power-of-two fraction of its size
//  for its box, decoded again when the box needs another, and cached under a
//  key that says which (owner, 2026-11-09, PICTURES (b)).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation
@testable import TUIImage
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("A file's picture is kept at the size it is drawn")
struct ImageDrawnSizeDecodeTests {
    /// One live-loop-shaped frame of `view` in a `width` × `height` space.
    @discardableResult
    private func frame(
        _ view: some View, _ tui: TUIContext, cache: URLImageCache, width: Int, height: Int,
        measuring: Bool = false
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.urlImageCache = cache
        environment.imageCellAspect = 2.0
        var context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        context.isMeasuring = measuring
        tui.lifecycle.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.lifecycle.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map(\.stripped)
    }

    /// The picture `cache` holds of the file at `path` reduced by `reduction`.
    private func held(_ cache: URLImageCache, _ path: String, reducedBy reduction: Int) -> RGBAImage? {
        PlatformImageLoader.cacheKey(forFile: path, reducedBy: reduction).flatMap(cache.get)
    }

    /// A square picture, 256 pixels a side: 192 KB as a BMP, within the
    /// 256 KB a frame decodes itself, so every load here is on the frame.
    private func squareFixture() throws -> BitmapFixture {
        try BitmapFixture(width: 256, height: 256, left: (220, 30, 30), right: (30, 30, 220))
    }

    // MARK: - The loader

    @Test("A reduction is the largest power of two that leaves the pixels a box needs")
    func reductionCoversTheNeed() {
        #expect(PlatformImageLoader.reduction(of: (256, 256), covering: (4, 4)) == 64)
        #expect(PlatformImageLoader.reduction(of: (256, 256), covering: (5, 4)) == 32, "51 × 51 is not 64's 4 × 4")
        #expect(PlatformImageLoader.reduction(of: (256, 256), covering: (40, 40)) == 4)
        #expect(PlatformImageLoader.reduction(of: (256, 256), covering: (256, 1)) == 1, "never fewer than drawn")
        #expect(PlatformImageLoader.reduction(of: (256, 256), covering: (999, 999)) == 1, "never upscaled")
        #expect(PlatformImageLoader.reduction(of: (300, 100), covering: (20, 6)) == 8, "the tighter axis decides")
    }

    @Test("The header says the size the decode has, with nothing decoded")
    func headerSizeIsTheDecodedSize() throws {
        let fixture = try BitmapFixture(width: 30, height: 12)
        let loader = PlatformImageLoader()
        let size = try loader.pictureSize(atPath: fixture.path, maxPixelCount: nil)
        let image = try loader.loadImage(from: fixture.path)
        #expect(size.width == image.width && size.height == image.height)
        #expect(throws: ImageLoadError.self) { try loader.pictureSize(atPath: fixture.path, maxPixelCount: 100) }
    }

    @Test("A reduced decode is the picture at that fraction, and says the size it has whole")
    func reducedDecode() throws {
        let fixture = try BitmapFixture(width: 64, height: 32)
        let decoded = try PlatformImageLoader().loadImage(from: fixture.path, maxPixelCount: nil, reducedBy: 4)
        #expect(decoded.width == 64 && decoded.height == 32)
        #expect(decoded.image.width == 16 && decoded.image.height == 8)
        // The limit is the picture's own size, not the reduced copy's.
        #expect(throws: ImageLoadError.self) {
            try PlatformImageLoader().loadImage(from: fixture.path, maxPixelCount: 64 * 32 - 1, reducedBy: 4)
        }
    }

    @Test("Each reduction is cached under its own key")
    func cacheKeyIncludesTheReduction() throws {
        let fixture = try squareFixture()
        let whole = try #require(PlatformImageLoader.cacheKey(forFile: fixture.path))
        #expect(PlatformImageLoader.cacheKey(forFile: fixture.path, reducedBy: 1) == whole)
        let quarter = try #require(PlatformImageLoader.cacheKey(forFile: fixture.path, reducedBy: 4))
        let eighth = try #require(PlatformImageLoader.cacheKey(forFile: fixture.path, reducedBy: 8))
        #expect(Set([whole, quarter, eighth]).count == 3)
    }

    // MARK: - The view

    @Test("A picture drawn small keeps a copy its box's size, not the picture's")
    func drawnSmallKeepsLittle() throws {
        let fixture = try squareFixture()
        let cache = URLImageCache()
        let lines = frame(
            Image(.file(fixture.path)).resizable().frame(width: 4, height: 2), TUIContext(), cache: cache,
            width: 20, height: 4)
        #expect(lines.first?.contains("Loading") == false, "drawn on its first frame")
        // Four cells of half blocks read 4 × 4 pixels; a 64th of 256 is 4.
        let kept = try #require(held(cache, fixture.path, reducedBy: 64))
        #expect(kept.width == 4 && kept.height == 4)
        #expect(held(cache, fixture.path, reducedBy: 1) == nil, "the picture whole is never decoded")
        #expect(cache.byteCount == 4 * 4 * 4, "\(cache.byteCount) bytes, where whole it is \(256 * 256 * 4)")
    }

    @Test("With no cache to keep it, the view holds the small copy itself")
    func noCacheHoldsTheSmallCopy() throws {
        let fixture = try squareFixture()
        let tui = TUIContext()
        frame(
            Image(.file(fixture.path)).resizable().frame(width: 4, height: 2), tui,
            cache: URLImageCache(byteLimit: 0), width: 20, height: 4)
        let held = tui.stateStorage.values.values.compactMap { box -> ReducedPicture? in
            guard let phase = box as? StateBox<ImageLoadingPhase>, case .reduced(let picture) = phase.value else {
                return nil
            }
            return picture
        }
        let picture = try #require(held.first)
        #expect(picture.image.width == 4 && picture.image.height == 4)
        #expect(picture.width == 256 && picture.height == 256, "laid out as the picture, whole")
    }

    @Test("Drawn larger, it is decoded again for the larger box, and both sizes stay cached")
    func largerBoxDecodesAgain() throws {
        let fixture = try squareFixture()
        let cache = URLImageCache()
        let tui = TUIContext()
        struct Resized: View {
            let path: String
            let side: Int
            var body: some View {
                Image(.file(path)).resizable().frame(width: side, height: side / 2)
            }
        }
        frame(Resized(path: fixture.path, side: 4), tui, cache: cache, width: 80, height: 40)
        #expect(held(cache, fixture.path, reducedBy: 64) != nil)
        // 40 cells of half blocks read 40 × 40 pixels: a quarter, 64 × 64.
        let large = frame(Resized(path: fixture.path, side: 40), tui, cache: cache, width: 80, height: 40)
        let kept = try #require(held(cache, fixture.path, reducedBy: 4), "decoded again, on the frame that grew")
        #expect(kept.width == 64 && kept.height == 64)
        #expect(held(cache, fixture.path, reducedBy: 64) != nil, "the small copy is the cache's to let go")
        // And drawn from it: the same as a view that only ever drew it large.
        let fresh = frame(
            Resized(path: fixture.path, side: 40), TUIContext(), cache: URLImageCache(), width: 80, height: 40)
        #expect(large == fresh)
    }

    @Test("A measure reads the picture's size, and decodes nothing")
    func measureDecodesNothing() throws {
        let fixture = try BitmapFixture(width: 200, height: 50)
        let tui = TUIContext()
        let cache = URLImageCache()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.urlImageCache = cache
        environment.imageCellAspect = 2.0
        let context = RenderContext(availableWidth: 40, availableHeight: 40, environment: environment, tuiContext: tui)
        let view = Image(.file(fixture.path)).resizable().scaledToFit()
        let size = measureChild(view, proposal: ProposedSize(width: 40, height: 40), context: context)
        // 200 × 50 at a 2:1 cell, 40 wide: 40 × 5, as the picture whole is.
        #expect(size.width == 40 && size.height == 5)
        #expect(cache.byteCount == 0, "the render decodes it, for the box this measure answered")
    }

    @Test("A picture drawn only as a measure is decoded for its box too")
    func measuredOnlyIsSmall() throws {
        let fixture = try squareFixture()
        let cache = URLImageCache()
        let tui = TUIContext()
        let view = HStack(spacing: 0) { Image(.file(fixture.path)).resizable().frame(width: 4, height: 2) }
        let lines = frame(view, tui, cache: cache, width: 20, height: 4, measuring: true)
        #expect(lines.first?.contains("Loading") == false)
        #expect(held(cache, fixture.path, reducedBy: 64) != nil)
        #expect(cache.byteCount == 4 * 4 * 4)
    }
}
