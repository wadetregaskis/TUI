//  🖥️ TUI — A Terminal UI framework for Swift
//  SharedAnimationTests.swift
//
//  Views playing one animated file share its frames: one decode, one set of
//  frames in memory. Each view decoded the file for itself and held its own
//  frames, up to 64 MiB of them (hunt H-96, IMAGE-10).
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
import TUIView

private struct PageApp<Page: View>: App {
    let page: @MainActor () -> Page
    /// `App`'s requirement; these apps are built with ``init(_:)``.
    init() { self.page = { fatalError("built with init(_:)") } }
    init(@ViewBuilder _ page: @escaping @MainActor () -> Page) { self.page = page }
    var body: some Scene { WindowGroup { page() } }
}

@MainActor
@Suite("Views of one animated file share its frames")
struct SharedAnimationTests {
    /// Three frames, black, white and black, looping.
    private func spinner() throws -> String {
        try GIFFixture(
            frames: [.init(grey: 0, delay: 10), .init(grey: 127, delay: 20), .init(grey: 0, delay: 10)], repeats: 0
        ).write()
    }

    @Test("Three views of one animated file decode it once")
    func threeViewsOneDecode() async throws {
        let path = try spinner()
        let cache = URLImageCache()
        let app = HeadlessApp(
            PageApp {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in Image(.file(path)).frame(width: 8, height: 2) }
                }
                .urlImageCache(cache)
            }, width: 20, height: 10)
        await settle(until: {
            app.frame(atNanos: 0)
            return app.nextWake(after: 0) != nil
        })
        // Every view's decode, which waits on the first or takes what it landed.
        for _ in 0..<6 {
            app.frame(atNanos: 0)
            await finishStartedTasks(of: app.lifecycle)
        }
        #expect(app.nextWake(after: 0) != nil, "they play")
        #expect(cache.animations.decodeCount == 1, "one decode for three views")
    }

    @Test("Callers asking for one file's frames get one set, until none holds them")
    func framesSharedWhileHeld() async throws {
        let path = try spinner()
        let animations = SharedAnimations()
        // In a function of its own, so that every hold on the frames has gone
        // when it returns.
        func share() async throws {
            async let first = animations.animation(atPath: path, maxPixelCount: nil)
            async let second = animations.animation(atPath: path, maxPixelCount: nil)
            let (one, other) = try await (first, second)
            let shared = try #require(one)
            #expect(other === shared, "both callers have the one decode's frames")
            let later = try await animations.animation(atPath: path, maxPixelCount: nil)
            #expect(later === shared, "a caller after it landed takes the frames still held")
            #expect(shared.animation.frames.count == 3)
        }
        try await share()
        #expect(animations.decodeCount == 1)

        // Nobody holds them, and the table does not either: they are decoded again.
        let again = try await animations.animation(atPath: path, maxPixelCount: nil)
        #expect(again != nil)
        #expect(animations.decodeCount == 2, "frames nobody holds are not kept")
    }
}
