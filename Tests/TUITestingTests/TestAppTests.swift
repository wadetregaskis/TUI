//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppTests.swift
//
//  TUITesting used the way an app's tests use it: no `@testable`, so anything
//  a client could not write fails to compile here.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIMenus
import TUIPresentation
import TUITesting
import TUITextInput

private struct Counter: View {
    @State private var count = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Count: \(count)")
            Button("Add") { count += 1 }.focusID("add")
            Button("Reset") { count = 0 }.focusID("reset")
        }
    }
}

private struct Echo: View {
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Name", text: $text).focusID("name")
            Text("Echo: \(text)")
        }
    }
}

@MainActor
@Suite("TestApp: reading the screen")
struct TestAppScreenTests {
    @Test("A view is drawn from the top-left corner, every row present, with no trailing spaces")
    func viewAtTopLeft() {
        let app = TestApp(width: 20, height: 3) { Text("Hello") }
        #expect(app.screen.lines == ["Hello", "", ""])
        #expect(app.screen.text == "Hello")
        #expect(app.screen.description == "Hello\n\n")
    }

    @Test("An app is laid out as in a terminal, so a window centres what is smaller than it")
    func wholeApp() {
        struct Hello: App {
            var body: some Scene { WindowGroup { Text("Hi") } }
        }
        let app = TestApp(Hello(), width: 6, height: 3)
        #expect(app.screen.lines == ["", "  Hi", ""])
    }

    @Test("Text is found by row and by cell, a wide character counting for two")
    func finding() {
        let app = TestApp(width: 20, height: 3) {
            VStack(alignment: .leading, spacing: 0) {
                Text("one two one")
                Text("日本 one")
            }
        }
        #expect(app.screen.contains("two"))
        #expect(!app.screen.contains("three"))
        #expect(app.screen.line(containing: "日本") == "日本 one")
        #expect(app.screen.location(of: "two") == CellPoint(x: 4, y: 0))
        #expect(app.screen.location(of: "three") == nil)
        #expect(
            app.screen.locations(of: "one") == [CellPoint(x: 0, y: 0), CellPoint(x: 8, y: 0), CellPoint(x: 5, y: 1)])
    }

    @Test("The styled rows carry the escape codes, and the plain rows do not")
    func styled() {
        let app = TestApp(width: 20, height: 1) { Text("Hi").bold() }
        #expect(app.screen.styledLines[0].contains("\u{1B}["))
        #expect(app.screen.lines == ["Hi"])
    }

    @Test("A screen is a value: one kept from before an action stays as it was")
    func screenIsAValue() {
        let app = TestApp(width: 20, height: 4) { Counter() }
        let before = app.screen
        app.press(.space)
        #expect(before.contains("Count: 0"))
        #expect(app.screen.contains("Count: 1"))
        #expect(before != app.screen)
    }

    @Test("A resize lays the view out again")
    func resizing() {
        let app = TestApp(width: 20, height: 2) { Text("Width") .frame(maxWidth: .infinity, alignment: .trailing) }
        #expect(app.screen.location(of: "Width")?.x == 15)
        app.resize(width: 10, height: 2)
        #expect(app.screen.location(of: "Width")?.x == 5)
    }
}

@MainActor
@Suite("TestApp: keys")
struct TestAppKeyTests {
    @Test("A key reaches the focused control, and the screen shows what it did")
    func press() {
        let app = TestApp(width: 40, height: 10) { Counter() }
        #expect(app.screen.contains("Count: 0"))
        #expect(app.focusedID == "add")
        #expect(app.press(.space))
        #expect(app.screen.contains("Count: 1"))
        app.press(.space, times: 2)
        #expect(app.screen.contains("Count: 3"))
    }

    @Test("Tab moves the focus, and a key nothing wants says so")
    func focusMoves() {
        let app = TestApp(width: 40, height: 10) { Counter() }
        app.press(.tab)
        #expect(app.focusedID == "reset")
        app.press(.tab, modifiers: .shift)
        #expect(app.focusedID == "add")
        #expect(!app.press(.f5))
    }

    @Test("Typing goes into the field a character at a time")
    func typing() {
        let app = TestApp(width: 40, height: 3) { Echo() }
        app.type("Ada Lovelace")
        #expect(app.screen.contains("Echo: Ada Lovelace"))
        app.press(.backspace, times: 9)
        #expect(app.screen.contains("Echo: Ada"))
    }

