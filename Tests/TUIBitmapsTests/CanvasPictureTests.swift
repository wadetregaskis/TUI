//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasPictureTests.swift
//
//  A `Canvas` where the terminal places pictures: which cells are the picture's,
//  and what is sent.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

private let red = Color.rgb(255, 0, 0)

@MainActor
@Suite("Canvas: as a picture", .serialized)
struct CanvasPictureTests {
    @Test("Where the terminal places pictures a canvas is one, at a cell's own pixels")
    func picture() {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(red))
        }
        var seen: (width: Int, height: Int)?
        let probe = Canvas { context, _ in seen = context.pixelGrid }
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellPixels = TerminalCellPixels(width: 16, height: 34)
        let context = RenderContext(availableWidth: 3, availableHeight: 2, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let store = tui.terminalImageStore
        let buffer = pictures { () -> FrameBuffer in
            _ = renderToBuffer(probe, context: context.withChildIdentity(erasedType: Int.self, key: "probe"))
            return renderToBuffer(canvas, context: context)
        }
        #expect(seen?.width == 3 * 8 && seen?.height == 2 * 17, "a 16×34 cell reduces to 8×17")
        #expect(placeholderCount(buffer) == 6, "every cell")
        let pending = store.takePending()
        #expect(pending.contains("a=t,"))
        #expect(pending.contains("s=24,v=34"), "\(pending.prefix(80))")
        #expect(pending.contains("f=24"), "opaque is RGB")
    }

    @Test("A cell the drawing leaves clear is not a picture's, and a glyph takes its own")
    func pictureWithHolesAndText() {
        let canvas = Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 2)), with: .color(red))
            context.draw(Text(verbatim: "x"), at: .zero, anchor: .topLeading)
        }
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellPixels = TerminalCellPixels(width: 8, height: 16)
        let context = RenderContext(availableWidth: 4, availableHeight: 1, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let buffer = pictures { renderToBuffer(canvas, context: context) }
        #expect(placeholderCount(buffer) == 1, "the second cell: the first has the glyph, the others no pixels")
        #expect(buffer.lines[0].stripped.hasPrefix("x"))
        #expect(tui.terminalImageStore.takePending().contains("f=32"), "not opaque, so it carries alpha")
    }

    @Test("The same drawing again sends nothing, and a changed one replaces it")
    func pictureIsSentOnce() {
        var side: CGFloat = 1
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellPixels = TerminalCellPixels(width: 8, height: 16)
        let context = RenderContext(availableWidth: 2, availableHeight: 1, environment: environment, tuiContext: tui)
        func frame() -> String {
            let canvas = Canvas { context, _ in
                context.fill(Path(CGRect(x: 0, y: 0, width: side, height: 2)), with: .color(red))
            }
            tui.stateStorage.beginRenderPass()
            defer { tui.stateStorage.endRenderPass() }
            _ = pictures { renderToBuffer(canvas, context: context) }
            return tui.terminalImageStore.takePending()
        }
        #expect(frame().contains("a=t,"))
        #expect(!frame().contains("a=t,"), "the terminal has it")
        side = 2
        #expect(frame().contains("a=t,"))
    }

    @Test("Asking for a grain draws glyphs even where pictures are on offer")
    func grainDeclinesPictures() {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(red))
        }
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 2, availableHeight: 1, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let buffer = pictures { renderToBuffer(canvas.canvasGrain(.quadrants), context: context) }
        #expect(placeholderCount(buffer) == 0)
    }

    @Test("A colour a pixel cannot hold is drawn in cells, spelled as itself")
    func colourWithoutChannels() {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.default))
        }
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 2, availableHeight: 1, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let buffer = pictures { renderToBuffer(canvas, context: context) }
        #expect(placeholderCount(buffer) == 0)
        #expect(tui.terminalImageStore.takePending().isEmpty)
    }

    /// `body`, on a terminal that places pictures, in full colour.
    private func pictures<Result>(_ body: () -> Result) -> Result {
        ColorDepth.withCurrent(.truecolor) { KittyGraphics.withSupport(true) { body() } }
    }

    private func placeholderCount(_ buffer: FrameBuffer) -> Int {
        buffer.lines.reduce(0) { $0 + $1.unicodeScalars.filter { $0 == .terminalImagePlaceholder }.count }
    }
}
