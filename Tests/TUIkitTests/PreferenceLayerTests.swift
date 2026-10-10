//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PreferenceLayerTests.swift
//
//  `overlayPreferenceValue` and `backgroundPreferenceValue`: a layer built
//  from what the base's subtree published, laid in the base's frame, with the
//  values from both views reaching the parent.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

private struct TitleKey: PreferenceKey {
    static let defaultValue = ""
}

private struct SumKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

@MainActor
@Suite("Preference-value overlays and backgrounds")
struct PreferenceLayerTests {
    /// One live-loop-shaped frame: the first row as drawn, and the sum the
    /// frame collected.
    private func frame<V: View>(_ view: V) -> (line: String, sum: Int) {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 5, environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        return (buffer.lines.first?.stripped ?? "", tuiContext.preferences.current[SumKey.self])
    }

    @Test("The overlay is built from what the subtree published")
    func overlayReadsTheSubtree() {
        let view = Text("..........")
            .preference(key: TitleKey.self, value: "hi")
            .overlayPreferenceValue(TitleKey.self, alignment: .leading) { Text($0) }
        #expect(frame(view).line == "hi........")
        let centred = Text("......").preference(key: TitleKey.self, value: "hi")
            .overlayPreferenceValue(TitleKey.self) { Text($0) }
        #expect(frame(centred).line == "..hi..")
    }

    @Test("The background is built from it too, and drawn behind")
    func backgroundReadsTheSubtree() {
        let view = Text("....")
            .preference(key: TitleKey.self, value: "xyzzy")
            .backgroundPreferenceValue(TitleKey.self, alignment: .leading) { Text($0) }
        #expect(frame(view).line == "....", "the base's glyphs are in front, the layer cut to its box")
    }

    @Test("The values from both views reach the parent")
    func bothViewsPublish() {
        let view = Text("ab")
            .preference(key: SumKey.self, value: 1)
            .overlayPreferenceValue(SumKey.self) { value in
                Text("\(value)").preference(key: SumKey.self, value: 2)
            }
        let drawn = frame(view)
        #expect(drawn.sum == 3)
        #expect(drawn.line == "1b", "the overlay saw only the base's value")
    }

    @Test("The result is the base's size")
    func baseSize() {
        let view = Text("ab")
            .preference(key: TitleKey.self, value: "a much longer title")
            .overlayPreferenceValue(TitleKey.self) { Text($0) }
        #expect(frame(view).line.count == 2)
        let measured = measureChild(view, proposal: ProposedSize(width: 20, height: 5), context: makeRenderContext())
        #expect(measured.width == 2 && measured.height == 1)
    }
}
