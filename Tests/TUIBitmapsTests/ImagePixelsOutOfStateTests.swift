//  🖥️ TUI — A Terminal UI framework for Swift
//  ImagePixelsOutOfStateTests.swift
//
//  A row's state lives as long as its list (as in SwiftUI's lazy containers),
//  so a picture's pixels are not kept in it: the image cache, bounded in
//  bytes, keeps them, the row keeps a handle (`ImageLoadingPhase.cached`), and
//  the view holds them only while it is drawn (`ImagePixelPin`). A long list of
//  pictures then holds the cache's cap of pixels, not every row's ever drawn —
//  with nothing drawn differently.
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
@Suite("A picture's pixels are kept by the image cache, not by its row's state")
struct ImagePixelsOutOfStateTests {
    /// A column of pictures, one line each, windowed as a scroll view windows
    /// a lazy stack.
    private func column(_ paths: [String]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(paths, id: \.self) { path in
                Image(.file(path)).frame(width: 4, height: 1)
            }
        }
    }

    /// One live-loop-shaped frame; returns the drawn lines.
    @discardableResult
    private func frame(
        _ view: some View, _ tui: TUIContext, cache: URLImageCache, offset: Int, syncLimit: Int? = nil
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.urlImageCache = cache
        if let syncLimit { environment.imageSynchronousDecodeLimit = syncLimit }
        environment.scrollContentWindow = ScrollContentWindow(offset: offset, viewportHeight: 4)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 400, environment: environment, tuiContext: tui)
        tui.lifecycle.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.lifecycle.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map(\.stripped)
    }

    /// The bytes of pixels the views' state holds: a phase holding its
    /// pixels, and a pin holding a drawn picture's.
    private func heldPixelBytes(_ storage: StateStorage) -> Int {
        storage.values.values.reduce(0) { total, box in
            if let phase = box as? StateBox<ImageLoadingPhase>, case .success(let image) = phase.value {
                return total + image.width * image.height * 4
            }
            if let pin = box as? StateBox<ImagePixelPin>, let image = pin.value.image {
                return total + image.width * image.height * 4
            }
            return total
        }
    }

    @Test("A thousand pictures scrolled through hold the cache's cap of pixels, not a thousand pictures'")
    func scrolledPicturesStayBounded() throws {
        let fixtures = try (0..<1_000).map { index in
            try BitmapFixture(
                width: 16, height: 16, left: (UInt8(index % 256), 40, 40), right: (40, UInt8(index % 256), 40))
        }
        let picture = 16 * 16 * 4
        let cache = URLImageCache(byteLimit: 32 * picture)
        let tui = TUIContext()
        let view = column(fixtures.map(\.path))
        var most = 0
        for offset in stride(from: 0, to: 1_000, by: 4) {
            frame(view, tui, cache: cache, offset: offset)
            most = max(most, heldPixelBytes(tui.stateStorage))
        }
        #expect(cache.byteCount <= cache.byteLimit)
        // What is on screen, and the rows the window draws past its edges.
        #expect(most <= 16 * picture, "state held \(most) bytes of pixels at most; one picture is \(picture)")
        #expect(heldPixelBytes(tui.stateStorage) <= 16 * picture)
    }

    @Test("A row whose picture the cache let go of draws it again, the same, on the frame it comes back")
    func evictedSmallFileDrawsTheSame() throws {
        let fixtures = try (0..<40).map { index in
            try BitmapFixture(width: 8, height: 8, left: (UInt8(index * 6), 0, 0), right: (0, 0, UInt8(index * 6)))
        }
        let cache = URLImageCache(byteLimit: 8 * 8 * 4 * 6)
        let tui = TUIContext()
        let view = column(fixtures.map(\.path))
        let first = frame(view, tui, cache: cache, offset: 0)
        frame(view, tui, cache: cache, offset: 0)
        // Away long enough for the cache to let the first rows' pictures go.
        for offset in stride(from: 8, to: 40, by: 4) { frame(view, tui, cache: cache, offset: offset) }
        let back = frame(view, tui, cache: cache, offset: 0)
        #expect(back.prefix(4) == first.prefix(4), "drawn again from the file, as it was")
    }

    @Test("Reloading a large picture the cache let go of, a row shows what it last drew, not its placeholder")
    func evictedLargeFileShowsItsLastDrawing() async throws {
        let fixtures = try (0..<20).map { index in
            try BitmapFixture(width: 8, height: 8, left: (UInt8(index * 10), 0, 0), right: (0, UInt8(index * 10), 0))
        }
        let cache = URLImageCache(byteLimit: 8 * 8 * 4 * 6)
        let tui = TUIContext()
        let view = column(fixtures.map(\.path))
        // Every file loads in a task (`imageSynchronousDecodeLimit(0)`).
        var first: [String] = []
        for _ in 0..<200 {
            first = frame(view, tui, cache: cache, offset: 0, syncLimit: 0)
            if !first.prefix(4).contains(where: { $0.contains("Loading") }) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(!first.prefix(4).contains { $0.contains("Loading") }, "sanity: the pictures loaded")
        for offset in stride(from: 8, to: 20, by: 4) {
            for _ in 0..<50 {
                let lines = frame(view, tui, cache: cache, offset: offset, syncLimit: 0)
                if !lines.contains(where: { $0.contains("Loading") }) { break }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        let back = frame(view, tui, cache: cache, offset: 0, syncLimit: 0)
        #expect(back.prefix(4) == first.prefix(4), "the last drawing, while the picture loads again")
    }

    @Test("An AsyncImage's picture is the cache's too: scrolled away, its row holds none of its pixels")
    func asyncImagePixelsAreTheCaches() async throws {
        let cache = URLImageCache()
        let red = RGBA(r: 255, g: 0, b: 0)
        let urls = (0..<12).map { index in
            let address = "tuikit-test://pixels-out-of-state/\(index)-\(UUID().uuidString).png"
            cache.set(address, image: RGBAImage(width: 4, height: 4, pixels: Array(repeating: red, count: 16)))
            return URL(string: address)!
        }
        let tui = TUIContext()
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(urls, id: \.self) { url in
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.frame(width: 4, height: 1) } else { Text("empty") }
                }
            }
        }
        for _ in 0..<200 {
            let lines = frame(view, tui, cache: cache, offset: 0)
            if !lines.prefix(4).contains(where: { $0.contains("empty") }) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(heldPixelBytes(tui.stateStorage) > 0, "sanity: the rows on screen hold what they draw")
        // No await between: the rows now on screen have not had their loads
        // land, so whatever is held is the rows that went.
        frame(view, tui, cache: cache, offset: 8)
        frame(view, tui, cache: cache, offset: 8)
        let held = heldPixelBytes(tui.stateStorage)
        #expect(held == 0, "the rows scrolled away hold no pixels: \(held) bytes held")
    }

    @Test("A picture made from pixels in memory keeps them: there is nothing to read them back from")
    func inMemoryPixelsStayInState() {
        let pixels = RGBAImage(width: 4, height: 4, pixels: Array(repeating: RGBA(r: 9, g: 9, b: 9), count: 16))
        let cache = URLImageCache()
        let tui = TUIContext()
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<1, id: \.self) { _ in
                Image(.file("/in-memory"), decoded: _DecodedImage(pixels)).frame(width: 4, height: 1)
            }
        }
        frame(view, tui, cache: cache, offset: 0)
        #expect(heldPixelBytes(tui.stateStorage) >= 16 * 4)
    }
}
