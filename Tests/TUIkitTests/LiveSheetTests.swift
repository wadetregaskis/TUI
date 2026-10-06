//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiveSheetTests.swift
//
//  `presentationBackgroundInteraction(.enabled)`: a detented sheet docked at
//  the bottom of the content area beside a live page — a pane, not a modal.
//  The input side, through the real input chain; the layout (the page laid out
//  in the rows above the sheet) is LiveSheetLayoutTests'.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The page's and the sheet's state, by reference so the bindings a frame
/// built reach it.
@MainActor
final class LiveSheetModel {
    var presented = true
    var detent: PresentationDetent = .height(6)
    var alerting = false
    var pagePresses = 0
    var pageChords = 0
    var sheetPresses = 0
    var presentedBinding: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
    var detentBinding: Binding<PresentationDetent> { Binding(get: { self.detent }, set: { self.detent = $0 }) }
    var alertBinding: Binding<Bool> { Binding(get: { self.alerting }, set: { self.alerting = $0 }) }
}

/// What a live `item:` sheet is presented for.
struct LiveNote: Identifiable {
    let id: Int
}

/// A page with a button, and a live `item:` sheet over it.
private struct LiveItemPage: View {
    let item: Binding<LiveNote?>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Page A") {}
            Spacer()
        }
        .sheet(item: item) { note in
            Panel("Note \(note.id)") { Button("Inside") {} }
                .presentationDetents([.height(6), .large])
                .presentationBackgroundInteraction(.enabled)
        }
    }
}

/// A page with two buttons and a chord, and a sheet over it whose content
/// says `interaction`, at `[.height(6), .large]`.
private struct LivePage: View {
    let model: LiveSheetModel
    var interaction: PresentationBackgroundInteraction = .enabled
    /// A button at the page's foot, under where the sheet docks.
    var footButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Page A") { model.pagePresses += 1 }
            Button("Page B") { model.pagePresses += 10 }
                .keyboardShortcut("n", modifiers: .control)
            Spacer()
            if footButton {
                // As wide as the page, so the sheet's cells are over it.
                Button(String(repeating: "F", count: 36)) { model.pagePresses += 100 }
            }
        }
        .sheet(isPresented: model.presentedBinding) {
            Panel("Sheet") {
                Button("Inside") { model.sheetPresses += 1 }
                    .alert("Sure?", isPresented: model.alertBinding) { Button("OK") {} }
            }
            .presentationDetents([.height(6), .large], selection: model.detentBinding)
            .presentationBackgroundInteraction(interaction)
        }
    }
}

@MainActor
@Suite("A live sheet beside its page", .rendersEnglishUI)
struct LiveSheetTests {
    private static let width = 40
    private static let height = 20

    private func harness() -> InputChainHarness {
        let harness = InputChainHarness(width: Self.width, height: Self.height) { environment in
            environment.terminalWidth = Self.width
            environment.overlayContentHeight = Self.height
        }
        harness.statusBar.showThemeItem = true
        return harness
    }

    /// A frame, composited, with the composited regions live — the sheet's
    /// as well as the page's.
    @discardableResult
    private func frame(_ harness: InputChainHarness, _ view: some View) -> FrameBuffer {
        let composited = harness.frame(view).compositingOverlays(
            maxWidth: Self.width, maxHeight: Self.height, palette: harness.context.environment.palette)
        harness.tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        return composited
    }

    /// Two frames: the sheet is presented and has taken the focus.
    private func open(_ harness: InputChainHarness, _ view: some View) {
        frame(harness, view)
        frame(harness, view)
    }

    /// Tabs until the focus is on the page (`page`) or in the sheet, at most
    /// eight times.
    private func tab(toPage page: Bool, _ harness: InputChainHarness, _ view: some View) {
        for _ in 0..<8 where (harness.focusManager.activePaneID == nil) != page {
            harness.press(KeyEvent(key: .tab))
            frame(harness, view)
        }
    }

