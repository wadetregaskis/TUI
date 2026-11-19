//  🖥️ TUI — A Terminal UI framework for Swift
//  LazyStackEdgeArrivalFrameTests.swift
//
//  Every frame written across one Tab into a lazy stack whose rows on screen
//  have nothing to focus (LAZY-EDGE, deviation L7). Last frame's ring sends
//  the key to an interim control — the scroll view's stop, or the control past
//  the stack — and the frame answering the key walks the stack in from that
//  edge and takes the focus on to the row it finds. That has to happen before
//  the frame is written: once it was taken on at the end of the pass, one frame
//  showed the focus on the interim control, `.onChange(of:)` of a
//  `@FocusState` saw it pass through there, and a `@FocusedValue` read it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITesting

private enum Field: Hashable { case top, head, row, bottom }

private struct ArrivalMarkerKey: FocusedValueKey { typealias Value = String }

extension FocusedValues {
    fileprivate var arrivalMarker: String? {
        get { self[ArrivalMarkerKey.self] }
        set { self[ArrivalMarkerKey.self] = newValue }
    }
}

/// What the page's views did.
@MainActor
private final class ArrivalLog {
    /// `.onChange(of:)` of the page's `@FocusState`, by the new value.
    var focusChanges: [String] = []
    /// `.onChange(of:)` of the page's `@FocusedValue`, by the new value.
    var markerChanges: [String] = []
    /// The rows whose `onAppear` ran.
    var appeared: [Int] = []
    /// The top text field's `onEditingChanged`.
    var editing: [Bool] = []
    /// The buttons pressed, by title.
    var pressed: [String] = []

    func reset() {
        focusChanges = []
        markerChanges = []
        appeared = []
        editing = []
        pressed = []
    }
}

private func spelled(_ field: Field?) -> String { field.map { "\($0)" } ?? "nil" }

@MainActor
@Suite("Tab into a lazy stack: no frame shows the interim focus", .serialized)
struct LazyStackEdgeArrivalFrameTests {
    private struct Row: View {
        let index: Int
        let firstButton: Int
        let log: ArrivalLog
        let focus: FocusState<Field?>.Binding
        var body: some View {
            Group {
                if index == firstButton {
                    Button("b\(index)") { log.pressed.append("b\(index)") }
                        .focusID("b\(index)").focused(focus, equals: .row)
                        .focusedValue(\.arrivalMarker, "row")
                } else {
                    Text("x\(index)")
                }
            }
            .onAppear { log.appeared.append(index) }
        }
    }

