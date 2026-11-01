//  🖥️ TUI — A Terminal UI framework for Swift
//  NoColorAuditTests.swift
//
//  With colour off, can you still see what state a control is in?
//
//  `NO_COLOR` puts a whole app at `.noColor`, where a control's colour draws
//  nothing and only its glyphs and its text attributes are left. So this looks at
//  the real controls, in a real app, as a terminal would paint them: the glyph and
//  the attributes of every cell, and nothing else. Two states of a control that
//  paint the same cells are two states a person can't tell apart.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
import TUITesting

// MARK: - What a terminal paints

/// What a cell shows without colour: its glyph, and the attributes that can show
/// on that glyph.
private struct PaintedCell: Equatable {
    var glyph: Character
    var attributes: Set<String>
}

/// Reads a row the way a terminal would, keeping what it can show without colour.
/// Bold on a space shows nothing, so a blank cell keeps only what paints a blank.
private func paintedCells(_ row: String) -> (cells: [PaintedCell], colours: [String]) {
    var cells: [PaintedCell] = []
    var colours: [String] = []
    var attributes = Set<String>()
    var rest = Substring(row)
    while let first = rest.first {
        if first == "\u{1B}" {
            rest = rest.dropFirst()
            guard rest.first == "[" else {
                // An OSC, as a hyperlink is: up to its terminator.
                if let end = rest.range(of: "\u{1B}\\") { rest = rest[end.upperBound...] }
                continue
            }
            rest = rest.dropFirst()
            let parameters = rest.prefix { !$0.isLetter }
            rest = rest.dropFirst(parameters.count)
            guard rest.first == "m" else {
                rest = rest.dropFirst()
                continue
            }
            rest = rest.dropFirst()
            apply(String(parameters), to: &attributes, colours: &colours)
        } else {
            rest = rest.dropFirst()
            let shown = first == " " ? attributes.intersection(["reverse", "underline", "strike"]) : attributes
            cells.append(PaintedCell(glyph: first, attributes: shown))
        }
    }
    return (cells, colours)
}

// swiftlint:disable:next cyclomatic_complexity
private func apply(_ parameters: String, to attributes: inout Set<String>, colours: inout [String]) {
    var codes = parameters.split(separator: ";", omittingEmptySubsequences: false).makeIterator()
    while let raw = codes.next() {
        let code = raw.split(separator: ":").first.flatMap { Int($0) } ?? 0
        switch code {
        case 0: attributes = []
        case 1: attributes.insert("bold")
        case 2: attributes.insert("dim")
        case 3: attributes.insert("italic")
        case 4: attributes.insert("underline")
        case 5, 6: attributes.insert("blink")
        case 7: attributes.insert("reverse")
        case 9: attributes.insert("strike")
        case 21, 22: attributes.subtract(["bold", "dim"])
        case 23: attributes.remove("italic")
        case 24: attributes.remove("underline")
        case 25: attributes.remove("blink")
        case 27: attributes.remove("reverse")
        case 29: attributes.remove("strike")
        case 38, 48, 58:
            // An extended colour: `5;n` or `2;r;g;b`, unless spelled with colons.
            colours.append(parameters)
            if !raw.contains(":") {
                let form = codes.next()
                for _ in 0..<(form == "2" ? 3 : 1) { _ = codes.next() }
            }
        case 30...37, 40...47, 90...97, 100...107: colours.append(parameters)
        default: break  // 39, 49 and 59 restate the terminal's own, which adds no colour.
        }
    }
}

/// How two screens differ, as a person would see it. Empty when they paint the same.
private func differences(_ first: [String], _ second: [String]) -> Set<String> {
    var found = Set<String>()
    for (one, other) in zip(first, second) {
        let one = paintedCells(one).cells
        let other = paintedCells(other).cells
        for index in 0..<max(one.count, other.count) {
            let left = index < one.count ? one[index] : PaintedCell(glyph: " ", attributes: [])
            let right = index < other.count ? other[index] : PaintedCell(glyph: " ", attributes: [])
            if left.glyph != right.glyph { found.insert("glyph") }
            found.formUnion(left.attributes.symmetricDifference(right.attributes))
        }
    }
    return found
}

