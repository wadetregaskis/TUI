//  🖥️ TUI — A Terminal UI framework for Swift
//  ColorWellSpringLoadingTests.swift
//
//  A `ColorPicker`'s well does not spring-load under any behavior, as
//  SwiftUI's does not (measured, macOS 15.8; owner ruling B82), though it is
//  built on a button, which does under `.enabled`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
import TUIColorPicker
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A colour well does not spring-load")
struct ColorWellSpringLoadingTests {
    /// How many spring-load targets `view` registers, drawn under `.enabled`.
    private func targets(_ view: some View) -> Int {
        let context = makeRenderContext(width: 40, height: 4) { environment, tui in
            environment.applyRuntimeServices(from: tui)
        }
        guard let session = context.environment.dragAndDropSession else {
            Issue.record("no drag session")
            return -1
        }
        _ = renderToBuffer(view.springLoadingBehavior(.enabled), context: context)
        return session.springLoadTargets.count
    }

    @Test("Under .enabled a button registers a target and a colour picker's well none")
    func wellOptsOut() {
        #expect(targets(Button("Go") {}) == 1, "the harness sees a button's target")
        #expect(targets(ColorPicker("Tint", selection: .constant(Color.red))) == 0)
    }
}
