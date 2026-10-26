//  🖥️ TUI — A Terminal UI framework for Swift
//  BackdropAnimationTests.swift
//
//  A dimmed backdrop is inert to INPUT, not to time. The page around a sheet
//  is on screen, so it has to keep moving — and the only affordable way for it
//  to move is the run the loop replays. Dropped, the page advanced solely when
//  something else happened to render.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

@testable import TUIApp
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

/// A page whose top row animates, and whose bottom row animates in glyphs the
/// backdrop flattens away.
///
/// Two runs, deliberately: the first survives the dim (`░`/`▒` are content),
/// the second must not (`█` is chrome the flatten replaces with a space, so
/// every frame becomes the same blank row).
private struct AnimatedPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("░░░░")
                .animatedCells([
                    AnimatedCellRun(
                        offsetX: 0, offsetY: 0, width: 4, frames: ["░░░░", "▒▒▒▒"],
                        frameTicks: 6, clock: .cursor)
                ])
            Text("████")
                .animatedCells([
                    AnimatedCellRun(
                        offsetX: 0, offsetY: 0, width: 4, frames: ["█▀██", "██▄█"],
                        frameTicks: 6, clock: .cursor)
                ])
            Text("page")
        }
    }
}

@MainActor
@Suite("A dimmed backdrop keeps animating")
struct BackdropAnimationTests {

    private final class BoolBox {
        var v = true
        var binding: Binding<Bool> { Binding(get: { self.v }, set: { self.v = $0 }) }
    }

    /// The whole screen as the run loop assembles it: render, then composite
    /// the overlay layers at the root — which is where the backdrop is dimmed
    /// and where a covered run is punched out.
    private func screen(_ view: some View, width: Int = 40, height: Int = 20) -> FrameBuffer {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        environment.overlayContentHeight = height
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.compositingOverlays(
            maxWidth: width, maxHeight: height, palette: context.environment.palette)
    }

    /// The report: with a dialog up, the dimmed page behind it animated in
    /// jerks. It had no run left to replay, so it advanced only when something
    /// else caused a full render — about 2.5 pictures a second on the
    /// Example's Progress page against the 30 it manages with nothing
    /// presented, each one a whole re-render of page, dim and dialog.
    @Test("A run on the page survives being the backdrop of a sheet")
    func sheetKeepsThePageAnimating() {
        let presented = BoolBox()
        let composited = screen(
            AnimatedPage().modal(isPresented: presented.binding) { Text("DIALOG") })
        #expect(
            composited.animatedCells.contains { $0.offsetY == 0 },
            "the page's top row lost its run behind the sheet")
    }

    /// The same run, flattened by the same rule as the row it sits in. A frame
    /// that reached the terminal in its own colours would show as a bright
    /// notch in a line that is one uniform dim span.
    /// That each replayed frame draws what a render draws behind a sheet is
    /// `ReplayedRunFieldTests`' "behind a sheet" case; this pins the veil.
    @Test("The backdrop row is veiled, not drawn in the page's own colours, and its runs keep their width")
    func rowsAreVeiledAndRunsKeepTheirWidth() {
        let presented = BoolBox()
        let composited = screen(
            AnimatedPage().modal(isPresented: presented.binding) { Text("DIALOG") })
        guard let run = composited.animatedCells.first(where: { $0.offsetY == 0 }) else {
            Issue.record("no run on the backdrop's top row")
            return
        }
        // Compared as the colours each OPENS with: the row's run may start
        // with a reset (`0;`) that a frame spliced into it does not repeat.
        let rowStyle = Self.leadingColours(of: composited.lines[0])
        let pageStyle = Self.leadingColours(of: screen(AnimatedPage()).lines[0])
        #expect(rowStyle != pageStyle, "the backdrop row kept the page's own colours: \(rowStyle.debugDescription)")
        for index in run.frames.indices {
            let frame = run.frame(atIndex: index)
            #expect(
                frame.stripped.count == run.frames[0].stripped.count,
                "frame \(index) changed the run's width")
        }
    }

    /// The SGR a string opens with, before its first printed cell, without a
    /// leading reset.
    private static func leadingColours(of text: String) -> String {
        let style = leadingStyle(of: text)
        return style.hasPrefix("\u{1B}[0;") ? "\u{1B}[" + style.dropFirst(4) : style
    }

    /// The escape sequences a string opens with, before its first printed cell.
    private static func leadingStyle(of text: String) -> String {
        var style = ""
        var rest = Substring(text)
        while rest.first == "\u{1B}" {
            guard let end = rest.firstIndex(of: "m") else { break }
            style += rest[rest.startIndex...end]
            rest = rest[rest.index(after: end)...]
        }
        return style
    }

    /// A run behind a sheet keeps its glyphs, veiled, so it keeps animating:
    /// an indeterminate `.pulse` bar goes on pulsing behind the dialog. (The
    /// flatten that came before dropped block glyphs as ornaments, so such a
    /// bar had nothing left to show, and its run was dropped.)
    @Test("A run behind a sheet keeps animating, veiled")
    func veiledRunsKeepAnimating() {
        let presented = BoolBox()
        let composited = screen(
            AnimatedPage().modal(isPresented: presented.binding) { Text("DIALOG") })
        #expect(
            composited.animatedCells.contains { $0.offsetY == 1 },
            "the bar's run was dropped behind the sheet")
    }

    /// The other half: a full-screen cover hides the page completely, so its
    /// runs are work with no picture at the end of it.
    @Test("A full-screen cover drops the page's runs")
    func coverDropsThePagesRuns() {
        let presented = BoolBox()
        let composited = screen(
            AnimatedPage().fullScreenCover(isPresented: presented.binding) { Text("COVER") })
        #expect(composited.animatedCells.isEmpty)
    }
}
