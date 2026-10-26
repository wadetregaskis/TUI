//  🖥️ TUI — A Terminal UI framework for Swift
//  SGRStateUnderlineTests.swift
//
//  SGRState netting an underline's shape (`4:n`) and colour (SGR 58/59) as
//  state of its own, so turning a styled underline off turns all of it off.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

@Suite("SGRState underline shapes and colours")
struct SGRStateUnderlineTests {

    private func state(_ sequences: String...) -> SGRState {
        var state = SGRState()
        for sequence in sequences { state.apply(sequence) }
        return state
    }

    @Test("Each shape is netted and spelled back as 4:n, single as 4")
    func shapes() {
        #expect(state("\u{1B}[4:3m").rendered == "\u{1B}[4:3m")
        #expect(state("\u{1B}[4:2m").rendered == "\u{1B}[4:2m")
        #expect(state("\u{1B}[4:1m").rendered == "\u{1B}[4m")
        #expect(state("\u{1B}[4:4m", "\u{1B}[4m").rendered == "\u{1B}[4m", "a plain 4 makes the line single again")
        #expect(state("\u{1B}[4:5m", "\u{1B}[4:0m").isDefault)
    }

    @Test("SGR 24 ends a styled underline whole: nothing of it is replayed")
    func offEndsTheShape() {
        // As a passthrough, `4:3` outlived the 24 and turned the curly line
        // back on wherever the state was replayed.
        #expect(state("\u{1B}[4:3m", "\u{1B}[24m").isDefault)
        #expect(state("\u{1B}[4:3m", "\u{1B}[0m").isDefault)
    }

    @Test("The colour is netted in either spelling, spelled with colons, and cleared by 59 or 0")
    func colour() {
        #expect(state("\u{1B}[4;58:5:196m").rendered == "\u{1B}[4;58:5:196m")
        #expect(state("\u{1B}[58:2::255:0:0m").rendered == "\u{1B}[58:2::255:0:0m")
        #expect(state("\u{1B}[58:2:255:0:0m").rendered == "\u{1B}[58:2::255:0:0m")
        #expect(state("\u{1B}[58;5;46m").rendered == "\u{1B}[58:5:46m")
        #expect(state("\u{1B}[4;58:5:1m", "\u{1B}[59m").rendered == "\u{1B}[4m")
        #expect(state("\u{1B}[4;58:5:1m", "\u{1B}[0m").isDefault)
        // 24 ends the line but not its colour, as on a terminal.
        #expect(state("\u{1B}[4;58:5:1m", "\u{1B}[24m").rendered == "\u{1B}[58:5:1m")
    }

    @Test("A change of shape or colour alone is a delta of just that")
    func deltas() {
        let single = state("\u{1B}[4m")
        let curly = state("\u{1B}[4:3m")
        let red = state("\u{1B}[4:3;58:5:196m")
        #expect(curly.rendered(changingFrom: single) == "\u{1B}[4:3m")
        #expect(single.rendered(changingFrom: curly) == "\u{1B}[4m")
        #expect(red.rendered(changingFrom: curly) == "\u{1B}[58:5:196m")
        #expect(curly.rendered(changingFrom: red) == "\u{1B}[59m")
        // Off is a reset, as every attribute going off is.
        #expect(SGRState().rendered(changingFrom: curly) == "\u{1B}[0m")
    }

    @Test("An underlined blank cell shows its line's shape and colour")
    func blankCells() {
        let single = state("\u{1B}[4m")
        #expect(!single.paintsBlankCellsIdentically(to: state("\u{1B}[4:4m")))
        #expect(!single.paintsBlankCellsIdentically(to: state("\u{1B}[4;58:5:2m")))
        #expect(single.paintsBlankCellsIdentically(to: state("\u{1B}[4:1m")))
        // Without the line, its colour shows nowhere.
        #expect(SGRState().paintsBlankCellsIdentically(to: state("\u{1B}[58:5:2m")))
    }

    @Test("Other colon-form parameters still pass through untouched")
    func otherSubparametersPassThrough() {
        #expect(state("\u{1B}[4:9m").rendered == "\u{1B}[4:9m")
        #expect(state("\u{1B}[38:2::1:2:3m").rendered == "\u{1B}[38:2::1:2:3m")
    }
}