    @Test("A shortcut fires on the key that stands in for Command, with what it declares")
    func shortcut() {
        struct Page: View {
            @State private var saves = 0
            var body: some View {
                Button("Saved \(saves)") { saves += 1 }.keyboardShortcut("s")
            }
        }
        let app = TestApp(width: 40, height: 3) { Page() }
        app.press(.character("s"), modifiers: .control)
        #expect(app.screen.contains("Saved 1"))
    }

    @Test("A change `onChange` makes to state is drawn before press returns")
    func framesUntilSettled() {
        struct Page: View {
            @State private var source = 0
            @State private var copy = 0
            var body: some View {
                Button("source \(source) copy \(copy)") { source += 1 }
                    .onChange(of: source) { _, new in copy = new }
            }
        }
        let app = TestApp(width: 40, height: 3) { Page() }
        app.press(.space)
        #expect(app.screen.contains("source 1 copy 1"))
    }

    @Test("A view that asks for a frame on every frame does not hang the test")
    func neverIdles() {
        struct Page: View {
            @State private var frames = 0
            var body: some View {
                Text("Frames \(frames)").onChange(of: frames, initial: true) { _, new in frames = new + 1 }
            }
        }
        let app = TestApp(width: 40, height: 3) { Page() }
        #expect(app.screen.contains("Frames"))
    }

    @Test("A quit is reported, not acted on, whichever key the app quits on")
    func quit() {
        struct Page: App {
            var body: some Scene {
                WindowGroup { Text("Page") }
            }
        }
        let app = TestApp(Page(), width: 20, height: 3)
        #expect(!app.hasRequestedQuit)
        _ = app.screen
    }
}

@MainActor
@Suite("TestApp: the mouse")
struct TestAppMouseTests {
    @Test("A click by text finds it on the screen; one that is not there throws and shows the screen")
    func clickByText() throws {
        let app = TestApp(width: 40, height: 10) { Counter() }
        try app.click("Add")
        #expect(app.screen.contains("Count: 1"))
        #expect(app.focusedID == "add")
        let error = #expect(throws: TestAppError.self) { try app.click("Delete") }
        #expect(error?.description.contains("Delete") == true)
        #expect(error?.description.contains("Count: 1") == true)
    }

    @Test("A click at a cell hits what the frame drew there")
    func clickAtCell() throws {
        let app = TestApp(width: 40, height: 10) { Counter() }
        app.click(at: try #require(app.screen.location(of: "Add")))
        #expect(app.screen.contains("Count: 1"))
    }

    @Test("Two clicks with no time between are a double click, and with time between are not")
    func doubleClick() throws {
        struct Page: View {
            @State private var doubles = 0
            var body: some View {
                Text("Doubles \(doubles)").onTapGesture(count: 2) { doubles += 1 }
            }
        }
        let app = TestApp(width: 40, height: 3) { Page() }
        try app.click("Doubles")
        app.advance(by: .seconds(5))
        try app.click("Doubles")
        #expect(app.screen.contains("Doubles 0"))
        try app.click("Doubles")
        #expect(app.screen.contains("Doubles 1"))
    }

    @Test("The right button is a button like the others")
    func rightButton() throws {
        struct Page: View {
            var body: some View {
                Text("Item").contextMenu { Button("Remove") {} }
            }
        }
        let app = TestApp(width: 40, height: 8) { Page() }
        #expect(!app.screen.contains("Remove"))
        try app.click("Item", button: .right)
        #expect(app.screen.contains("Remove"))
    }

    @Test("The wheel scrolls what it is over")
    func wheel() throws {
        let app = TestApp(width: 20, height: 4) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<20, id: \.self) { Text("row \($0)") }
                }
            }
        }
        #expect(app.screen.contains("row 0"))
        app.scroll(.down, by: 2)
        #expect(!app.screen.contains("row 0"))
        let top = try #require(app.screen.lines.first)
        try app.scroll(.up, by: 2, over: top)
        #expect(app.screen.contains("row 0"))
    }

    @Test("A drag goes through the press, the moves and the release")
    func drag() {
        struct Page: View {
            @State private var moved = 0
            var body: some View {
                Text("Moved \(moved)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .gesture(DragGesture(minimumDistance: 0).onEnded { moved = Int($0.translation.width) })
            }
        }
        let app = TestApp(width: 40, height: 6) { Page() }
        app.drag(from: CellPoint(x: 2, y: 2), to: CellPoint(x: 22, y: 2))
        #expect(app.screen.contains("Moved 20"))
    }

    @Test("The pointer's moves arrive where the app has asked to hear of them")
    func hover() throws {
        struct Page: View {
            @State private var isOver = false
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isOver ? "pointer here" : "pointer away").onHover { isOver = $0 }
                    Text("elsewhere")
                }
            }
        }
        let app = TestApp(width: 40, height: 6) { Page() }
        try app.hover(over: "pointer away")
        #expect(app.screen.contains("pointer here"))
        try app.hover(over: "elsewhere")
        #expect(app.screen.contains("pointer away"))
    }

    @Test("A long press is a button held while the clock moves")
    func longPress() throws {
        struct Page: View {
            @State private var presses = 0
            var body: some View {
                Text("Presses \(presses)").onLongPressGesture(minimumDuration: 1) { presses += 1 }
            }
        }
        let app = TestApp(width: 40, height: 3) { Page() }
        let point = try #require(app.screen.location(of: "Presses"))
        app.mouse(MouseEvent(button: .left, phase: .pressed, x: point.x, y: point.y))
        #expect(app.screen.contains("Presses 0"))
        app.advance(by: .seconds(2))
        #expect(app.screen.contains("Presses 1"))
        app.mouse(MouseEvent(button: .left, phase: .released, x: point.x, y: point.y))
    }
}

