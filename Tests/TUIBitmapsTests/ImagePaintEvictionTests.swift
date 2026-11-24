//  🖥️ TUI — A Terminal UI framework for Swift
//  ImagePaintEvictionTests.swift
//
//  An `ImagePaint` of a picture the image cache keeps goes on drawing it
//  after the cache lets it go. It read its pixels back from the cache before
//  looking at what it had converted them to, so from the frame after an
//  eviction it drew nothing, for as long as it stayed on screen (hunt H-96,
//  IMAGE-6).
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
@Suite("An image paint after the cache lets its picture go", .drawsInTruecolor)
struct ImagePaintEvictionTests {
    /// What 8 × 8 pixels cost the image cache: the cache below holds one.
    private let pictureBytes = 8 * 8 * 4

    /// Another picture of 8 × 8, filed to evict the paint's.
    private let other = RGBAImage(width: 8, height: 8, pixels: Array(repeating: RGBA(r: 0, g: 0, b: 255), count: 64))

    /// Draws a field painted with the red picture at `path` through `cache`,
    /// the file decoded on the frame when `synchronously`, otherwise in a task.
    private func painter(_ path: String, cache: URLImageCache, synchronously: Bool) -> (tui: TUIContext, frame: () -> Bool) {
        let tui = TUIContext()
        let view = Rectangle().fill(.image(Image(.file(path))))
        func frame() -> Bool {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tui)
            environment.imageCellAspect = 2.0
            environment.urlImageCache = cache
            environment.imageSynchronousDecodeLimit = synchronously ? 1 << 20 : 0
            let context = RenderContext(availableWidth: 4, availableHeight: 2, environment: environment, tuiContext: tui)
            tui.lifecycle.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            tui.lifecycle.endRenderPass()
            tui.stateStorage.endRenderPass()
            return buffer.lines.contains { $0.contains("255;0;0") }
        }
        return (tui, frame)
    }

    /// A red picture of 8 × 8. Kept by the test to its end: the fixture
    /// deletes its file when it goes, which is at its last use.
    private func redFile() throws -> BitmapFixture {
        try BitmapFixture(width: 8, height: 8, left: (255, 0, 0), right: (255, 0, 0))
    }

    @Test("A paint that has drawn its picture goes on drawing it once the cache evicts it")
    func drawnPaintSurvivesEviction() throws {
        let fixture = try redFile()
        defer { withExtendedLifetime(fixture) {} }
        let cache = URLImageCache(byteLimit: pictureBytes)
        let (_, frame) = painter(fixture.path, cache: cache, synchronously: true)
        #expect(frame(), "the paint draws its picture")
        cache.set("other", image: other)
        #expect(cache.get("other") != nil && cache.byteCount == pictureBytes, "the paint's picture was evicted")
        #expect(frame(), "and still draws it")
        #expect(frame())
    }

    @Test("A paint whose picture was evicted before it drew it loads it again and draws it")
    func evictedBeforeDrawnReloads() async throws {
        let fixture = try redFile()
        defer { withExtendedLifetime(fixture) {} }
        let cache = URLImageCache(byteLimit: pictureBytes)
        let (tui, frame) = painter(fixture.path, cache: cache, synchronously: false)
        #expect(!frame(), "loading in a task")
        await finishStartedTasks(of: tui.lifecycle)
        // Landed, and let go of before any frame drew it.
        cache.set("other", image: other)
        var drawn = false
        for _ in 0..<3 where !drawn {
            drawn = frame()
            await finishStartedTasks(of: tui.lifecycle)
        }
        #expect(drawn, "the paint loads its picture again and draws it")
    }
}
