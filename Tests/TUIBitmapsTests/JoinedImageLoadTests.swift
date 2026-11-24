//  🖥️ TUI — A Terminal UI framework for Swift
//  JoinedImageLoadTests.swift
//
//  Views that load one picture at once share one load: one download, one
//  decode, one picture in the cache and one in the terminal. Each used to load
//  its own, since none found the picture in the cache before any had landed,
//  and each filed its own decode over the last.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization
import Testing

@testable import TUIApp
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation
@testable import TUIImage
@testable import TUIStyling
@testable import TUITestSupport
@testable import TUIView

/// A load that waits until it is opened, counting how often it runs and
/// whether it was cancelled while it waited.
private final class GatedLoad: Sendable {
    private struct State {
        var runs = 0
        var opened = false
        var sawCancellation = false
        /// Each run waiting, by the order it started in.
        var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = Mutex(State())
    let image = RGBAImage(width: 2, height: 2, pixels: Array(repeating: RGBA(r: 255, g: 0, b: 0), count: 4))

    var runs: Int { state.withLock { $0.runs } }
    var sawCancellation: Bool { state.withLock { $0.sawCancellation } }

    func open() {
        let waiting = state.withLock { state in
            state.opened = true
            defer { state.waiting = [:] }
            return state.waiting.values
        }
        for run in waiting { run.resume() }
    }

    /// Waits to be opened, or for its task to be cancelled, and hands back
    /// ``image`` if it was opened.
    func run() async throws -> RGBAImage {
        let run = state.withLock { state in
            state.runs += 1
            return state.runs
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let goes = state.withLock { state in
                    guard !state.opened, !Task.isCancelled else { return true }
                    state.waiting[run] = continuation
                    return false
                }
                if goes { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.waiting.removeValue(forKey: run) }?.resume()
        }
        if Task.isCancelled {
            state.withLock { $0.sawCancellation = true }
            throw CancellationError()
        }
        return image
    }
}

@MainActor
@Suite("Loads of one picture at once are one load")
struct JoinedImageLoadTests {
    private func load(_ key: String, from gate: GatedLoad, in cache: URLImageCache) -> Task<RGBAImage, any Error> {
        Task { try await cache.joinedLoad(key, maxPixelCount: nil) { try await gate.run() } }
    }

    @Test("Twenty callers asking for one key while it loads share one load and one buffer")
    func twentyCallersOneLoad() async throws {
        let cache = URLImageCache()
        let gate = GatedLoad()
        let callers = (0..<20).map { _ in load("picture", from: gate, in: cache) }
        // Every caller waiting on the one load; or, unjoined, every caller's own
        // load running, which fails below rather than waiting out the timeout.
        await settle(until: { cache.loadersWaiting(on: "picture") == 20 || gate.runs == 20 })
        gate.open()
        var images: [RGBAImage] = []
        for caller in callers { images.append(try await caller.value) }
        #expect(gate.runs == 1, "one load for twenty callers")
        let held = try #require(cache.get("picture"))
        #expect(
            images.allSatisfy { DecodedPixels($0) == DecodedPixels(held) },
            "every caller has the buffer the cache holds")
    }

    @Test("A caller cancelled while it waits stops waiting, and the load goes on for the others")
    func cancelledCallerLeavesTheLoad() async throws {
        let cache = URLImageCache()
        let gate = GatedLoad()
        let leaving = load("picture", from: gate, in: cache)
        let staying = load("picture", from: gate, in: cache)
        await settle(until: { cache.loadersWaiting(on: "picture") == 2 || gate.runs == 2 })
        leaving.cancel()
        await #expect(throws: CancellationError.self) { try await leaving.value }
        #expect(cache.loadersWaiting(on: "picture") == 1, "the other caller still waits")
        gate.open()
        let image = try await staying.value
        #expect(!gate.sawCancellation, "the load was not cancelled under the caller still waiting")
        #expect(gate.runs == 1)
        #expect(DecodedPixels(image) == DecodedPixels(gate.image))
    }

