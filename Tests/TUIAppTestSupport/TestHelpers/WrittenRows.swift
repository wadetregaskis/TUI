//  🖥️ TUI — A Terminal UI framework for Swift
//  WrittenRows.swift
//
//  A buffer's rows as the run loop writes them: opened on the page, with the
//  page put back after every reset (`FrameDiffWriter.buildLine`). A suite about
//  which FIELD a cell shows needs this, not the buffer: the buffer spells a cell
//  on the terminal's own field (`ESC[49m`) and one that names no field alike, and
//  only the written row puts the page under the second.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

@testable import TUIApp
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// `buffer`'s rows as the terminal is sent them, on the page `palette` paints,
/// read back column by column. In a written row `""` is the terminal's own field
/// and the page is its own escape.
@MainActor
func writtenRows(_ buffer: FrameBuffer, palette: any Palette, width: Int) -> [[PaintedCell]] {
    let writer = FrameDiffWriter(program: .unidentified)
    return writer.buildOutputLines(
        buffer: buffer, terminalWidth: width, terminalHeight: buffer.lines.count,
        bgCode: RenderBackgroundCodes(palette: palette).content, reset: ANSIRenderer.reset
    ).map(paintedCells)
}

/// `view` rendered to the screen in truecolor — on `palette`, or the default one —
/// and written as the run loop writes it (``writtenRows(_:palette:width:)``).
@MainActor
func writtenRows(of view: some View, palette: (any Palette)? = nil, width: Int = 24, height: Int = 12)
    -> [[PaintedCell]]
{
    let context = makeRenderContext(width: width, height: height) { environment, _ in
        if let palette { environment.palette = palette }
    }
    return ColorDepth.withCurrent(.truecolor) {
        writtenRows(
            renderToScreen(view, context: context), palette: context.environment.palette, width: width)
    }
}

#endif