    private func click(_ text: String, on screen: FrameBuffer, _ harness: InputChainHarness) throws {
        let rows = screen.lines.map(\.stripped)
        let row = try #require(rows.lastIndex { $0.contains(text) }, "\(text) is not drawn: \(rows)")
        let column = try #require(rows[row].range(of: text)).lowerBound.utf16Offset(in: rows[row])
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: column + 1, y: row))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: column + 1, y: row))
    }

    /// The `.enabled` twin of PresentationInteractionTests.backgroundIsInert.
    @Test("With background interaction enabled, the page behind a sheet takes keys and clicks")
    func backgroundIsLive() throws {
        let harness = harness()
        let model = LiveSheetModel()
        let view = LivePage(model: model)
        open(harness, view)
        #expect(harness.focusManager.activePaneID != nil, "presenting did not move the focus into the sheet")
        tab(toPage: true, harness, view)
        #expect(harness.focusManager.activePaneID == nil, "Tab did not reach the page")
        harness.press(KeyEvent(key: .enter))
        let screen = frame(harness, view)
        #expect(model.pagePresses == 1, "the page's focused button did not take Return")
        try click("Page A", on: screen, harness)
        frame(harness, view)
        #expect(model.pagePresses == 2, "the page's button did not take the click")
        harness.press(KeyEvent(key: .character("n"), ctrl: true))
        #expect(model.pagePresses == 12, "the page's chord did not fire")
    }

    /// The `activatePresentedSection` trap: a live sheet that took its section
    /// back every frame pulled the focus off the page on the frame after the
    /// Tab that put it there.
    @Test("The focus Tab puts on the page stays there, frame after frame, and Tab goes back into the sheet")
    func focusStaysWhereTabPutsIt() {
        let harness = harness()
        let model = LiveSheetModel()
        let view = LivePage(model: model)
        open(harness, view)
        tab(toPage: true, harness, view)
        let onPage = harness.focusManager.currentFocusedID
        #expect(onPage != nil)
        for _ in 0..<5 { frame(harness, view) }
        #expect(harness.focusManager.currentFocusedID == onPage, "the sheet took the focus back")
        #expect(harness.focusManager.activePaneID == nil)
        tab(toPage: false, harness, view)
        #expect(harness.focusManager.activePaneID != nil, "Tab did not go back into the sheet")
        for _ in 0..<3 { frame(harness, view) }
        #expect(harness.focusManager.activePaneID != nil)
    }

    @Test("A click on a blank cell of the sheet does not reach the page control under it")
    func sheetCellsAreTheSheets() throws {
        let harness = harness()
        let model = LiveSheetModel()
        // No root lays the page out short here, so the page is the whole
        // height and its foot button sits under the docked sheet — as on the
        // frame a dock is learnt late.
        let view = LivePage(model: model, footButton: true)
        open(harness, view)
        // The sheet's bottom border, over the foot button.
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: Self.width / 2, y: Self.height - 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: Self.width / 2, y: Self.height - 1))
        frame(harness, view)
        #expect(model.pagePresses == 0, "a click on the sheet pressed the page's button under it")
        let screen = frame(harness, view)
        try click("Inside", on: screen, harness)
        #expect(model.sheetPresses == 1, "the sheet's own button did not take the click")
    }

    @Test("Escape is the sheet's with the focus in it, and the page's with the focus on the page")
    func escapeIsThePanes() {
        let harness = harness()
        let model = LiveSheetModel()
        let view = LivePage(model: model)
        open(harness, view)
        tab(toPage: true, harness, view)
        harness.press(KeyEvent(key: .escape))
        frame(harness, view)
        #expect(model.presented, "Escape on the page dismissed the sheet")
        tab(toPage: false, harness, view)
        harness.press(KeyEvent(key: .escape))
        frame(harness, view)
        #expect(!model.presented, "Escape in the sheet did not dismiss it")
    }

    @Test("The app's chrome keys stay live, and nothing is marked modal or grabbed")
    func chromeKeysAreLive() {
        let harness = harness()
        let model = LiveSheetModel()
        open(harness, LivePage(model: model))
        #expect(harness.focusManager.activePaneID != nil, "precondition: the focus is in the sheet")
        #expect(!harness.focusManager.activeSectionIsModal)
        #expect(harness.tui.keyEventDispatcher.grabbingSectionID == nil)
        #expect(harness.press(KeyEvent(key: .character("t"))), "t is grounded behind a live sheet")

        let modal = self.harness()
        let inert = LiveSheetModel()
        open(modal, LivePage(model: inert, interaction: .disabled))
        #expect(!modal.press(KeyEvent(key: .character("t"))), "precondition: t is grounded behind a modal sheet")
    }

    @Test("Above its upThrough detent the sheet is a modal again; back at it, the focus stays in the sheet")
    func upThroughThreshold() {
        let harness = harness()
        let model = LiveSheetModel()
        let view = LivePage(model: model, interaction: .enabled(upThrough: .height(6)))
        open(harness, view)
        tab(toPage: true, harness, view)
        #expect(harness.focusManager.activePaneID == nil, "precondition: the focus is on the page")

        model.detent = .large
        let grown = harness.frame(view)
        frame(harness, view)
        #expect(grown.overlays.first?.dimsBackground == true, "the grown sheet does not dim the page")
        #expect(grown.overlays.first?.level == .modal)
        #expect(harness.focusManager.activeSectionIsModal, "the grown sheet did not take the focus")
        #expect(harness.tui.keyEventDispatcher.grabbingSectionID != nil, "the grown sheet does not grab the input")

        model.detent = .height(6)
        let shrunk = harness.frame(view)
        frame(harness, view)
        #expect(shrunk.overlays.first?.dimsBackground == false)
        #expect(shrunk.overlays.first?.level == .popover)
        #expect(!harness.focusManager.activeSectionIsModal)
        #expect(harness.focusManager.activePaneID != nil, "shrinking moved the focus out of the sheet")
        #expect(harness.tui.keyEventDispatcher.grabbingSectionID == nil)
    }

    @Test("A live sheet presented for another item takes the focus, as a newly presented one does")
    func anotherItemTakesTheFocus() {
        let harness = harness()
        var current: LiveNote? = LiveNote(id: 1)
        let view = LiveItemPage(item: Binding(get: { current }, set: { current = $0 }))
        open(harness, view)
        tab(toPage: true, harness, view)
        #expect(harness.focusManager.activePaneID == nil, "precondition: the focus is on the page")
        current = LiveNote(id: 2)
        frame(harness, view)
        frame(harness, view)
        #expect(harness.focusManager.activePaneID != nil, "the second item's sheet left the focus on the page")
    }

    @Test("Dismissed with the focus on the page, the sheet leaves the focus where it is")
    func dismissalLeavesThePageFocus() {
        let harness = harness()
        let model = LiveSheetModel()
        let view = LivePage(model: model)
        open(harness, view)
        tab(toPage: true, harness, view)
        let onPage = harness.focusManager.currentFocusedID
        model.presented = false
        frame(harness, view)
        frame(harness, view)
        #expect(harness.focusManager.currentFocusedID == onPage)
    }

    @Test("An alert from inside a live sheet takes the keyboard, the page's chords included, and gives it back to the sheet")
    func alertInsideALiveSheet() {
        let harness = harness()
        let model = LiveSheetModel()
        let view = LivePage(model: model)
        open(harness, view)
        let inSheet = harness.focusManager.activeSectionIdentifier
        model.alerting = true
        frame(harness, view)
        frame(harness, view)
        #expect(harness.focusManager.activeSectionIsModal, "the alert did not take the focus")
        #expect(harness.tui.keyEventDispatcher.grabbingSectionID != nil, "the alert does not grab the input")
        harness.press(KeyEvent(key: .character("n"), ctrl: true))
        #expect(model.pagePresses == 0, "the page's chord fired from under the alert")
        harness.press(KeyEvent(key: .escape))
        frame(harness, view)
        frame(harness, view)
        #expect(!model.alerting, "Escape did not close the alert")
        #expect(model.presented, "Escape closed the sheet with the alert")
        #expect(harness.focusManager.activeSectionIdentifier == inSheet, "the focus did not return to the sheet")
    }

    @Test("A page drop-down opens over the sheet")
    func pageDropDownDrawsOverTheSheet() {
        let harness = InputChainHarness(width: Self.width, height: 12) { environment in
            environment.terminalWidth = Self.width
            environment.overlayContentHeight = 12
        }
        let model = LiveSheetModel()
        let selection = Binding<Int>(get: { 0 }, set: { _ in })
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("page")
            Picker("Pick", selection: selection) {
                ForEach(0..<8, id: \.self) { Text("option \($0)").tag($0) }
            }
            Spacer()
        }
        .sheet(isPresented: model.presentedBinding) {
            Panel("Sheet") { Text("sheet body") }
                .presentationDetents([.height(6)])
                .presentationBackgroundInteraction(.enabled)
        }
        func composited() -> [String] {
            harness.frame(view).compositingOverlays(
                maxWidth: Self.width, maxHeight: 12, palette: harness.context.environment.palette
            ).lines.map(\.stripped)
        }
        _ = composited()
        _ = composited()
        tab(toPage: true, harness, view)
        harness.press(KeyEvent(key: .enter))
        let rows = composited()
        let lastOption = rows.lastIndex { $0.contains("option 7") }
        #expect(lastOption.map { $0 >= 6 } == true, "the drop-down is not drawn over the sheet's rows: \(rows)")
        #expect(harness.tui.keyEventDispatcher.grabbingSectionID != nil, "the open drop-down does not hold the keyboard")
    }
}
