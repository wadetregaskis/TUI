//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuPopupServedRowsTests.swift
//
//  An open pop-up menu whose rows are served from the row memo draws, frame
//  for frame, what the same menu draws with the render cache emptied before
//  every frame (H-92b): through a walk of Downs and Ups, the page keys, Home
//  and End, type select, a submenu opened and closed, disabled rows, dividers,
//  a section, a toggle, the key-equivalent column, the pointer, and rows
//  inserted above and removed while it is open, which move every ordinal below
//  them. Each step's styled screen is compared, so a highlight served on the
//  wrong row, or a row's colours from the frame before, shows as a difference.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIMenus
import TUITesting
@testable import TUITestSupport

@Observable
@MainActor
private final class Model {
    var ids: [Int] = Array(0..<60)
    var showsHidden = false
    var log: [String] = []
}

private struct WalkMenuApp: App {
    let model: Model

    init() { model = Model() }

    init(model: Model) { self.model = model }

    var body: some Scene {
        WindowGroup {
            let model = model
            VStack(alignment: .leading, spacing: 0) {
                Menu("File") {
                    Button("New") { model.log.append("New") }.keyboardShortcut("n")
                    Button("Open") {}.disabled(true)
                    Divider()
                    Toggle("Show Hidden", isOn: Bindable(model).showsHidden)
                    Menu("Recent") {
                        ForEach(0..<12, id: \.self) { index in Button("Recent \(index)") {} }
                    }
                    Section("Items") {
                        ForEach(model.ids, id: \.self) { id in
                            Button("Item \(id)") { model.log.append("Item \(id)") }
                                .disabled(id % 7 == 3)
                        }
                    }
                    Divider()
                    Button("Quit") {}.keyboardShortcut("q")
                }
                Text(verbatim: "log \(model.log.joined(separator: ","))")
            }
        }
    }
}

@MainActor
@Suite("An open menu's served rows draw what a cold frame draws")
struct MenuPopupServedRowsTests {
    @MainActor
    private final class Pair {
        let warm: TestApp
        let cold: TestApp
        let warmModel = Model()
        let coldModel = Model()
        private var now: Int64 = 0
        private(set) var steps = 0
        private(set) var distinctScreens = Set<[String]>()

        init() {
            warm = TestApp(WalkMenuApp(model: warmModel), width: 60, height: 20)
            cold = TestApp(WalkMenuApp(model: coldModel), width: 60, height: 20)
            cold.clearsRenderCacheEachFrame = true
            frame("start")
            frame("start")
        }

        func frame(_ label: String) {
            now += 16_666_667
            warm.frame(atNanos: now)
            cold.frame(atNanos: now)
            steps += 1
            let warmScreen = warm.screen.styledLines
            let coldScreen = cold.screen.styledLines
            distinctScreens.insert(warmScreen)
            #expect(
                warmScreen == coldScreen,
                "after \(label) (step \(steps)):\nwarm:\n\(warm.screen.text)\ncold:\n\(cold.screen.text)")
        }

        func key(_ key: Key, _ times: Int = 1) {
            for _ in 0..<times {
                warm.send(KeyEvent(key: key))
                cold.send(KeyEvent(key: key))
                frame("\(key)")
            }
        }

        func type(_ text: String) {
            for character in text { key(.character(character)) }
        }

        func hover(over text: String) throws {
            try warm.hover(over: text)
            try cold.hover(over: text)
            frame("hover over \(text)")
        }

        func change(_ label: String, _ edit: (Model) -> Void) {
            edit(warmModel)
            edit(coldModel)
            frame(label)
        }
    }

    @Test("A walk through an open menu draws every frame as a cold frame does")
    func walkMatchesColdFrames() throws {
        let pair = Pair()
        pair.key(.space)
        #expect(pair.warm.screen.contains("Item 0"), "\(pair.warm.screen.text)")
        pair.key(.down, 4)
        pair.key(.up)
        pair.key(.pageDown, 2)
        pair.key(.up, 2)
        pair.key(.end)
        pair.key(.pageUp)
        pair.key(.home)
        pair.key(.down, 3)
        pair.type("It")
        pair.type("R")
        pair.key(.right)
        pair.key(.down, 2)
        pair.key(.left)
        pair.key(.down)
        pair.change("rows inserted above") { $0.ids.insert(contentsOf: [-2, -1], at: 0) }
        pair.key(.down, 2)
        pair.change("a row removed above") { $0.ids.removeFirst() }
        pair.key(.up)
        try pair.hover(over: "Item 5")
        try pair.hover(over: "Recent")
        try pair.hover(over: "Item 2")
        pair.key(.down)
        pair.key(.escape)
        pair.key(.space)
        pair.key(.down, 3)
        pair.key(.space)
        #expect(pair.distinctScreens.count > 20, "the walk drew \(pair.distinctScreens.count) distinct screens")
        #expect(pair.warmModel.log == pair.coldModel.log)
        #expect(!pair.warmModel.log.isEmpty, "the walk chose nothing")
    }
}
