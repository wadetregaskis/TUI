//  🖥️ TUI — A Terminal UI framework for Swift
//  DialogDragTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing
@testable import TUICore
@testable import TUIFoundation
@testable import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("Dialog drag and resize behaviour")
struct DialogDragTests {
    @Test("Symmetrical width resizing when centred in viewport")
    func symmetricalWidthResizingWhenCentred() {
        let handler = _DialogDragHandler()
        handler.currentWidth = 60
        handler.currentHeight = 20

        // Begin resize drag while centred (offsetX == 0)
        handler.beginDrag(mode: .resizeWidth, atX: 59, y: 19)

        // Drag right by 3 cells (atX: 62) in a viewport of width 100
        handler.updateDrag(toX: 62, y: 19, screenWidth: 100, screenHeight: 40)

        // Symmetrical: width expands by 2 * 3 = 6 cells
        #expect(handler.userWidth == 66)
        // Offset remains 0 so the dialog remains centred
        #expect(handler.offsetX == 0)
    }

    @Test("Symmetrical height resizing when centred in viewport")
    func symmetricalHeightResizingWhenCentred() {
        let handler = _DialogDragHandler()
        handler.currentWidth = 60
        handler.currentHeight = 20

        // Begin resize drag while centred vertically (offsetY == 0)
        handler.beginDrag(mode: .resizeHeight, atX: 59, y: 19)

        // Drag down by 2 cells (atY: 21) in a viewport of height 40
        handler.updateDrag(toX: 59, y: 21, screenWidth: 100, screenHeight: 40)

        // Symmetrical: height expands by 2 * 2 = 4 cells
        #expect(handler.userHeight == 24)
        // Offset remains 0 so the dialog remains centred vertically
        #expect(handler.offsetY == 0)
    }

    @Test("Anchored width resizing when off-centre")
    func anchoredWidthResizingWhenOffCentre() {
        let handler = _DialogDragHandler()
        handler.currentWidth = 60
        handler.currentHeight = 20

        // Move dialog off-centre first
        handler.beginDrag(mode: .move, atX: 0, y: 0)
        handler.updateDrag(toX: 5, y: 0, screenWidth: 100, screenHeight: 40)
        handler.endDrag()
        #expect(handler.offsetX == 5)

        // Begin resize drag while off-centre
        handler.beginDrag(mode: .resizeWidth, atX: 59, y: 19)

        // Drag right by 3 cells (atX: 62)
        handler.updateDrag(toX: 62, y: 19, screenWidth: 100, screenHeight: 40)

        // Normal/anchored resize: width expands by 3 cells
        #expect(handler.userWidth == 63)
        // Left edge position: pressCentre = (100 - 60) / 2 = 20; placed at 20 + 5 = 25.
        // New targetCentre = (100 - 63) / 2 = 18.
        // New offsetX = 5 + (20 - 18) = 7. Placed at 18 + 7 = 25 (left edge anchored at 25).
        #expect(handler.offsetX == 7)
    }

    @Test("Resize commits dimensions and invokes onResize callback on endDrag")
    func resizeCommitsAndInvokesOnResize() {
        let handler = _DialogDragHandler()
        handler.currentWidth = 60
        handler.currentHeight = 20

        var reportedWidth: Int?
        var reportedHeight: Int?
        handler.onResize = { w, h in
            reportedWidth = w
            reportedHeight = h
        }

        handler.beginDrag(mode: .resizeBoth, atX: 59, y: 19)
        handler.updateDrag(toX: 62, y: 22, screenWidth: 100, screenHeight: 40)
        handler.endDrag()

        #expect(handler.userWidth == 66)
        #expect(handler.userHeight == 26)
        #expect(reportedWidth == 66)
        #expect(reportedHeight == 26)
    }

    @Test("Plain click on resize border does not commit size or invoke onResize")
    func plainClickOnResizeBorderDoesNotCommitSize() {
        let handler = _DialogDragHandler()
        handler.currentWidth = 60
        handler.currentHeight = 20

        var resizeCalled = false
        handler.onResize = { _, _ in
            resizeCalled = true
        }

        // Click on right border (resizeWidth) with no movement
        handler.beginDrag(mode: .resizeWidth, atX: 59, y: 10)
        handler.endDrag()

        #expect(!resizeCalled)
        #expect(handler.userWidth == nil)
        #expect(handler.userHeight == nil)

        // Click on bottom-right corner (resizeBoth) with no movement
        handler.beginDrag(mode: .resizeBoth, atX: 59, y: 19)
        handler.endDrag()

        #expect(!resizeCalled)
        #expect(handler.userWidth == nil)
        #expect(handler.userHeight == nil)
    }

    @Test("endDrag without beginDrag does nothing")
    func endDragWithoutBeginDragDoesNothing() {
        let handler = _DialogDragHandler()
        handler.currentWidth = 60
        handler.currentHeight = 20

        var resizeCalled = false
        handler.onResize = { _, _ in
            resizeCalled = true
        }

        // updateDrag without beginDrag should be ignored
        handler.updateDrag(toX: 70, y: 30, screenWidth: 100, screenHeight: 40)
        #expect(handler.userWidth == nil)
        #expect(handler.userHeight == nil)
        #expect(handler.offsetX == 0)
        #expect(handler.offsetY == 0)

        // endDrag without beginDrag should do nothing
        handler.endDrag()
        #expect(!resizeCalled)
        #expect(handler.userWidth == nil)
        #expect(handler.userHeight == nil)

        // Also test: after a successful resize, a subsequent stray endDrag does not re-commit
        handler.beginDrag(mode: .resizeBoth, atX: 59, y: 19)
        handler.updateDrag(toX: 62, y: 22, screenWidth: 100, screenHeight: 40)
        handler.endDrag()

        #expect(resizeCalled)
        resizeCalled = false

        // Stray endDrag later
        handler.endDrag()
        #expect(!resizeCalled)
    }

    @Test("Dismissing mid-drag and then releasing saves nothing")
    func dismissingMidDragAndReleasingSavesNothing() {
        let handler = _DialogDragHandler()
        handler.currentWidth = 60
        handler.currentHeight = 20

        var resizeCalled = false
        handler.onResize = { _, _ in
            resizeCalled = true
        }

        // Drag begins and resizes
        handler.beginDrag(mode: .resizeBoth, atX: 59, y: 19)
        handler.updateDrag(toX: 62, y: 22, screenWidth: 100, screenHeight: 40)
        #expect(handler.userWidth == 66)
        #expect(handler.userHeight == 26)

        // Esc or dismissal runs reset() mid-drag
        handler.reset()
        #expect(handler.userWidth == nil)
        #expect(handler.userHeight == nil)
        #expect(handler.offsetX == 0)
        #expect(handler.offsetY == 0)

        // Late release arrives
        handler.endDrag()

        #expect(!resizeCalled)
        #expect(handler.userWidth == nil)
        #expect(handler.userHeight == nil)
        #expect(handler.offsetX == 0)
        #expect(handler.offsetY == 0)
    }
}
