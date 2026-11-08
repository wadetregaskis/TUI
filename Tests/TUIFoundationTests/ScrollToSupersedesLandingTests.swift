//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollToSupersedesLandingTests.swift
//
//  A keyboard glide that lands parks its landing as a seek, flagged as a
//  landing so it is jumped to rather than animated. An app's `scrollTo` made
//  before a frame spends that seek replaced the request but not the flag, so
//  the app's request was then treated as the glide's landing: sought again by
//  position and jumped to, whatever animation the call was made in. A new
//  request is never a landing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("scrollTo supersedes a parked landing")
struct ScrollToSupersedesLandingTests {

    @Test("A scrollTo over a parked landing is the app's request, not a landing")
    func scrollToClearsTheLandingFlag() {
        let handler = ScrollViewHandler(focusID: "scroll")
        handler.pendingScrollTo = ScrollToRequest(key: "row-3", anchor: nil)
        handler.pendingScrollToIsLanding = true

        let registry = ScrollToRegistry()
        registry.register(handler: handler, identity: ViewIdentity(path: "scroll"), renderCache: nil)
        registry.scrollTo(key: "row-9", anchor: .center)

        #expect(handler.pendingScrollTo?.key == "row-9")
        #expect(!handler.pendingScrollToIsLanding, "the app's request inherited the glide's landing flag")
    }
}
