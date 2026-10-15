//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorDepthPinIsolationTests.swift
//
//  Cut from ColorDepthTestSupport.swift, which holds the helper it tests.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkitStyling
@testable import TUIkitTestSupport

@Suite("ColorDepth pin task isolation")
struct ColorDepthPinIsolationTests {

    @Test("A pinned depth is visible inside the pin and invisible to other tasks")
    func pinIsTaskScoped() async {
        let ambient = ColorDepth.current
        // Pin a depth guaranteed to differ from the ambient one.
        let pinned: ColorDepth = ambient == .noColor ? .truecolor : .noColor

        await ColorDepth.withCurrent(pinned) {
            #expect(ColorDepth.current == pinned, "the pin is visible on the pinning task")

            // A detached task inherits no task-locals: it must see the
            // ambient process value, NOT the pin. (This is the parallel-test
            // bleed that once made an unrelated Picker render colourless
            // while an ImageTests case held a .noColor pin.)
            let elsewhere = await Task.detached { ColorDepth.current }.value
            #expect(elsewhere == ambient, "other tasks see the ambient depth, got \(elsewhere)")
        }

        #expect(ColorDepth.current == ambient, "the pin ends with its scope")
    }
}
