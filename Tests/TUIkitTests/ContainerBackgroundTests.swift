//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerBackgroundTests.swift
//
//  `containerBackground(_:for:)` and `containerBackground(for:alignment:content:)`
//  with `.window`: the background fills the scene's content area, under the
//  content, which stays centred and keeps its regions.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("containerBackground(for: .window)")
struct ContainerBackgroundTests {
    /// One live-loop-shaped frame of a window group, `width` × `height`.
    private func scene<V: View>(_ content: V, width: Int = 10, height: Int = 3) -> FrameBuffer {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = WindowGroup { content }.renderScene(context: context)
        tuiContext.stateStorage.endRenderPass()
        return buffer
    }

    /// The SGR state each cell of `line` is drawn in.
    private func states(_ line: String) -> [SGRState] {
        var state = SGRState()
        var result: [SGRState] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible: result.append(state)
            }
        }
        return result
    }

    @Test("A style fills the whole content area, under the centred content")
    func styleFillsTheArea() {
        let buffer = scene(Text("hi").containerBackground(Color.red, for: .window))
        #expect(buffer.width == 10 && buffer.height == 3)
        #expect(buffer.lines.map(\.stripped) == ["          ", "    hi    ", "          "])
        let plain = scene(Text("hi"))
        let cornerState = states(buffer.lines[0])[0]
        #expect(cornerState != states(plain.lines[0])[0], "the corner carries the background")
        #expect(buffer.lines.allSatisfy { states($0).allSatisfy { $0.backgroundColour == cornerState.backgroundColour } },
                "and every cell carries the same one, the text's included")
    }

    @Test("A view background is placed by its alignment")
    func viewBackgroundAlignment() {
        let buffer = scene(Text("hi").containerBackground(for: .window, alignment: .bottomTrailing) { Text("bg") })
        #expect(buffer.lines.map(\.stripped) == ["          ", "    hi    ", "        bg"])
    }

    @Test("Without one the window is as it was")
    func noBackground() {
        #expect(scene(Text("hi")).lines.map(\.stripped) == ["          ", "    hi    ", "          "])
    }

    @Test("The content's regions move with it into the centre")
    func regionsSurvive() {
        let buffer = scene(Text("hi").onTapGesture {}.containerBackground(Color.red, for: .window))
        #expect(buffer.hitTestRegions.contains { $0.offsetX == 4 && $0.offsetY == 1 && $0.width == 2 })
    }
}
