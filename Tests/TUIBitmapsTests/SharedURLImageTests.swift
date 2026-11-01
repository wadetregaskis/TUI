//  🖥️ TUI — A Terminal UI framework for Swift
//  SharedURLImageTests.swift
//
//  A load publishes a handle on a picture the image cache keeps, and the view
//  reads the pixels when it next draws. Between the two the cache can let them
//  go: a second load of the URL files its own decode over the first, or a load
//  of another URL evicts it. The view then held a handle on nothing and never
//  loaded again, so its placeholder spun for ever. So a load's pixels now stay
//  with the view until it has drawn them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation
@testable import TUIImage
@testable import TUITestSupport
@testable import TUIView

// The server is a BSD socket (see `LocalHTTPServer`).
#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

@MainActor
@Suite("Views whose pictures land together")
struct SharedURLImageTests {
    /// A server of one red picture, 8 × 8, holding its responses until
    /// `requests` have arrived, so that the loads land together.
    private func redPicture(holdUntil requests: Int) throws -> LocalHTTPServer {
        let fixture = try BitmapFixture(width: 8, height: 8, left: (255, 0, 0), right: (255, 0, 0))
        let bytes = try Data(contentsOf: URL(fileURLWithPath: fixture.path))
        return try LocalHTTPServer(body: bytes, holdUntil: requests)
    }

    /// What 8 × 8 pixels cost the image cache.
    private let pictureBytes = 8 * 8 * 4

    private func asyncImage(_ address: String) -> some View {
        AsyncImage(url: URL(string: address)) { $0.frame(width: 4, height: 2) } placeholder: { Text("waiting") }
    }

    private func image(_ address: String) -> some View {
        Image(.url(address)).frame(width: 4, height: 2)
    }

    /// Draws `view` once, which starts its loads, then lets them land with no
    /// frame drawn: the race, made certain. A frame drawn between the two
    /// landings pins the first picture, and hides the bug.
    private func landWithNoFrameDrawn(
        _ view: () -> some View, harness: InputChainHarness, server: LocalHTTPServer, cache: URLImageCache, keys: [String]
    ) async throws {
        harness.frame(view())
        await settle(until: {
            server.requestCount == keys.count && keys.contains { cache.get($0) != nil }
        })
        // The second landing, and both hops to the main actor to publish.
        try await Task.sleep(for: .milliseconds(200))
    }

    /// Draws `view` until both of its pictures show, with nothing left waiting.
    private func expectBothPicturesDrawn(_ view: () -> some View, harness: InputChainHarness) async {
        var lines: [String] = []
        await settle(until: {
            lines = harness.frame(view()).lines
            let red = lines.filter { $0.contains("255;0;0") }.count
            return red >= 4 && lines.allSatisfy { $0.stripped.allSatisfy(\.isWhitespace) }
        })
        #expect(
            lines.filter { $0.contains("255;0;0") }.count >= 4,
            "both pictures draw, 2 rows each: \(lines.map(\.stripped))")
    }

    @Test("Two AsyncImages of one URL both draw when their loads land together")
    func twoAsyncImages() async throws {
        let server = try redPicture(holdUntil: 2)
        defer { server.stop() }
        let address = server.url()
        let cache = URLImageCache()
        let harness = InputChainHarness()
        let view = { VStack { asyncImage(address); asyncImage(address) }.urlImageCache(cache) }
        try await landWithNoFrameDrawn(view, harness: harness, server: server, cache: cache, keys: [address, address])
        await expectBothPicturesDrawn(view, harness: harness)
    }

    @Test("An Image and an AsyncImage of one URL both draw when their loads land together")
    func imageAndAsyncImage() async throws {
        let server = try redPicture(holdUntil: 2)
        defer { server.stop() }
        let address = server.url()
        let cache = URLImageCache()
        let harness = InputChainHarness()
        let view = { VStack { image(address); asyncImage(address) }.urlImageCache(cache) }
        try await landWithNoFrameDrawn(view, harness: harness, server: server, cache: cache, keys: [address, address])
        await expectBothPicturesDrawn(view, harness: harness)
    }

    @Test("Two Images of one URL both draw when their loads land together")
    func twoImages() async throws {
        let server = try redPicture(holdUntil: 2)
        defer { server.stop() }
        let address = server.url()
        let cache = URLImageCache()
        let harness = InputChainHarness()
        let view = { VStack { image(address); image(address) }.urlImageCache(cache) }
        try await landWithNoFrameDrawn(view, harness: harness, server: server, cache: cache, keys: [address, address])
        await expectBothPicturesDrawn(view, harness: harness)
    }

    @Test("A picture the cache evicts before it is first drawn still draws")
    func evictedBeforeFirstDrawn() async throws {
        let server = try redPicture(holdUntil: 2)
        defer { server.stop() }
        let first = server.url("/first")
        let second = server.url("/second")
        // Room for one picture, so the second to land evicts the first.
        let cache = URLImageCache(byteLimit: pictureBytes)
        let harness = InputChainHarness()
        let view = { VStack { asyncImage(first); image(second) }.urlImageCache(cache) }
        try await landWithNoFrameDrawn(view, harness: harness, server: server, cache: cache, keys: [first, second])
        await expectBothPicturesDrawn(view, harness: harness)
    }

    @Test("An AsyncImage whose picture was evicted while it was away draws it again when it comes back")
    func evictedWhileAway() async throws {
        let server = try redPicture(holdUntil: 0)
        defer { server.stop() }
        let addresses = (0..<12).map { server.url("/\($0)") }
        // Six pictures of the twelve, so scrolling away lets the first ones go.
        let cache = URLImageCache(byteLimit: 6 * pictureBytes)
        let tui = TUIContext()
        // Narrower when it comes back, so that what it last drew does not fit, and
        // only the picture itself will do.
        func view(width: Int) -> some View {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(addresses, id: \.self) { address in
                    AsyncImage(url: URL(string: address)) { $0.resizable().frame(width: width, height: 1) } placeholder: {
                        Text("waiting")
                    }
                }
            }
        }
        func frame(offset: Int, width: Int) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            environment.urlImageCache = cache
            environment.scrollContentWindow = ScrollContentWindow(offset: offset, viewportHeight: 4)
            let context = RenderContext(
                availableWidth: 20, availableHeight: 400, environment: environment, tuiContext: tui)
            tui.lifecycle.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let buffer = renderToBuffer(view(width: width), context: context)
            tui.lifecycle.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            return buffer.lines
        }
        for (offset, width) in [(0, 8), (8, 8), (0, 4)] {
            var lines: [String] = []
            await settle(until: {
                lines = frame(offset: offset, width: width)
                let window = lines.dropFirst(offset).prefix(4)
                return window.count == 4 && window.allSatisfy { $0.contains("255;0;0") }
            })
            #expect(
                lines.dropFirst(offset).prefix(4).allSatisfy { $0.contains("255;0;0") },
                "at offset \(offset) the rows draw: \(lines.map(\.stripped))")
        }
    }
}
#endif
