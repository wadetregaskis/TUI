//  🖥️ TUI — A Terminal UI framework for Swift
//  OffsetTransitionTests.swift
//
//  A view drawn displaced (`.offset`) that comes and goes with a transition:
//  a toast offset into place over a page, moved in from the bottom and faded.
//  Its picture is all in layers past an empty footprint, and the effects
//  treated that footprint as the picture (the Materials clip, 2026-10-29):
//  the fade measured it nothing wide, so an overlay centring it drew the toast
//  half its width aside for the frames of the fade; the move blanked the
//  footprint's cells over the page and left the layers where they were, so
//  the toast appeared where it ended, unmoved.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

/// A page of dots, and over it a toast centred at the bottom, offset up and to
/// the left, as the Materials clip's "Publishing…" toast is.
private struct ToastHost: View {
    let showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlyphFill(".").frame(width: 60, height: 12)
        }
        .overlay(alignment: .bottom) {
            if showing {
                Text("TOAST").frame(width: 10)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 2)
                    .background(Color.red)
                    .offset(x: -12, y: -3)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

@MainActor
@Suite("An offset view's transition")
struct OffsetTransitionTests {
    /// Where the toast's text is at rest: the overlay centres the 14-wide toast
    /// in 60 columns (23) and the offset takes it 12 left and 3 up, and its
    /// text is two in, a row down.
    private static let restingColumn = 13
    private static let restingRow = 7
    /// The rows the toast's box covers at rest.
    private static let restingRows = 6...8

    /// The frames of the toast arriving and then leaving, every 50 ms of a
    /// 0.3 s ease, as the composited screen shows them.
    private func frames() -> (arriving: [[String]], leaving: [[String]]) {
        var context = makeRenderContext(width: 70, height: 14)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .easeInOut(duration: 0.3))
        func draw(_ showing: Bool, _ millis: Int) -> [String] {
            context.environment.frameNowNanos = Int64(millis) * 1_000_000
            let storage = context.environment.stateStorage!
            storage.beginRenderPass()
            defer { storage.endRenderPass() }
            return renderToBuffer(ToastHost(showing: showing), context: context)
                .compositingOverlays(maxWidth: 70, maxHeight: 14, palette: SystemPalette.green)
                .lines.map { $0.stripped }
        }
        _ = draw(false, 0)
        let arriving = stride(from: 0, through: 400, by: 50).map { draw(true, 1000 + $0) }
        let leaving = stride(from: 0, through: 400, by: 50).map { draw(false, 2000 + $0) }
        return (arriving, leaving)
    }

    /// Where the toast's text is drawn on `screen`, if it is.
    private func toast(on screen: [String]) -> (column: Int, row: Int)? {
        for (row, line) in screen.enumerated() {
            if let found = line.range(of: "TOAST") {
                return (line.distance(from: line.startIndex, to: found.lowerBound), row)
            }
        }
        return nil
    }

    @Test("The toast stays in its column on every frame of its fade")
    func staysInItsColumn() {
        let (arriving, leaving) = frames()
        for screen in arriving + leaving {
            guard let at = toast(on: screen) else { continue }
            #expect(at.column == Self.restingColumn, "\(screen.joined(separator: "\n"))")
        }
    }

    @Test("The toast moves up into place from below, and back down out of it")
    func movesInAndOut() {
        let (arriving, leaving) = frames()
        let rowsIn = arriving.compactMap { toast(on: $0)?.row }
        let rowsOut = leaving.compactMap { toast(on: $0)?.row }
        #expect(rowsIn.contains { $0 > Self.restingRow }, "it appeared in place: \(rowsIn)")
        #expect(rowsIn.last == Self.restingRow)
        #expect(rowsIn == rowsIn.sorted(by: >), "\(rowsIn)")
        #expect(rowsOut.contains { $0 > Self.restingRow }, "it vanished in place: \(rowsOut)")
        #expect(rowsOut == rowsOut.sorted(), "\(rowsOut)")
    }

    @Test("Where the toast is laid out, nothing is blanked while it moves")
    func paintsNothingInItsSlot() {
        let (arriving, leaving) = frames()
        for screen in arriving + leaving {
            let toastRow = toast(on: screen)?.row
            for (row, line) in screen.enumerated() where row < 12 && row != toastRow {
                let settled = toastRow == Self.restingRow && Self.restingRows.contains(row)
                #expect(settled || line.allSatisfy { $0 == "." }, "row \(row): \(screen.joined(separator: "\n"))")
            }
        }
    }
}