    private struct Page: View {
        let log: ArrivalLog
        var headerButton = false
        var firstButton = 300
        /// A text field above the scroll view instead of the `top` button.
        var topField = false
        @State private var text = ""
        @FocusState private var focus: Field?
        @FocusedValue(\.arrivalMarker) private var marker

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("f=\(spelled(focus)) v=\(marker ?? "-")")
                top
                scroll
                Button("bottom") {}.focusID("bottom").focused($focus, equals: .bottom)
                    .focusedValue(\.arrivalMarker, "bottom")
            }
            .onChange(of: focus) { _, new in log.focusChanges.append(spelled(new)) }
            .onChange(of: marker) { _, new in log.markerChanges.append(new ?? "-") }
        }

        /// The control above the scroll view: a button, or a text field.
        private var top: some View {
            Group {
                if topField {
                    TextField("top", text: $text).onEditingChanged { log.editing.append($0) }
                        .focusID("top")
                } else {
                    Button("top") { log.pressed.append("top") }.focusID("top")
                }
            }
            .focused($focus, equals: .top).focusedValue(\.arrivalMarker, "top")
        }

        /// The scroll view: the lazy stack of 400 rows, under a header's
        /// button where asked.
        private var scroll: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if headerButton {
                        Button("head") {}.focusID("head").focused($focus, equals: .head)
                            .focusedValue(\.arrivalMarker, "head")
                    }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<400, id: \.self) {
                            Row(index: $0, firstButton: firstButton, log: log, focus: $focus)
                        }
                    }
                }
            }
            .frame(height: 6)
        }
    }

    /// One frame written: its bytes, and its rows as plain text.
    private struct Written {
        let bytes: Int
        let lines: [String]
    }

    /// A page's app, the log of what its views did, and the frame clock.
    @MainActor
    private final class Driver {
        let app: TestApp
        let log: ArrivalLog
        private var nanos: Int64 = 0

        init(headerButton: Bool = false, firstButton: Int = 300, topField: Bool = false) {
            let log = ArrivalLog()
            self.log = log
            app = TestApp(width: 30, height: 12) {
                Page(log: log, headerButton: headerButton, firstButton: firstButton, topField: topField)
            }
        }

        /// Sends `events` with no frame between them, then draws one frame at
        /// a time while the app asks for one: the frames written.
        @discardableResult
        func send(_ events: KeyEvent...) -> [Written] {
            for event in events { _ = app.send(event) }
            return drawFrames()
        }

        @discardableResult
        func drawFrames() -> [Written] {
            var written: [Written] = []
            for _ in 0..<8 {
                let asked = app.framesAsked
                _ = app.takeFrameRequest()
                let before = app.bytesWritten
                nanos += 16_666_667
                app.frame(atNanos: nanos)
                written.append(Written(
                    bytes: app.bytesWritten - before, lines: TestScreen(styledLines: app.headless.screen).lines))
                if !app.takeFrameRequest(), app.framesAsked == asked { break }
            }
            return written.filter { $0.bytes > 0 }
        }

        var focusedID: String? { app.headless.focusedID }
    }

    /// The key's frames: one, showing the row the walk found focused, as
    /// `@FocusState` and `@FocusedValue` say it; and what the views saw
    /// change, only that.
    private func expectArrival(
        _ written: [Written], at button: String, _ driver: Driver, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(driver.focusedID == button, sourceLocation: sourceLocation)
        #expect(written.count == 1, "frames written: \(written.map(\.lines))", sourceLocation: sourceLocation)
        for frame in written {
            #expect(frame.lines.first?.hasPrefix("f=row v=row") == true, "\(frame.lines)", sourceLocation: sourceLocation)
            #expect(frame.lines.contains { $0.contains(button) }, "\(frame.lines)", sourceLocation: sourceLocation)
        }
        #expect(driver.log.focusChanges == ["row"], sourceLocation: sourceLocation)
        #expect(driver.log.markerChanges == ["row"], sourceLocation: sourceLocation)
    }

    @Test("Tab from a button above, over 300 rows of text")
    func tabFromAbove() {
        let driver = Driver()
        driver.drawFrames()
        for _ in 0..<3 { driver.drawFrames() }
        #expect(driver.focusedID == "top")
        driver.log.reset()
        let written = driver.send(KeyEvent(key: .tab))
        expectArrival(written, at: "b300", driver)
        // No row the walk only looked at, nor any row of the interim frame,
        // appeared: only the rows drawn round the button.
        #expect(driver.log.appeared.allSatisfy { (290...305).contains($0) }, "\(driver.log.appeared)")
    }

    @Test("Tab over 300 rows of text as the first key after launch")
    func tabAsFirstKey() {
        let driver = Driver()
        driver.drawFrames()
        driver.log.reset()
        let written = driver.send(KeyEvent(key: .tab))
        expectArrival(written, at: "b300", driver)
    }

    @Test("Tab from a header's button over 300 rows of text (449deb443)")
    func tabFromHeaderButton() {
        let driver = Driver(headerButton: true)
        driver.drawFrames()
        for _ in 0..<3 { driver.drawFrames() }
        driver.send(KeyEvent(key: .tab))
        #expect(driver.focusedID == "head")
        driver.log.reset()
        let written = driver.send(KeyEvent(key: .tab))
        expectArrival(written, at: "b300", driver)
    }

    @Test("Shift-Tab from the scroll view's stop to a button 100 rows up")
    func shiftTabFromScrollStop() {
        let driver = Driver(firstButton: 100)
        driver.drawFrames()
        for _ in 0..<3 { driver.drawFrames() }
        // To the scroll view's stop from below: bottom, then the scroll view.
        driver.send(KeyEvent(key: .tab, shift: true))
        driver.send(KeyEvent(key: .tab, shift: true))
        #expect(driver.focusedID?.hasPrefix("scrollview-") == true)
        driver.log.reset()
        let written = driver.send(KeyEvent(key: .tab, shift: true))
        expectArrival(written, at: "b100", driver)
    }

    /// What the frame cannot hide: the key moves the focus to the interim
    /// control before any frame, so what the focus manager tells a control at
    /// once — a text field's `onEditingChanged` — fires for it, and a key read
    /// behind the Tab in the same batch goes to it. Deviation L7 names this as
    /// the limit that remains. A known issue: this fails once it is fixed.
    @Test("At the key, the interim control is told it has the focus (known limit)")
    func keyTimeInterim() {
        let driver = Driver(firstButton: 100, topField: true)
        driver.drawFrames()
        for _ in 0..<3 { driver.drawFrames() }
        driver.send(KeyEvent(key: .tab, shift: true))
        driver.send(KeyEvent(key: .tab, shift: true))
        #expect(driver.focusedID?.hasPrefix("scrollview-") == true)
        driver.log.reset()
        let written = driver.send(KeyEvent(key: .tab, shift: true))
        expectArrival(written, at: "b100", driver)
        withKnownIssue("LAZY-EDGE: the key's interim control is told before the frame finds the row") {
            #expect(driver.log.editing.isEmpty, "\(driver.log.editing)")
        }

        let batched = Driver(firstButton: 100)
        batched.drawFrames()
        for _ in 0..<3 { batched.drawFrames() }
        batched.send(KeyEvent(key: .tab, shift: true))
        batched.send(KeyEvent(key: .tab, shift: true))
        batched.log.reset()
        batched.send(KeyEvent(key: .tab, shift: true), KeyEvent(key: .enter))
        withKnownIssue("LAZY-EDGE: a key read behind the Tab in one batch goes to the interim control") {
            #expect(batched.log.pressed == ["b100"], "\(batched.log.pressed)")
        }
    }
}
