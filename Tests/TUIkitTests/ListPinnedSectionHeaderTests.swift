//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListPinnedSectionHeaderTests.swift
//
//  A `List` pins the header of the section its window opens in over the top
//  of its rows, as a macOS list floats its group rows (decisions A45): under
//  every style but `.sidebar` (measured: `NSTableView.floatsGroupRows`), with
//  the keyboard cursor kept below it and the covered row's lines the
//  header's to click. Footers never pin.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A list pins its section headers")
struct ListPinnedSectionHeaderTests {

    /// Two sections of plain rows, in a list too short for the first.
    private struct Fruit: View {
        let selection: Binding<String?>
        var body: some View {
            List(selection: selection) {
                Section("Fruit") {
                    ForEach((0..<20).map { "fruit\($0)" }, id: \.self) { Text($0) }
                }
                Section("Veg") {
                    ForEach((0..<4).map { "veg\($0)" }, id: \.self) { Text($0) }
                }
            }
        }
    }

    private final class Box: @unchecked Sendable {
        var selection: String?
    }

    /// The list, in a 30x8 window, in `style`, with the scroll bar drawn rather
    /// than the "N more" lines so the rows start on the first line.
    private func view(_ box: Box, style: some ListStyle) -> some View {
        Fruit(selection: Binding(get: { box.selection }, set: { box.selection = $0 }))
            .listStyle(style)
            .scrollIndicators(.visible)
    }

    private func lines(_ buffer: FrameBuffer) -> [String] { buffer.lines.map(\.stripped) }

    /// Moves the cursor `count` rows down, a frame after each.
    private func down(_ count: Int, in harness: InputChainHarness, _ build: () -> some View) -> FrameBuffer {
        var buffer = harness.frame(build())
        for _ in 0..<count {
            _ = harness.press(KeyEvent(key: .down))
            buffer = harness.frame(build())
        }
        return buffer
    }