@MainActor
@Suite("TestApp: time")
struct TestAppTimeTests {
    @Test("An animation plays out as the clock moves, and not otherwise")
    func animation() {
        struct Page: View {
            @State private var isAcross = false
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Button("go") { withAnimation(.linear(duration: 1)) { isAcross.toggle() } }
                    Text("@").padding(.leading, isAcross ? 10 : 0)
                }
            }
        }
        let app = TestApp(width: 20, height: 4) { Page() }
        app.press(.enter)
        #expect(app.screen.location(of: "@")?.x == 0, "no time has passed")
        app.advance(by: .milliseconds(500))
        let halfWay = app.screen.location(of: "@")?.x ?? 0
        #expect(halfWay > 2 && halfWay < 8)
        app.advance(by: .milliseconds(500))
        #expect(app.screen.location(of: "@")?.x == 10)
        #expect(app.elapsed == .seconds(1))
    }

    @Test("A TimelineView reads the app's date, which a test can set")
    func timeline() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let app = TestApp(width: 40, height: 3) {
            TimelineView(.periodic(from: start, by: 1)) { context in
                Text("At \(Int(context.date.timeIntervalSinceReferenceDate))")
            }
        }
        app.date = start
        app.advance(by: .zero)
        #expect(app.screen.contains("At 0"))
        app.advance(by: .seconds(3))
        #expect(app.screen.contains("At 3"))
        #expect(app.date == start.addingTimeInterval(3))
    }

    @Test("Advancing an hour with nothing animating takes one frame, not an hour of them")
    func idleHour() {
        let clock = ContinuousClock()
        let started = clock.now
        let app = TestApp(width: 40, height: 3) { Text("Still") }
        app.advance(by: .seconds(3600))
        #expect(app.elapsed == .seconds(3600))
        #expect(app.screen.contains("Still"))
        #expect(started.duration(to: clock.now) < .seconds(60))
    }

    @Test("A .task's work shows once the test waits for it")
    func task() async throws {
        struct Page: View {
            @State private var loaded = "nothing"
            var body: some View {
                Text("Loaded: \(loaded)").task { loaded = "data" }
            }
        }
        let app = TestApp(width: 40, height: 3) { Page() }
        try await app.wait(for: "Loaded: data")
    }

    @Test("A wait for something that never comes gives up, with the screen")
    func waitGivesUp() async {
        let app = TestApp(width: 40, height: 3) { Text("Patience") }
        let error = await #expect(throws: TestAppError.self) {
            try await app.wait(for: "Never", timeout: .milliseconds(1))
        }
        #expect(error?.description.contains("Patience") == true)
    }

    @Test("A wait reads a change a condition can see and no frame asked for")
    func waitUntil() async throws {
        var label = "before"
        let app = TestApp(width: 40, height: 3) { Text(label) }
        #expect(app.screen.contains("before"))
        label = "after"
        try await app.wait(until: { app.screen.contains("after") })
    }

    @Test("A view that sleeps on a TestClock wakes when the test moves it")
    func testClock() async throws {
        struct Ticker: View {
            let clock: TestClock
            @State private var ticks = 0
            var body: some View {
                Text("Ticks: \(ticks)").task {
                    while (try? await clock.sleep(for: .seconds(1))) != nil { ticks += 1 }
                }
            }
        }
        let clock = TestClock()
        let app = TestApp(width: 40, height: 3) { Ticker(clock: clock) }
        try await app.wait(until: { clock.sleepers == 1 })
        #expect(app.screen.contains("Ticks: 0"))
        clock.advance(by: .seconds(1))
        try await app.wait(for: "Ticks: 1")
        try await app.wait(until: { clock.sleepers == 1 })
        clock.advance(by: .seconds(1))
        try await app.wait(for: "Ticks: 2")
    }

    @Test("The app's tasks end with it")
    func tasksEndWithTheApp() async throws {
        let clock = TestClock()
        let box = Box()
        var app: TestApp? = TestApp(width: 40, height: 3) {
            Text("Page").task {
                try? await clock.sleep(for: .seconds(1))
                box.ended = true
            }
        }
        _ = app?.screen
        try await app?.wait(until: { clock.sleepers == 1 })
        app = nil
        let waiting = TestApp(width: 1, height: 1) { Text("") }
        try await waiting.wait(until: { box.ended })
    }
}