/// A row with a line under it marking the attributes of its cells, for a person.
private func annotated(_ rows: [String]) -> String {
    rows.compactMap { row -> String? in
        let cells = paintedCells(row).cells
        let text = String(cells.map(\.glyph))
        guard !text.allSatisfy({ $0 == " " }) || cells.contains(where: { !$0.attributes.isEmpty }) else { return nil }
        let marks = String(
            cells.map { cell -> Character in
                if cell.attributes.contains("reverse") { return "R" }
                if cell.attributes.contains("bold") { return "B" }
                if cell.attributes.contains("dim") { return "d" }
                if cell.attributes.contains("underline") { return "u" }
                if cell.attributes.contains("italic") { return "i" }
                if cell.attributes.contains("strike") { return "s" }
                return " "
            })
        return "    |\(text)|\n    |\(marks)|"
    }.joined(separator: "\n")
}

// MARK: - The controls

private enum Sample: Int, Hashable, CaseIterable, Sendable { case first, second, third }

private struct Row: Identifiable {
    let id: Int
    let name: String
}

private let rows = [Row(id: 0, name: "Alpha"), Row(id: 1, name: "Bravo"), Row(id: 2, name: "Charlie")]

/// Every control, by name, at a state set through `on`.
@MainActor @ViewBuilder
// swiftlint:disable:next cyclomatic_complexity
private func control(_ name: String, on: Bool = false) -> some View {
    switch name {
    case "button": Button("Save") {}
    case "button.bordered": Button("Save") {}.buttonStyle(.bordered)
    case "button.prominent": Button("Save") {}.buttonStyle(.borderedProminent)
    case "button.borderless": Button("Save") {}.buttonStyle(.borderless)
    case "button.plain": Button("Save") {}.buttonStyle(.plain)
    case "button.destructive": Button("Save") {}.buttonStyle(.destructive)
    case "button.glass": Button("Save") {}.buttonStyle(.glass)
    case "link": Link("Docs", destination: URL(string: "https://swift.org")!)
    case "toggle": Toggle("Wi-Fi", isOn: .constant(on))
    case "toggle.switch": Toggle("Wi-Fi", isOn: .constant(on)).toggleStyle(.switch)
    case "toggle.checkbox": Toggle("Wi-Fi", isOn: .constant(on)).toggleStyle(.checkbox)
    case "toggle.button": Toggle("Wi-Fi", isOn: .constant(on)).toggleStyle(.button)
    case "radio": radio(on: on)
    case "picker.segmented": picker(on: on).pickerStyle(.segmented)
    case "picker.menu": picker(on: on).pickerStyle(.menu)
    case "picker.radio": picker(on: on).pickerStyle(.radioGroup)
    case "picker.inline": picker(on: on).pickerStyle(.inline)
    case "stepper": Stepper("Count", value: .constant(on ? 7 : 3), in: 0...10)
    case "textfield": TextField("Name", text: .constant(on ? "Ada" : "")).frame(width: 20)
    case "securefield": SecureField("Secret", text: .constant(on ? "Ada" : "")).frame(width: 20)
    case "texteditor": TextEditor(text: .constant(on ? "Ada" : "Bob")).frame(width: 20, height: 3)
    case "list": list(on: on)
    case "table": table(on: on)
    case "tabs": tabs(on: on).tabViewStyle(.automatic)
    case "tabs.compact": tabs(on: on).tabViewStyle(.compact)
    case "tabs.bordered": tabs(on: on).tabViewStyle(.bordered)
    case "menu": Menu("Actions") { Button("One") {} }
    case "disclosure": DisclosureGroup("More", isExpanded: .constant(on)) { Text("Inside") }
    case "date": DatePicker("When", selection: .constant(Date(timeIntervalSince1970: on ? 0 : 86400 * 40)))
    case "colorpicker": ColorPicker("Tint", selection: .constant(on ? Color.red : Color.blue))
    case "scrollview": scrollView()
    default: slider(name, on: on)
    }
}

