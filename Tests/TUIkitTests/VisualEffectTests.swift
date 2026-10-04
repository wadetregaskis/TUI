//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VisualEffectTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
private final class Frames {
    var context = makeRenderContext(width: 12, height: 3)

    init(_ animation: Animation? = nil) {
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: animation)
    }

    func draw<V: View>(_ view: V, atMillis millis: Int = 0) -> FrameBuffer {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context)
    }
}

/// What a terminal would show for `buffer`: its lines with its layers
/// composited, and the opacity regions it still has to resolve.
@MainActor
private func picture(_ buffer: FrameBuffer) -> [String] {
    var flattened = buffer
    for layer in buffer.overlays {
        flattened = flattened.composited(with: layer.content, at: (layer.offsetX, layer.offsetY))
    }
    return flattened.lines.map(\.stripped)
}

@MainActor
@Suite("Visual effects")
struct VisualEffectTests {

    private var tinted: some View { Text("abc").foregroundStyle(.red).background(.blue) }

    @Test("The empty effect draws the view as it is")
    func emptyEffect() {
        let plain = Frames().draw(tinted)
        let effected = Frames().draw(tinted.visualEffect { content, _ in content })
        #expect(effected.lines == plain.lines)
    }

    @Test("Each effect draws what the View modifier of the same name draws")
    func effectsMatchTheirModifiers() {
        let pairs: [(FrameBuffer, FrameBuffer)] = [
            (Frames().draw(tinted.offset(x: 2, y: 1)),
             Frames().draw(tinted.visualEffect { content, _ in content.offset(x: 2, y: 1) })),
            (Frames().draw(tinted.offset(CellSize(width: 1, height: 0))),
             Frames().draw(tinted.visualEffect { content, _ in content.offset(CellSize(width: 1, height: 0)) })),
            (Frames().draw(tinted.opacity(0.4)),
             Frames().draw(tinted.visualEffect { content, _ in content.opacity(0.4) })),
            (Frames().draw(tinted.brightness(0.3)),
             Frames().draw(tinted.visualEffect { content, _ in content.brightness(0.3) })),
            (Frames().draw(tinted.contrast(0.5)),
             Frames().draw(tinted.visualEffect { content, _ in content.contrast(0.5) })),
            (Frames().draw(tinted.saturation(0.2)),
             Frames().draw(tinted.visualEffect { content, _ in content.saturation(0.2) })),
            (Frames().draw(tinted.grayscale(1)),
             Frames().draw(tinted.visualEffect { content, _ in content.grayscale(1) })),
            (Frames().draw(tinted.hueRotation(.degrees(90))),
             Frames().draw(tinted.visualEffect { content, _ in content.hueRotation(.degrees(90)) })),
        ]
        for (modifier, effect) in pairs {
            #expect(effect.lines == modifier.lines)
            #expect(effect.opacityRegions == modifier.opacityRegions)
            #expect(picture(effect) == picture(modifier))
        }
    }

    @Test("Effects chain, the later one applied over the earlier")
    func effectsChain() {
        let chained = Frames().draw(
            tinted.visualEffect { content, _ in content.grayscale(1).offset(x: 2) })
        let modifiers = Frames().draw(tinted.grayscale(1).offset(x: 2))
        #expect(picture(chained) == picture(modifiers))
        #expect(chained.overlays.first?.content.lines == modifiers.overlays.first?.content.lines)
    }

    @Test("The proxy is the view's own size, and the effect does not change it")
    func geometryAndLayout() {
        let shifted = Frames().draw(
            Text("abc").visualEffect { content, proxy in content.offset(x: proxy.size.width) })
        #expect(shifted.width == 3, "the view keeps its place and size")
        #expect(shifted.overlays.first?.offsetX == 3)
        let context = makeRenderContext(width: 12, height: 3)
        let size = measureChild(
            Text("abc").visualEffect { content, _ in content.offset(x: 5).opacity(0.5) },
            proposal: ProposedSize(width: 12, height: 3), context: context)
        #expect(size.width == 3 && size.height == 1)
    }

    @Test("An effect animates between its values under an animated change")
    func effectAnimates() {
        let frames = Frames(.linear(duration: 1))
        func view(_ opacity: Double) -> some View {
            tinted.visualEffect { content, _ in content.opacity(opacity) }
        }
        _ = frames.draw(view(1), atMillis: 0)
        _ = frames.draw(view(0), atMillis: 0)
        let halfway = frames.draw(view(0), atMillis: 500)
        let still = Frames().draw(view(0.5))
        #expect(halfway.opacityRegions == still.opacityRegions)
        #expect(halfway.opacityRegions != Frames().draw(view(0)).opacityRegions)
    }
}
