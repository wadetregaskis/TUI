//  🖥️ TUI — A Terminal UI framework for Swift
//  RadioButtonGroupBuilderTests.swift
//
//  The control flow `RadioButtonGroupBuilder`'s documentation promises: `if`,
//  `if`/`else`, `if let` and `for`…`in`, alone and mixed with plain items.
//  Until H-46b none of them compiled — `buildBlock` took items one by one and
//  had no way to take the array a loop or an `if` produces.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUIPickers
@testable import TUITestSupport

@MainActor
@Suite("RadioButtonGroupBuilder control flow")
struct RadioButtonGroupBuilderTests {

    private func values<Value>(_ group: RadioButtonGroup<Value>) -> [Value] {
        group.items.map(\.value)
    }

    private func rows(_ group: some View) -> [String] {
        renderToBuffer(group, context: makeRenderContext(width: 30, height: 10)).lines.map(\.stripped)
    }

    // MARK: - Each form on its own

    @Test("An if without an else contributes its item only when it runs", arguments: [true, false])
    func ifWithoutElse(showsExtra: Bool) {
        let group = RadioButtonGroup(selection: .constant("a")) {
            RadioButtonItem("a", "Alpha")
            if showsExtra {
                RadioButtonItem("x", "Extra")
            }
        }
        #expect(values(group) == (showsExtra ? ["a", "x"] : ["a"]))
    }

    @Test("An if/else contributes the branch that runs", arguments: [true, false])
    func ifElse(takesFirst: Bool) {
        let group = RadioButtonGroup(selection: .constant("a")) {
            if takesFirst {
                RadioButtonItem("a", "Alpha")
            } else {
                RadioButtonItem("b", "Bravo")
                RadioButtonItem("c", "Charlie")
            }
        }
        #expect(values(group) == (takesFirst ? ["a"] : ["b", "c"]))
    }

    @Test("An if let contributes its item only when the optional holds one")
    func ifLet() {
        func group(_ recent: String?) -> RadioButtonGroup<String> {
            RadioButtonGroup(selection: .constant("a")) {
                RadioButtonItem("a", "Alpha")
                if let recent {
                    RadioButtonItem(recent, recent)
                }
            }
        }
        #expect(values(group("r")) == ["a", "r"])
        #expect(values(group(nil)) == ["a"])
    }

    @Test("A for loop contributes one item per element, in order")
    func forIn() {
        let names = ["one", "two", "three"]
        let group = RadioButtonGroup(selection: .constant("one")) {
            for name in names {
                RadioButtonItem(name, name)
            }
        }
        #expect(values(group) == names)
    }

    @Test("A for loop over nothing gives an empty group")
    func forInEmpty() {
        let names: [String] = []
        let group = RadioButtonGroup(selection: .constant("")) {
            for name in names {
                RadioButtonItem(name, name)
            }
        }
        #expect(values(group).isEmpty)
    }

    @Test("Plain items, an if, an if/else and a for loop mix in written order")
    func mixed() {
        let extras = [3, 4]
        let group = RadioButtonGroup(selection: .constant(1)) {
            RadioButtonItem(1, "One")
            if extras.isEmpty {
                RadioButtonItem(9, "Never")
            }
            for extra in extras {
                RadioButtonItem(extra, "Extra \(extra)")
            }
            if extras.count > 1 {
                RadioButtonItem(5, "Five")
            } else {
                RadioButtonItem(6, "Six")
            }
            RadioButtonItem(2, "Two")
        }
        #expect(values(group) == [1, 3, 4, 5, 2])
    }

    @Test("Items a loop makes draw and select like written ones")
    func loopItemsRender() {
        let names = ["Alpha", "Bravo"]
        let group = RadioButtonGroup(selection: .constant("Bravo")) {
            for name in names {
                RadioButtonItem(name, name)
            }
        }
        let drawn = rows(group)
        #expect(drawn.count == 2)
        #expect(drawn.first?.hasSuffix("Alpha") == true)
        #expect(drawn.last == "\(TerminalSymbols.radioSelected) Bravo")
    }

    // MARK: - The documentation's examples, verbatim

    private enum Choice: Hashable { case option1, option2, option3 }

    @Test("The builder's overview example compiles as written")
    func overviewExample() {
        @State var choice = Choice.option1
        // Verbatim from RadioButtonGroupBuilder's "Overview".
        let group = RadioButtonGroup(selection: $choice) {
            RadioButtonItem(.option1, "First Option")
            RadioButtonItem(.option2, "Second Option")
            RadioButtonItem(.option3, "Third Option")
        }
        #expect(values(group) == [.option1, .option2, .option3])
    }

    @Test("The builder's control-flow example compiles as written")
    func controlFlowExample() {
        @State var format = "plain"
        let showsRichText = false
        let recentFormat: String? = "markdown"
        let customFormats = ["csv", "tsv"]
        // Verbatim from RadioButtonGroupBuilder's "Supported Control Flow".
        let group = RadioButtonGroup(selection: $format) {
            RadioButtonItem("plain", "Plain text")
            if showsRichText {
                RadioButtonItem("rich", "Rich text")
            } else {
                RadioButtonItem("html", "Web page")
            }
            if let recent = recentFormat {
                RadioButtonItem(recent, "Last used")
            }
            for name in customFormats {
                RadioButtonItem(name, name)
            }
        }
        #expect(values(group) == ["plain", "html", "markdown", "csv", "tsv"])
    }
}