@MainActor private func scrollView() -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) { ForEach(0..<30) { Text("Row \($0)") } }
    }
    .frame(width: 20, height: 4)
}

@MainActor private func radio(on: Bool) -> some View {
    RadioButtonGroup(selection: .constant(on ? Sample.second : Sample.first)) {
        RadioButtonItem(Sample.first, "One")
        RadioButtonItem(Sample.second, "Two")
    }
}

@MainActor private func picker(on: Bool) -> some View {
    Picker("Pick", selection: .constant(on ? Sample.second : Sample.first)) {
        Text("One").tag(Sample.first)
        Text("Two").tag(Sample.second)
    }
}

@MainActor private func list(on: Bool) -> some View {
    List(rows, selection: .constant(on ? Set([1]) : Set<Int>())) { Text($0.name) }
        .frame(width: 30, height: 5)
}

@MainActor private func table(on: Bool) -> some View {
    Table(rows, selection: .constant(on ? Set([1]) : Set<Int>())) {
        TableColumn("Name", value: \Row.name)
    }
    .frame(width: 30, height: 6)
}

@MainActor private func tabs(on: Bool) -> some View {
    TabView(selection: .constant(on ? 1 : 0)) {
        Tab("One", value: 0) { Text("First") }
        Tab("Two", value: 1) { Text("Second") }
    }
}

private let trackStyles: [(String, TrackStyle)] = [
    ("bar", .bar), ("block", .block), ("blockFine", .blockFine), ("dot", .dot), ("knob", .knob),
    ("marker", .marker), ("shade", .shade), ("braille", .braille), ("shadeRamp", .shadeRamp()),
]

@MainActor @ViewBuilder
private func slider(_ name: String, on: Bool) -> some View {
    let value = on ? 0.75 : 0.25
    if name.hasPrefix("slider."), let style = trackStyles.first(where: { "slider.\($0.0)" == name })?.1 {
        Slider(value: .constant(value), in: 0...1).trackStyle(style).frame(width: 30)
    } else if name.hasPrefix("progress."), let style = trackStyles.first(where: { "progress.\($0.0)" == name })?.1 {
        ProgressView(value: value).trackStyle(style).frame(width: 30)
    } else if name == "gauge" {
        Gauge(value: value, in: 0...1) { Text("Fuel") }.frame(width: 30)
    }
}

// MARK: - The audit

/// Every control that takes the focus.
private let focusable =
    [
        "button", "button.bordered", "button.prominent", "button.borderless", "button.plain", "button.destructive",
        "button.glass", "link", "toggle", "toggle.switch", "toggle.checkbox", "toggle.button", "radio",
        "picker.segmented", "picker.menu", "picker.radio", "picker.inline", "stepper", "textfield", "securefield",
        "texteditor", "list", "table", "tabs", "tabs.compact", "tabs.bordered", "menu", "disclosure", "date",
        "colorpicker", "scrollview",
    ] + trackStyles.map { "slider.\($0.0)" }

/// Every control with a value to show.
private let stated =
    [
        "toggle", "toggle.switch", "toggle.checkbox", "toggle.button", "radio", "picker.segmented", "picker.menu",
        "picker.radio", "picker.inline", "stepper", "textfield", "securefield", "texteditor", "list", "table",
        "tabs", "tabs.compact", "tabs.bordered", "disclosure", "date", "gauge",
    ] + trackStyles.flatMap { ["slider.\($0.0)", "progress.\($0.0)"] }

/// The app a control is measured in for what it leaves animating.
private struct BreathHost: App {
    var name = "button"

    init() {}

    init(name: String) { self.name = name }

    var body: some Scene {
        WindowGroup { control(name) }
    }
}

/// The app an indeterminate bar is measured in.
private struct IndeterminateHost: App {
    var style = IndeterminateStyle.sweep

    init() {}

    init(style: IndeterminateStyle) { self.style = style }

    var body: some Scene {
        WindowGroup { ProgressView().indeterminateStyle(style).frame(width: 30) }
    }
}

