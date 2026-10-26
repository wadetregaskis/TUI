//  🖥️ TUI — A Terminal UI framework for Swift
//  PreferenceTransformTests.swift
//
//  `transformPreference(_:_:)`, against what SwiftUI measures: the transform
//  runs on the subtree's reduced value — the default when nothing below set
//  one — and its result is what the ancestors receive.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// A summing key whose default is not the sum's identity.
private struct OffsetSumKey: PreferenceKey {
    static let defaultValue: Int = 100
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

@MainActor
@Suite("transformPreference")
struct PreferenceTransformTests {
    /// One live-loop-shaped frame; returns the frame's collected preferences.
    private func collected<V: View>(_ view: V) -> Int {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10, environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        return tuiContext.preferences.current[OffsetSumKey.self]
    }

    @Test("With nothing below setting the key, the default is transformed and set")
    func transformsTheDefault() {
        #expect(collected(Text("a").transformPreference(OffsetSumKey.self) { $0 += 5 }) == 105)
    }

    @Test("A child's value is transformed")
    func transformsAChild() {
        let view = Text("a").preference(key: OffsetSumKey.self, value: 1)
            .transformPreference(OffsetSumKey.self) { $0 *= 10 }
        #expect(collected(view) == 10)
    }

    @Test("Children are reduced first, then transformed")
    func reducesThenTransforms() {
        let view = VStack {
            Text("a").preference(key: OffsetSumKey.self, value: 1)
            Text("b").preference(key: OffsetSumKey.self, value: 2)
        }.transformPreference(OffsetSumKey.self) { $0 *= 10 }
        #expect(collected(view) == 30)
    }

    @Test("A sibling outside the transform is untouched")
    func siblingsOutsideAreUntouched() {
        let view = VStack {
            Text("a").preference(key: OffsetSumKey.self, value: 1)
                .transformPreference(OffsetSumKey.self) { $0 *= 10 }
            Text("b").preference(key: OffsetSumKey.self, value: 2)
        }
        #expect(collected(view) == 12)
    }
}