    @Test("Scrolled into a section, a plain list draws its header on the first line")
    func pinsInPlain() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        let buffer = down(12, in: harness) { view(box, style: .plain) }
        let drawn = lines(buffer)
        #expect(!drawn.contains { $0.contains("fruit0") }, "the list did not scroll: \(drawn)")
        #expect(drawn.first?.contains("Fruit") == true, "the header is not pinned: \(drawn)")
        #expect(drawn.filter { $0.contains("Fruit") }.count == 1, "\(drawn)")
    }

    @Test("Every style but the sidebar pins", arguments: ["automatic", "inset", "bordered", "surface"])
    func pinsInOtherStyles(_ name: String) {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 9)
        let buffer: FrameBuffer
        switch name {
        case "automatic": buffer = down(12, in: harness) { view(box, style: .automatic) }
        case "inset": buffer = down(12, in: harness) { view(box, style: .inset) }
        case "bordered": buffer = down(12, in: harness) { view(box, style: .bordered) }
        default: buffer = down(12, in: harness) { view(box, style: .surface) }
        }
        let drawn = lines(buffer)
        let firstRow = drawn.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.contains("─") }
        #expect(firstRow?.contains("Fruit") == true, "\(name): \(drawn)")
    }

    @Test("A sidebar list does not pin")
    func sidebarDoesNotPin() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        let drawn = lines(down(12, in: harness) { view(box, style: .sidebar) })
        #expect(!drawn.contains { $0.contains("Fruit") }, "\(drawn)")
    }

    @Test("The header that pins is the section's the window opens in")
    func pinsTheRightSection() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        // Past the first section's last row and into the second's rows.
        let drawn = lines(down(23, in: harness) { view(box, style: .plain) })
        #expect(drawn.contains { $0.contains("veg2") }, "\(drawn)")
        if drawn.first?.contains("veg") == true || drawn.first?.contains("Veg") == true {
            #expect(!drawn.contains { $0.contains("Fruit") }, "Fruit pinned over Veg's rows: \(drawn)")
        }
    }

    /// Two sections of TWO-line rows, long enough to scroll well inside the
    /// first: every row taller than a line.
    private struct Tall: View {
        let selection: Binding<String?>
        var body: some View {
            List(selection: selection) {
                Section("Fruit") {
                    ForEach((0..<60).map { "fruit\($0)" }, id: \.self) { Text("\($0)\nmore") }
                }
                Section("Veg") {
                    ForEach((0..<20).map { "veg\($0)" }, id: \.self) { Text("\($0)\nmore") }
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.visible)
        }
    }

    @Test("The scroll bar follows the rows under a pinned header, not the header")
    func scrollBarIgnoresThePinnedHeader() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { Tall(selection: Binding(get: { box.selection }, set: { box.selection = $0 })) }
        /// The bar's column, top to bottom.
        func bar(_ buffer: FrameBuffer) -> String {
            buffer.lines.map { String($0.stripped.last ?? " ") }.joined()
        }
        let near = down(6, in: harness, build)
        let nearBar = bar(near)
        let far = down(30, in: harness, build)
        // Both scrolled inside Fruit, its header pinned over each.
        #expect(lines(near).first?.contains("Fruit") == true, "\(lines(near))")
        #expect(lines(far).first?.contains("Fruit") == true, "\(lines(far))")
        // Measured from the pinned header's index, the thumb sat at the top of
        // the track through the whole section.
        #expect(bar(far) != nearBar, "the thumb did not move: \(nearBar) then \(bar(far))")
    }

    @Test("Moving the cursor up keeps it below the pinned header")
    func cursorStaysBelowTheHeader() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { view(box, style: .plain) }
        _ = down(14, in: harness, build)
        // Up, one row at a time, past the point where the cursor reaches the top
        // of the window and has to push it up — selecting each row it lands on
        // so the row can be found in the frame.
        for step in 1...10 {
            _ = harness.press(KeyEvent(key: .up))
            _ = harness.press(KeyEvent(key: .space))
            let drawn = lines(harness.frame(build()))
            let selected = box.selection ?? ""
            #expect(!selected.isEmpty, "step \(step): Space selected nothing")
            guard drawn.first?.contains("Fruit") == true else { continue }
            let row = drawn.firstIndex { $0.firstMatch(of: /fruit\d+/).map { String($0.output) } == selected }
            #expect(row != nil, "step \(step): the cursor's row \(selected) is not drawn: \(drawn)")
        }
    }

    @Test("A click on the pinned header does not select the row under it")
    func clickOnTheHeaderSelectsNothing() throws {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { view(box, style: .plain) }
        let drawn = lines(down(12, in: harness, build))
        try #require(drawn.first?.contains("Fruit") == true, "\(drawn)")
        box.selection = nil
        harness.click(4, 0, build)
        #expect(box.selection == nil, "a click on the header selected \(box.selection ?? "")")
        // The line below it is a row, and a click there selects it.
        harness.click(4, 1, build)
        let below = drawn[1].firstMatch(of: /fruit\d+/).map { String($0.output) }
        #expect(box.selection != nil && box.selection == below, "\(String(describing: box.selection)) vs \(drawn[1])")
    }

    @Test("The stripes count on under the pinned header")
    func stripesKeepTheirRows() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { view(box, style: .plain).alternatingRowBackgrounds() }
        let buffer = down(12, in: harness, build)
        for line in buffer.lines {
            let text = line.stripped
            guard let match = text.firstMatch(of: /fruit(\d+)/), let index = Int(match.output.1) else { continue }
            // Row `fruitN` is the section's Nth row: odd ones stripe — unless it is
            // the cursor's, which wears the focus wash instead.
            if !index.isMultiple(of: 2), !line.contains("●") {
                #expect(line.contains("\u{1B}[48;"), "fruit\(index) lost its stripe")
            }
        }
    }

    @Test("A press on a row of a reorderable list leaves the header pinned")
    func pressKeepsThePin() throws {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = {
            List(selection: Binding(get: { box.selection }, set: { box.selection = $0 })) {
                Section("Fruit") {
                    ForEach((0..<20).map { "fruit\($0)" }, id: \.self) { Text($0) }.onMove { _, _ in }
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.visible)
        }
        let before = lines(down(12, in: harness, build))
        try #require(before.first?.contains("Fruit") == true, "\(before)")
        // Every press on a row of an `.onMove` list arms a reorder, inactive
        // until the pointer moves: a click, not yet a drag.
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 4, y: 3))
        let pressed = lines(harness.frame(build()))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 4, y: 3))
        _ = harness.frame(build())
        #expect(pressed.first?.contains("Fruit") == true, "the press unpinned the header: \(pressed)")
    }

    /// A three-line header over the first section, a one-line one over the second.
    private struct TallHeader: View {
        let selection: Binding<String?>
        var body: some View {
            List(selection: selection) {
                Section {
                    ForEach((0..<20).map { "fruit\($0)" }, id: \.self) { Text($0) }
                } header: {
                    Text("Fruit\nlong\nheader")
                }
                Section("Veg") {
                    ForEach((0..<20).map { "veg\($0)" }, id: \.self) { Text($0) }
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.visible)
        }
    }

    @Test("The cursor clears the header pinned over the window, an earlier section's taller one included")
    func cursorClearsTheHeaderThatCoversIt() throws {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 10)
        let build = { TallHeader(selection: Binding(get: { box.selection }, set: { box.selection = $0 })) }
        // The cursor onto veg1: the first Down lands on fruit0, then on through
        // Fruit's twenty rows and over Veg's header.
        _ = down(22, in: harness, build)
        _ = harness.press(KeyEvent(key: .space))
        _ = harness.frame(build())
        try #require(box.selection == "veg1", "\(String(describing: box.selection))")
        // Then the window opened at fruit19 (row 20, Fruit's header being row 0),
        // as a wheel can leave it: Fruit's three lines cover fruit19, Veg's
        // header and veg0, and veg1 is the first row seen.
        let list = try #require(harness.focusManager.currentFocused as? ItemListHandler<String>)
        list.scrollOffset = 20
        list.scrollTopClipLines = 0
        let drawn = lines(harness.frame(build()))
        try #require(drawn.first?.contains("Fruit") == true && drawn.count > 3 && drawn[3].contains("veg1"), "\(drawn)")
        // Up onto veg0, under Fruit's header: Veg's one-line header is not the one
        // covering it.
        _ = harness.press(KeyEvent(key: .up))
        _ = harness.press(KeyEvent(key: .space))
        let after = lines(harness.frame(build()))
        #expect(box.selection == "veg0", "\(String(describing: box.selection))")
        #expect(after.contains { $0.contains("veg0") }, "the cursor's row is under Fruit's header: \(after)")
    }

    @Test("A centred cursor stays below the pinned header")
    func centredCursorClearsTheHeader() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 2)
        let build = { view(box, style: .plain).scrollFollowMargin(.centered) }
        _ = harness.frame(build())
        for step in 1...8 {
            _ = harness.press(KeyEvent(key: .down))
            _ = harness.press(KeyEvent(key: .space))
            let drawn = lines(harness.frame(build()))
            let selected = box.selection ?? ""
            #expect(drawn.contains { $0.contains(selected) && !selected.isEmpty }, "step \(step): \(selected) is hidden: \(drawn)")
        }
    }

    @Test("A header that would take every line the rows have does not pin")
    func headerTallerThanTheRowsDoesNotPin() {
        let box = Box()
        let harness = InputChainHarness(width: 30, height: 1)
        let build = { view(box, style: .plain) }
        _ = harness.frame(build())
        for step in 1...6 {
            _ = harness.press(KeyEvent(key: .down))
            _ = harness.press(KeyEvent(key: .space))
            let drawn = lines(harness.frame(build()))
            let selected = box.selection ?? ""
            #expect(drawn.contains { $0.contains(selected) && !selected.isEmpty }, "step \(step): \(selected) is hidden: \(drawn)")
        }
    }
}
