//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PopoverReturnKeyTests.swift
//
//  `onKeyPress` on a popover's content hears the keys while the focus is
//  inside it (decisions-D2C, "Found on the way": the compact date picker's
//  calendar did not hear Return, and worked it around in its own handler).
//  The popover's claim on Escape grabbed the input as an open drop-down
//  menu's does, which silences the whole focus path; its modal section is
//  what keeps the app's keys off the page behind it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

final class PopoverKeyLog: @unchecked Sendable {
    var entries: [String] = []
}

/// A button that opens a popover with a focusable view, `onKeyPress` on the
/// popover's content and on the page around the button.
struct PopoverReturnApp: App {
    static let log = PopoverKeyLog()

    var body: some Scene {
        WindowGroup {
            PopoverReturnPage()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct PopoverReturnPage: View {
    @State private var shown = false

    var body: some View {
        VStack {
            Button("open") { shown = true }
                .popover(isPresented: $shown) {
                    VStack {
                        Text("POPOVER")
                        Text("focusable").focusable()
                    }
                    .onKeyPress(.return) {
                        PopoverReturnApp.log.entries.append("return")
                        return .handled
                    }
                    .onKeyPress("x") {
                        PopoverReturnApp.log.entries.append("x")
                        return .handled
                    }
                }
        }
        .onKeyPress("y") {
            PopoverReturnApp.log.entries.append("page y")
            return .handled
        }
    }
}

@MainActor
@Suite("onKeyPress on a popover's content")
struct PopoverReturnKeyTests {
    @Test("A popover's content hears its keys with the focus inside it, and the page behind it does not")
    func popoverContentHearsItsKeys() {
        PopoverReturnApp.log.entries = []
        let app = HeadlessApp(PopoverReturnApp(), width: 40, height: 12)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        app.send(KeyEvent(key: .enter))
        frame()
        frame()
        #expect(app.screen.contains { $0.contains("POPOVER") }, "precondition: shown")
        app.send(KeyEvent(key: .tab))
        frame()
        #expect(app.focusedID?.hasPrefix("focusable-") == true, "precondition: the focus is inside the popover")
        app.send(KeyEvent(character: "x"))
        frame()
        app.send(KeyEvent(key: .enter))
        frame()
        app.send(KeyEvent(character: "y"))
        frame()
        #expect(PopoverReturnApp.log.entries == ["x", "return"], "\(PopoverReturnApp.log.entries)")
    }
}
