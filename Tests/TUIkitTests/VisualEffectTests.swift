//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VisualEffectTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

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

    @Test("SwiftUI's own example: an offset following the view's global position is drawn, in the frame that draws it")
    func globalPositionDrivesTheEffect() {
        let harness = InputChainHarness()
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("a")
            Text("b")
            Text("c")
            Text("row").visualEffect { content, proxy in
                content.offset(x: proxy.frame(in: .global).origin.y)
            }
        }
        // Three rows down: drawn three cells right, on the frame it first
        // appears — the root draws it again once it has found it (B59, A2).
        #expect(picture(harness.frame(view))[3] == "   row")
        #expect(harness.geometryCorrections.root == 1)
        // From then on the root carries an origin, and the stack predicts it.
        #expect(picture(harness.frame(view))[3] == "   row")
        #expect(harness.geometryCorrections.root == 1)
    }

    @Test("An effect asking a named space is answered in it, and an effect asking only its size stamps nothing")
    func namedSpaceAndLocalEffects() {
        let harness = InputChainHarness()
        let named = harness.frame(
            VStack(alignment: .leading, spacing: 0) {
                Text("a")
                Text("row").visualEffect { content, proxy in
                    content.offset(x: proxy.frame(in: .named("list")).minY * 2)
                }
            }
            .coordinateSpace(.named("list")))
        #expect(picture(named)[1] == "  row")
        #expect(harness.geometryCorrections.total == 0)
        let local = harness.frame(Text("abc").visualEffect { content, proxy in content.offset(x: proxy.size.width) })
        #expect(!local.carriesGeometryMarkers)
    }

    @Test("An effect keeps its marker when its content stops stamping one: no correction for it")
    func markerSlotIgnoresContent() {
        let harness = InputChainHarness()
        let page = { (observed: Bool) in
            VStack(alignment: .leading, spacing: 0) {
                Text("a")
                // A row down that the prediction does not follow: the effect's
                // residual carries it from frame to frame.
                UnconvertedContainer {
                    // An `AnyView` draws at the effect's own identity, so an
                    // observer in it claims a marker slot there too.
                    AnyView(
                        observed
                            ? AnyView(Text("row").onScrollVisibilityChange { _ in })
                            : AnyView(Text("row"))
                    )
                    .visualEffect { content, proxy in content.offset(x: proxy.frame(in: .global).origin.y) }
                }
            }
        }
        harness.frame(page(true))
        harness.frame(page(true))
        let settled = harness.geometryCorrections
        #expect(picture(harness.frame(page(false)))[2] == "  row")
        #expect(picture(harness.frame(page(true)))[2] == "  row")
        // The effect's marker is the same marker whatever its content draws,
        // so the residual kept for it is kept, and it is predicted.
        #expect(harness.geometryCorrections == settled)
    }

    @Test("An effect drawn from its place on its first frame, under an animation, is not slid there from a guess")
    func firstFrameUnderAnimationDoesNotSlide() {
        let harness = InputChainHarness { environment in
            environment.canAnimate = true
            environment.transaction = Transaction(animation: .linear(duration: 1))
        }
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("a")
            Text("b")
            Text("c")
            Text("row").visualEffect { content, proxy in
                content.offset(x: proxy.frame(in: .global).origin.y)
            }
        }
        // The first drawing is told nothing (the root starts no origin before
        // it has a reader) and offsets by 0; the root's correction tells it 3.
        // An appearance does not animate, and the first drawing was never
        // shown: the frame draws the row three cells right, not on its way.
        #expect(picture(harness.frame(view))[3] == "   row")
        harness.now += 500_000_000
        #expect(picture(harness.frame(view))[3] == "   row")
    }
}