@MainActor
@Suite("At .noColor, no state is told by colour alone")
struct NoColorAuditTests {
    /// The screen with `name` holding the focus, and with it having moved off.
    private func focusScreens(_ name: String) -> (focused: [String], unfocused: [String]) {
        let app = TestApp(width: 70, height: 14) {
            VStack(alignment: .leading, spacing: 0) {
                control(name)
                Button("ELSEWHERE") {}.focusID("elsewhere")
            }
        }
        let focused = app.screen.styledLines
        for _ in 0..<12 where app.focusedID != "elsewhere" { app.press(.tab) }
        let unfocused = app.screen.styledLines
        func without(_ lines: [String]) -> [String] { lines.filter { !$0.stripped.contains("ELSEWHERE") } }
        return (without(focused), without(unfocused))
    }

    /// The screen of `name` with the focus elsewhere.
    private func restingScreen(_ name: String, on: Bool = false, disabled: Bool = false) -> [String] {
        TestApp(width: 70, height: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Button("FIRST") {}
                control(name, on: on).disabled(disabled)
            }
        }.screen.styledLines
    }

    private func comment(_ first: [String], _ second: [String]) -> Comment {
        Comment(rawValue: "They paint the same:\n" + annotated(first) + "\n  --\n" + annotated(second))
    }

    @Test("The focus shows", arguments: focusable)
    func focusShows(name: String) {
        ColorDepth.withCurrent(.noColor) {
            let (focused, unfocused) = focusScreens(name)
            #expect(!differences(focused, unfocused).isEmpty, comment(focused, unfocused))
        }
    }

    @Test("Disabled shows", arguments: focusable)
    func disabledShows(name: String) {
        ColorDepth.withCurrent(.noColor) {
            let enabled = restingScreen(name)
            let disabled = restingScreen(name, disabled: true)
            #expect(!differences(enabled, disabled).isEmpty, comment(enabled, disabled))
        }
    }

    @Test("A control's value shows", arguments: stated)
    func valueShows(name: String) {
        ColorDepth.withCurrent(.noColor) {
            let off = restingScreen(name)
            let on = restingScreen(name, on: true)
            #expect(!differences(off, on).isEmpty, comment(off, on))
        }
    }

    @Test("No state paints a colour", arguments: focusable + stated)
    func noColourIsPainted(name: String) {
        ColorDepth.withCurrent(.noColor) {
            let rows = focusScreens(name).focused + restingScreen(name) + restingScreen(name, on: true)
            let colours = rows.flatMap { paintedCells($0).colours }
            #expect(colours.isEmpty, "\(colours)")
        }
    }

    @Test("A focused radio option isn't one more selected option")
    func radioFocusIsNotSelection() throws {
        try ColorDepth.withCurrent(.noColor) {
            let app = TestApp(width: 30, height: 4) { control("radio") }
            app.press(.down)
            #expect(app.screen.lines.filter { $0.hasPrefix(TerminalSymbols.radioSelected) } == ["● One"])
            let row = try #require(app.screen.lines.firstIndex { $0.hasSuffix("Two") })
            let cells = paintedCells(app.screen.styledLines[row]).cells
            #expect(cells.contains { $0.glyph == "T" && $0.attributes.contains("reverse") })
        }
    }

    @Test("A text field's prompt, its caret and its selection each show")
    func textFieldShowsEverything() {
        ColorDepth.withCurrent(.noColor) {
            // The prompt, against the same word typed. Neither has the focus here.
            let prompt = TestApp(width: 30, height: 3) {
                VStack(alignment: .leading, spacing: 0) {
                    Button("FIRST") {}
                    TextField("Ada", text: .constant("")).frame(width: 20)
                }
            }
            let entered = TestApp(width: 30, height: 3) {
                VStack(alignment: .leading, spacing: 0) {
                    Button("FIRST") {}
                    TextField("Bob", text: .constant("Ada")).frame(width: 20)
                }
            }
            #expect(differences(prompt.screen.styledLines, entered.screen.styledLines).contains("dim"))

            // The caret: a reversed cell.
            let typed = TestApp(width: 30, height: 3) { TextField("Bob", text: .constant("Ada")).frame(width: 20) }
            let cells = typed.screen.styledLines.flatMap { paintedCells($0).cells }
            #expect(cells.contains { $0.attributes.contains("reverse") }, "\(typed.screen)")

            // The selection: both cells of it.
            typed.press(.left, modifiers: .shift, times: 2)
            let selected = typed.screen.styledLines.flatMap { paintedCells($0).cells }.filter {
                $0.attributes.contains("reverse")
            }
            #expect(selected.map(\.glyph) == ["d", "a"], "\(typed.screen)")
        }
    }

    /// What animates without colour. A breath in a colour has nothing to show, and no
    /// reason to wake the loop. Only these change what's drawn: a caret blinks, and the
    /// cursor row of a list or a table breathes by its weight.
    @Test("A focused control leaves nothing animating that can't be seen", arguments: focusable)
    func nothingWakesTheLoop(name: String) {
        ColorDepth.withCurrent(.noColor) {
            let host = BreathHost(name: name)
            let runner = AppRunner(app: host, appState: AppState())
            let harness = RenderLoopHarness(tuiContext: runner.tuiContext)
            let loop = harness.loop(host)
            let timer = CursorTimer(renderNotifier: harness.appState)
            _ = loop.render(cursorTimer: timer)
            timer.beginFrameReadTracking()
            let activity = loop.render(cursorTimer: timer)
            #expect(!activity.usesPulse, "reads the phase, so every step redraws the page")
            #expect(!activity.usesCursor, "reads the cursor clock, so every step redraws the page")
            if !["textfield", "securefield", "texteditor", "list", "table"].contains(name) {
                let runs = loop.replayable?.runs ?? []
                #expect(runs.isEmpty, "\(runs.map(\.frames))")
            }
        }
    }

    /// An indeterminate bar says the app is working by moving. If its motion is all in
    /// its colours, it has stopped saying so.
    @Test(
        "An indeterminate bar still moves",
        arguments: [
            IndeterminateStyle.sweep, .barberPole, .pulse, .knightRider, .gradient(),
        ])
    func indeterminateMoves(style: IndeterminateStyle) throws {
        try ColorDepth.withCurrent(.noColor) {
            let harness = RenderLoopHarness()
            let loop = harness.loop(IndeterminateHost(style: style))
            let timer = CursorTimer(renderNotifier: harness.appState)
            _ = loop.render(cursorTimer: timer)
            let run = try #require(loop.replayable?.runs.first { $0.isAnimating }, "nothing moves")
            let pictures = run.frames.map(paintedCells).map(\.cells)
            #expect(pictures.contains { $0 != pictures[0] }, "\(run.frames)")
        }
    }

    /// For a person: `TUI_AUDIT_DUMP=path swift test --filter NoColorAuditTests` writes
    /// each pair of screens with its attributes marked, to read by eye.
    @Test(
        "The screens, for a person to read",
        .enabled(if: ProcessInfo.processInfo.environment["TUI_AUDIT_DUMP"] != nil))
    func dump() {
        ColorDepth.withCurrent(.noColor) {
            var report = ""
            func add(_ kind: String, _ name: String, _ first: [String], _ second: [String]) {
                let found = differences(first, second).sorted().joined(separator: ",")
                report += "\(kind) \(name): \(found.isEmpty ? "*** NONE ***" : found)\n"
                report += annotated(first) + "\n  --\n" + annotated(second) + "\n"
            }
            for name in focusable {
                let (focused, unfocused) = focusScreens(name)
                add("FOCUS", name, focused, unfocused)
                add("DISABLED", name, restingScreen(name), restingScreen(name, disabled: true))
            }
            for name in stated { add("STATE", name, restingScreen(name), restingScreen(name, on: true)) }
            let path = ProcessInfo.processInfo.environment["TUI_AUDIT_DUMP"] ?? ""
            try? report.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