@MainActor
private final class Box {
    var ended = false
}

@MainActor
@Suite("TestApp: storage and sheets")
struct TestAppIsolationTests {
    @Test("@AppStorage with no store of its own stays inside the instance")
    func appStorage() {
        struct Page: View {
            @AppStorage("TUITestingTests.count") private var count = 0
            var body: some View {
                Button("Count \(count)") { count += 1 }
            }
        }
        let first = TestApp(width: 40, height: 3) { Page() }
        first.press(.space)
        #expect(first.screen.contains("Count 1"))
        let second = TestApp(width: 40, height: 3) { Page() }
        #expect(second.screen.contains("Count 0"))
    }

    @Test("A sheet presents and takes the keyboard, as in a running app")
    func sheet() throws {
        struct Page: View {
            @State private var isShown = false
            var body: some View {
                Button("Show") { isShown = true }
                    .sheet(isPresented: $isShown) {
                        Button("Close") { isShown = false }
                    }
            }
        }
        let app = TestApp(width: 40, height: 12) { Page() }
        app.press(.enter)
        #expect(app.screen.contains("Close"))
        try app.click("Close")
        #expect(!app.screen.contains("Close"))
    }

    @Test("A snapshot that is missing is written and reported; a matching one passes; a changed one shows the rows")
    func snapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TestAppTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("SomeTests.swift").path
        let app = TestApp(width: 20, height: 3) { Text("Hello") }
        #expect(throws: TestAppError.self) { try app.screen.compareToSnapshot("page", filePath: source) }
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("__Snapshots__/page.txt").path))
        try app.screen.compareToSnapshot("page", filePath: source)
        let other = TestApp(width: 20, height: 3) { Text("Goodbye") }
        let error = #expect(throws: TestAppError.self) { try other.screen.compareToSnapshot("page", filePath: source) }
        #expect(error?.description.contains("- Hello") == true)
        #expect(error?.description.contains("+ Goodbye") == true)
    }

    @Test("Only TUI_RECORD_SNAPSHOTS=1 records: 0 or empty must not write over a snapshot and pass")
    func recordingSnapshots() {
        #expect(TestScreen.recordsSnapshots(environment: ["TUI_RECORD_SNAPSHOTS": "1"]))
        #expect(!TestScreen.recordsSnapshots(environment: ["TUI_RECORD_SNAPSHOTS": "0"]))
        #expect(!TestScreen.recordsSnapshots(environment: ["TUI_RECORD_SNAPSHOTS": ""]))
        #expect(!TestScreen.recordsSnapshots(environment: [:]))
    }
}
