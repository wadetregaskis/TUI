//  🖥️ TUI — A Terminal UI framework for Swift
//  ScaledMetricTests.swift
//
//  `@ScaledMetric` reads its base value, as macOS's does at every Dynamic
//  Type size (measured).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

private struct Gutter: View {
    @ScaledMetric(relativeTo: .caption) var gutter = 3
    var body: some View { Text("gutter \(gutter)") }
}

@MainActor
@Suite("ScaledMetric")
struct ScaledMetricTests {
    @Test("A metric reads its base value, whatever the type size")
    func baseValue() {
        let context = makeRenderContext(width: 20, height: 1)
        var large = context
        large.environment.dynamicTypeSize = .accessibility5
        for context in [context, large] {
            #expect(renderToBuffer(Gutter(), context: context).lines.first?.stripped.hasPrefix("gutter 3") == true)
        }
        #expect(ScaledMetric(wrappedValue: 2.5).wrappedValue == 2.5)
    }
}
