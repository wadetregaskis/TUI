//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowDrawsOncePerFrameTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUILists
@testable import TUIStyling
@testable import TUITestSupport

/// A row no memo can serve — a live canvas in its own `TimelineView` — is drawn
/// once a frame, however many of the list's passes read it: the overflow walk
/// draws it, and the window and the composer are handed that drawing. The row
/// that broke this was the focused, selected one, which the walk drew at the
/// standard prominence before the list raised it, and the raise then drew again.
@MainActor
@Suite("A List row draws once a frame")
struct ListRowDrawsOncePerFrameTests {

    /// The canvases' draws, by row, each with the prominence it was drawn under.
    final class Draws { var byRow: [Int: [BackgroundProminence]] = [:] }

    /// Renders `view` three times in one app, a sixtieth of a second apart —
    /// the first pass registers the focus stops, and the focus is then given
    /// to `focusID` — and returns the draws of the last pass.
    private func lastFrameDraws<V: View>(
        _ view: V, draws: Draws, focusID: String, beforeLastPass: () -> Void = {}
    ) -> [Int: [BackgroundProminence]] {
        var tick = 0
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let scheduler = AnimationScheduler()
        func pass() {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            environment.animationScheduler = scheduler
            environment.frameNowNanos = Int64(tick) * 16_666_667
            let context = RenderContext(
                availableWidth: 40, availableHeight: 30, environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            // Every row's timeline at a new entry, so no memo serves its canvas.
            tuiContext.renderCache.frameDate = Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(tick) / 60)
            tick += 1
            focusManager.beginRenderPass()
            scheduler.beginFrame()
            _ = renderToBuffer(view, context: context)
            scheduler.endFrame()
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
        }
        pass()
        focusManager.focus(id: focusID)
        pass()
        beforeLastPass()
        draws.byRow = [:]
        pass()
        return draws.byRow
    }

    /// A row whose canvas draws its timeline's entry.
    private struct CanvasRow: View {
        let index: Int
        let draws: Draws

        var body: some View {
            TimelineView(.animation) { [index, draws] timeline in
                let phase = Int(timeline.date.timeIntervalSinceReferenceDate * 60) % 8
                Canvas { context, _ in
                    draws.byRow[index, default: []].append(context.environment.backgroundProminence)
                    context.fill(Path(CGRect(x: phase, y: 0, width: 2, height: 1)), with: .color(.red))
                }
            }
            .frame(width: 10, height: 2)
        }
    }

    private func rows(_ draws: Draws, focusID: String) -> some View {
        List(selection: .constant(Set([0]))) {
            ForEach(0..<5, id: \.self) { index in CanvasRow(index: index, draws: draws) }
        }
        .focusID(focusID)
    }

    @Test("A focused list draws its selected cursor row once, raised")
    func focusedSelectedRowOnce() {
        let draws = Draws()
        let drawn = lastFrameDraws(rows(draws, focusID: "rows"), draws: draws, focusID: "rows")
        #expect(drawn[0] == [.increased], "the cursor's selected row, once and raised: \(drawn)")
        for index in 1..<5 {
            #expect(drawn[index] == [.standard], "row \(index), once: \(drawn)")
        }
    }

    /// How many rows ``GrowingRows`` has: read by its body on every pass.
    final class RowCount { var value = 0 }

    /// A focused, selecting list whose rows are ``RowCount``'s, as a file
    /// panel's are before and after its folder is read.
    private struct GrowingRows: View {
        let count: RowCount
        let draws: Draws

        var body: some View {
            List(selection: .constant(Set([0]))) {
                ForEach(0..<count.value, id: \.self) { index in CanvasRow(index: index, draws: draws) }
            }
            .focusID("rows")
        }
    }

    /// The raise before the overflow walk runs before the list has handed its
    /// handler this frame's ids: the handler's row count is already this
    /// frame's, but its id lookup still reads last frame's rows. Asking it
    /// whether the cursor's row is selected, on the first frame a focused
    /// list has rows, read past the end of none (a trap, which took two gate
    /// groups' test processes down with it).
    @Test("A focused list that gains its rows raises its selected cursor row, reading this frame's ids")
    func focusedListGainingRows() {
        let draws = Draws()
        let count = RowCount()
        let drawn = lastFrameDraws(
            GrowingRows(count: count, draws: draws), draws: draws, focusID: "rows",
            beforeLastPass: { count.value = 3 })
        // Raised every time it is drawn. Not once: on this frame the raise
        // moves, from no row to this one, and a moved raise discards the
        // renders of the rows it moved between (`raiseBackgroundProminence`),
        // so the window walk draws it again, as on any frame the cursor moves.
        let first = drawn[0] ?? []
        #expect(!first.isEmpty && first.allSatisfy { $0 == .increased }, "the cursor's selected row, raised: \(drawn)")
        #expect(drawn[2] == [.standard], "a row the list gained, once: \(drawn)")
    }

    @Test("A list without the focus draws each row once, none raised")
    func unfocusedRowsOnce() {
        let draws = Draws()
        let page = VStack {
            Button("Elsewhere") {}.focusID("elsewhere")
            rows(draws, focusID: "rows")
        }
        let drawn = lastFrameDraws(page, draws: draws, focusID: "elsewhere")
        for index in 0..<5 {
            #expect(drawn[index] == [.standard], "row \(index), once: \(drawn)")
        }
    }
}
