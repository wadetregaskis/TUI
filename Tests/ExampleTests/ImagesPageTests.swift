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

            var screens: [String] = [app.screen.styledLines.joined(separator: "\n")]
            for _ in 1...10 {
                try await Task.sleep(nanoseconds: 50_000_000)
                app.advance(by: .milliseconds(100))
                let current = app.screen.styledLines.joined(separator: "\n")
                screens.append(current)
            }

            let distinctScreens = Set(screens)
            #expect(distinctScreens.count > 1, "The animation never advanced past its first frame with KittyGraphics!")
        }
    }

    @Test("Bouncing ball animates on Images page with glyphs (KittyGraphics unsupported)")
    func bouncingBallAnimatesWithGlyphs() async throws {
        try await KittyGraphics.withSupport(false) {
            let app = TestApp(width: 100, height: 40) {
                ImagesPage(picture: .animation)
            }

            var screens: [String] = [app.screen.description]
            for _ in 1...10 {
                try await Task.sleep(nanoseconds: 50_000_000)
                app.advance(by: .milliseconds(100))
                let current = app.screen.description
                screens.append(current)
            }

            let distinctScreens = Set(screens)
            #expect(distinctScreens.count > 1, "The animation never advanced past its first frame with Glyphs!")
        }
    }
}
