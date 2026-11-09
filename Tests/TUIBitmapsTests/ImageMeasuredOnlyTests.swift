//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageMeasuredOnlyTests.swift
//
//  A picture drawn only as a measure (a tab's label is: the chip is the
//  control) never ran the render pass's load. It drew its placeholder for
//  good, and with the image cache off (`TUI_IMAGE_CACHE_SIZE=0`) every measure
//  decoded its file again, every frame.
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
@Suite("A picture drawn only as a measure")
struct ImageMeasuredOnlyTests {
    /// One live-loop-shaped frame of `view`, drawn as a measure or not.
    private func frame(
        _ view: some View, _ tui: TUIContext, cache: URLImageCache, measuring: Bool
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.urlImageCache = cache
        var context = RenderContext(availableWidth: 20, availableHeight: 4, environment: environment, tuiContext: tui)
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

    private func picture(_ path: String) -> some View {
        HStack(spacing: 0) {
            Image(.file(path)).resizable().frame(width: 4, height: 2)
        }
    }

    @Test("It draws its picture, as a view drawn by a render pass does", arguments: [0, 64 << 20])
    func drawsThePicture(byteLimit: Int) throws {
        let fixture = try BitmapFixture(width: 8, height: 8, left: (220, 30, 30), right: (30, 30, 220))
        let drawn = frame(picture(fixture.path), TUIContext(), cache: URLImageCache(byteLimit: byteLimit), measuring: false)
        let tui = TUIContext()
        let cache = URLImageCache(byteLimit: byteLimit)
        for _ in 0..<3 {
            #expect(frame(picture(fixture.path), tui, cache: cache, measuring: true) == drawn)
        }
    }

    /// The decode the view keeps is the same buffer from frame to frame: not
    /// decoded again.
    @Test("With the cache off, it is decoded once, not on every frame")
    func decodedOnceWithTheCacheOff() throws {
        let fixture = try BitmapFixture(width: 8, height: 8, left: (220, 30, 30), right: (30, 30, 220))
        let tui = TUIContext()
        let cache = URLImageCache(byteLimit: 0)
        func kept() -> DecodedPixels? {
            for box in tui.stateStorage.values.values {
                if let measured = box as? StateBox<MeasuredPicture>, case .success(let image)? = measured.value.phase {
                    return DecodedPixels(image)
                }
            }
            return nil
        }
        _ = frame(picture(fixture.path), tui, cache: cache, measuring: true)
        let first = try #require(kept())
        for _ in 0..<3 {
            _ = frame(picture(fixture.path), tui, cache: cache, measuring: true)
            #expect(kept() == first)
        }
    }
}
