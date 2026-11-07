//  🖥️ TUI — A Terminal UI framework for Swift
//  ImagesPageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import Example
import TUI
@testable import TUICore
import TUITesting

@MainActor
@Suite("Images page tests")
struct ImagesPageTests {
    @Test("Bouncing ball animates on Images page with KittyGraphics supported")
    func bouncingBallAnimatesWithKittyGraphics() async throws {
        try await KittyGraphics.withSupport(true) {
            let app = TestApp(width: 100, height: 40) {
                ImagesPage(picture: .animation)
            }

            // The frames decode on a task: the clock is stepped until they
            // have landed and the picture moves, however long that takes.
            let first = app.screen.styledLines.joined(separator: "\n")
            try await app.wait(until: {
                app.advance(by: .milliseconds(100))
                return app.screen.styledLines.joined(separator: "\n") != first
            })
        }
    }

    @Test("Bouncing ball animates on Images page with glyphs (KittyGraphics unsupported)")
    func bouncingBallAnimatesWithGlyphs() async throws {
        try await KittyGraphics.withSupport(false) {
            let app = TestApp(width: 100, height: 40) {
                ImagesPage(picture: .animation)
            }

            // The frames decode on a task: the clock is stepped until they
            // have landed and the picture moves, however long that takes.
            let first = app.screen.description
            try await app.wait(until: {
                app.advance(by: .milliseconds(100))
                return app.screen.description != first
            })
        }
    }
}