    @Test("The load is cancelled once every caller waiting on it has gone, and the next caller loads again")
    func lastCallerGoneCancelsTheLoad() async throws {
        let cache = URLImageCache()
        let gate = GatedLoad()
        let only = load("picture", from: gate, in: cache)
        await settle(until: { cache.loadersWaiting(on: "picture") == 1 })
        only.cancel()
        await #expect(throws: CancellationError.self) { try await only.value }
        await settle(until: { gate.sawCancellation })
        #expect(gate.sawCancellation, "nobody waits on it, so it stops")
        #expect(cache.get("picture") == nil)

        let next = GatedLoad()
        next.open()
        let image = try await load("picture", from: next, in: cache).value
        #expect(next.runs == 1, "a caller after the cancellation starts a load of its own")
        #expect(DecodedPixels(image) == DecodedPixels(next.image))
    }

    @Test("A load that lands where another has filed the key takes that one's picture")
    func landingAdoptsTheHeldPicture() {
        let cache = URLImageCache()
        let first = RGBAImage(width: 1, height: 1, pixels: [RGBA(r: 1, g: 2, b: 3)])
        let second = RGBAImage(width: 1, height: 1, pixels: [RGBA(r: 1, g: 2, b: 3)])
        cache.set("picture", image: first)
        let decode = cache.entry("picture")?.decode
        let kept = cache.keep("picture", image: second)
        #expect(DecodedPixels(kept) == DecodedPixels(first))
        #expect(cache.entry("picture")?.decode === decode, "the decode views drew stays filed")
    }
}

// The server is a BSD socket (see `LocalHTTPServer`).
#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

@MainActor
@Suite("Views of one URL drawn at once", .drawsInTruecolor)
struct JoinedURLImageViewTests {
    @Test("Twenty AsyncImages of one URL in one frame make one request and send the terminal one picture")
    func twentyAsyncImagesOneRequest() async throws {
        let fixture = try BitmapFixture(width: 8, height: 8, left: (255, 0, 0), right: (255, 0, 0))
        let server = try LocalHTTPServer(body: try Data(contentsOf: URL(fileURLWithPath: fixture.path)), holdUntil: .max)
        defer { server.stop() }
        let address = server.url()
        let cache = URLImageCache()
        let tui = TUIContext()
        let view = VStack(spacing: 0) {
            ForEach(0..<20, id: \.self) { _ in
                AsyncImage(url: URL(string: address)) { $0.resizable().frame(width: 4, height: 2) } placeholder: {
                    Text("waiting")
                }
            }
        }
        func frame() -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            environment.urlImageCache = cache
            environment.imageCellAspect = 2.0
            // The server holds the one download open until every view has
            // joined it, which takes as long as this process's main actor and
            // pool take to run twenty views' tasks: under a full parallel run,
            // longer than the default 30 s request timeout. The download then
            // timed out, every view drew its placeholder, and no frame after
            // could draw a picture (one gate in many). 300 s, as
            // `URLImageHTTPFailureTests.timeout`, stays clear of any suite's
            // length; a passing run never waits for it.
            environment.imageURLTimeout = 300
            environment.imageCellPixels = TerminalCellPixels(width: 8, height: 16)
            let context = RenderContext(availableWidth: 20, availableHeight: 400, environment: environment, tuiContext: tui)
            tui.lifecycle.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let buffer = KittyGraphics.withSupport(true) { renderToBuffer(view, context: context) }
            tui.lifecycle.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            return buffer.lines
        }

        _ = frame()
        // Every view's load asked: twenty callers waiting on one load, or, unjoined,
        // a second request at the server already, which fails below.
        await settle(until: { server.requestCount > 1 || cache.loadersWaiting(on: address) == 20 })
        server.answerHeld()
        await finishStartedTasks(of: tui.lifecycle)
        var lines: [String] = []
        await settle(until: {
            lines = frame()
            return lines.filter { $0.unicodeScalars.contains(.terminalImagePlaceholder) }.count == 40
        })
        #expect(
            lines.filter { $0.unicodeScalars.contains(.terminalImagePlaceholder) }.count == 40,
            "every view draws its picture: \(lines.map(\.stripped))")
        #expect(server.requestCount == 1, "one download for twenty views")
        #expect(tui.terminalImageStore.imageCount == 1, "one picture sent to the terminal")
    }
}
#endif
