//  🖥️ TUI — A Terminal UI framework for Swift
//  LiveTitleTests.swift
//
//  A title key with a live value — `\(timerInterval:)`, `\(date, style:)` — in
//  the controls that keep it live, as SwiftUI's do (measured on macOS 15.8,
//  lane TEXTFMT): a button's and a colour picker's title, a field's
//  placeholder, a table column's header, and the controls that build their
//  label as a `Text` of the key. Each draws the frame's reading and asks for a
//  wake at the next change (owner ruling B51-LIVE).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Live titles")
struct LiveTitleTests {
    /// 2026-05-09 06:13:20 UTC.
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private struct Row: Identifiable {
        let id: Int
        let name: String
    }

    /// A timer counting up from `base`, read as `m:ss`.
    private var interval: ClosedRange<Date> { base...base.addingTimeInterval(3_600) }

    /// One frame of `view` at `date` on a fresh context, fenced as the loop
    /// fences it: the lines drawn, and how many wakes the frame asked for.
    private func frame(_ view: some View, at date: Date, width: Int = 60) -> (lines: [String], wakes: Int) {
        let tui = TUIContext()
        let scheduler = AnimationScheduler()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        environment.animationScheduler = scheduler
        environment.frameNowNanos = 0
        environment.locale = Locale(identifier: "en_US")
        let context = RenderContext(
            availableWidth: width, availableHeight: 8, environment: environment, tuiContext: tui)
        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.renderCache.frameDate = date
        context.environment.focusManager?.beginRenderPass()
        scheduler.beginFrame()
        let buffer = renderToBuffer(view, context: context)
        scheduler.endFrame()
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return (buffer.lines.map(\.stripped), scheduler.liveWakeCount)
    }

    /// Whether `view` draws `0:05` five seconds in and `1:05` a minute later,
    /// asking for a wake each time.
    private func expectLive(_ view: some View, sourceLocation: SourceLocation = #_sourceLocation) {
        let early = frame(view, at: base.addingTimeInterval(5.5))
        let later = frame(view, at: base.addingTimeInterval(65.5))
        #expect(early.lines.joined().contains("0:05"), "\(early.lines)", sourceLocation: sourceLocation)
        #expect(later.lines.joined().contains("1:05"), "\(later.lines)", sourceLocation: sourceLocation)
        #expect(early.wakes >= 1, sourceLocation: sourceLocation)
    }

    @Test("A button's title key with a live value is drawn at the frame's date")
    func button() {
        expectLive(Button("Elapsed \(timerInterval: interval, countsDown: false)") {})
    }

    @Test("A colour picker's title key with a live value is drawn at the frame's date")
    func colorPicker() {
        expectLive(ColorPicker("Elapsed \(timerInterval: interval, countsDown: false)", selection: .constant(.red)))
    }

    @Test("A toggle's, a label's and a section's title keys stay live, built as a Text of the key")
    func textLabelledControls() {
        expectLive(Toggle("Elapsed \(timerInterval: interval, countsDown: false)", isOn: .constant(true)))
        expectLive(Label("Elapsed \(timerInterval: interval, countsDown: false)", systemImage: "star"))
        expectLive(Section("Elapsed \(timerInterval: interval, countsDown: false)") { Text("row") })
    }

    @Test("A field's title, drawn as its placeholder, stays live: text and secure fields")
    func fieldPlaceholders() {
        expectLive(TextField("Elapsed \(timerInterval: interval, countsDown: false)", text: .constant("")))
        expectLive(SecureField("Elapsed \(timerInterval: interval, countsDown: false)", text: .constant("")))
        expectLive(TextField("Elapsed \(timerInterval: interval, countsDown: false)", text: .constant(""), axis: .vertical))
    }

    @Test("A value field's title key is its Text, live, as a text field's is")
    func valueFieldTitle() {
        let field = TextField("Elapsed \(timerInterval: interval, countsDown: false)", value: .constant(3), format: .number)
        #expect(Mirror(reflecting: field).children.contains { ($0.value as? Text)?.isLive == true })
    }

    @Test("A field's prompt that reads the clock stays live")
    func fieldPrompt() {
        expectLive(
            TextField("Name", text: .constant(""), prompt: Text(timerInterval: interval, countsDown: false)))
    }

    @Test("A table column's header key or Text with a live value is drawn at the frame's date")
    func tableHeader() {
        let rows = [Row(id: 1, name: "a")]
        expectLive(Table(rows) { TableColumn("Elapsed \(timerInterval: interval, countsDown: false)", value: \.name) })
        expectLive(Table(rows) { TableColumn(Text(timerInterval: interval, countsDown: false), value: \.name) })
        expectLive(
            Table(rows) {
                TableColumn("Elapsed \(timerInterval: interval, countsDown: false)", value: \.name).width(.fit)
            })
    }

    @Test("A title with nothing live asks for no wake")
    func plainTitlesAreIdle() {
        let rows = [Row(id: 1, name: "a")]
        #expect(frame(Button("Save") {}, at: base).wakes == 0)
        #expect(frame(TextField("Name", text: .constant("")), at: base).wakes == 0)
        #expect(frame(Table(rows) { TableColumn("Name", value: \.name) }, at: base).wakes == 0)
    }
}
