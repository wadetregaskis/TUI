//  🖥️ TUI — A Terminal UI framework for Swift
//  ViewRendererTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

/// Tests for `ViewRenderer`, the one-off renderer behind `renderOnce(_:)`.
///
/// It queries the terminal size, renders the view to a `FrameBuffer`,
/// and writes the buffer line by line where the cursor is. A `MockTerminal`
/// is injected via the `TerminalProtocol` parameter; it captures every write.
@MainActor
@Suite("ViewRenderer")
struct ViewRendererTests {

    private let sampleView = VStack {
        Text("one")
        Text("two")
    }

    /// The visible (ANSI-stripped) content lines written to the mock, without
    /// the newline each ends in.
    private func visibleWrites(_ mock: MockTerminal) -> [String] {
        mock.writtenOutput.compactMap {
            let stripped = $0.stripped.trimmingCharacters(in: .newlines)
            return stripped.isEmpty ? nil : stripped
        }
    }

    /// The live pipeline neutralises a cursor-moving control at its write
    /// boundary; this one-off path is a second boundary and skipped it, so a
    /// tab in user data shoved the row to the next tab stop.
    @Test("A snapshot neutralises a control character in a row")
    func snapshotSanitisesControls() {
        let mock = MockTerminal()
        mock.size = (20, 4)
        let userData = "a\tb"
        ViewRenderer(terminal: mock).render(Text(userData))
        #expect(
            !mock.writtenOutput.contains { $0.unicodeScalars.contains("\u{09}") },
            "a tab reached the terminal raw")
        #expect(mock.outputContains("a b"))
    }

    /// A terminal that under-advances a glyph does so however the bytes were
    /// produced, and this path builds none of a frame: no diff, no reuse cache,
    /// no padding — and, until this was added, no advance model either. So a
    /// `renderOnce` snapshot containing `⚙️` put the rest of its line one cell
    /// to the left on Terminal.app, in exactly the way the animation replay did
    /// (`ReplayCursorCompensationTests`) and for exactly the same reason: it
    /// wrote content the writer never saw.
    @Test("A snapshot carries the host's cursor compensation")
    func snapshotsAreCompensated() throws {
        let mock = MockTerminal()
        mock.size = (30, 4)
        // The host is detected once from the process environment, so which
        // model is under test has to be said rather than arranged.
        let appleTerminal = FrameDiffWriter(program: .appleTerminal)

        ViewRenderer(terminal: mock, writer: appleTerminal).render(Text("⚙️ settings"))

        let line = try #require(
            mock.writtenOutput.first { $0.unicodeScalars.contains("\u{2699}") },
            "no write carried the cluster at all")
        #expect(line.contains("\u{1B}[1C"), "the cluster reached the terminal bare")
    }

    /// …and a host with no measured model still gets its bytes untouched, so
    /// the line above is a compensation test and not a "compensate everything"
    /// test.
    @Test("A snapshot on an unmodelled host is written verbatim")
    func unmodelledHostsAreUntouched() {
        let mock = MockTerminal()
        mock.size = (30, 4)
        let plain = FrameDiffWriter(program: .unidentified)

        ViewRenderer(terminal: mock, writer: plain).render(Text("⚙️ settings"))

        #expect(!mock.writtenOutput.contains { $0.contains("\u{1B}[1C") })
    }

    @Test("Renders without crashing and writes the view's content")
    func rendersContent() {
        let mock = MockTerminal()
        mock.size = (20, 6)

        // Regression guard: this used to crash because ViewRenderer
        // built a context with no stateStorage, which the render pass
        // force-unwraps.
        ViewRenderer(terminal: mock).render(sampleView)

        #expect(visibleWrites(mock) == ["one", "two"])
    }

    @Test("Snapshot render does not fire onAppear")
    func doesNotFireOnAppear() {
        final class Flag {
            var fired = false
        }
        let flag = Flag()
        let mock = MockTerminal()
        mock.size = (20, 6)
        let view = Text("hi").onAppear { flag.fired = true }

        ViewRenderer(terminal: mock).render(view)

        #expect(flag.fired == false, "a one-off snapshot must not fire onAppear")
        // …but the view still renders.
        #expect(visibleWrites(mock).contains { $0.contains("hi") })
    }

    /// A snapshot keeps nothing once it is drawn. What its context keeps holds
    /// closures over that context — a `List`'s handler answers row heights
    /// from the rows it drew, and each row's box holds the context it was built
    /// under — and the context's environment holds the storage, the cache and
    /// the focus manager those closures are kept in. So each was in a cycle
    /// with what it kept, and every `renderOnce` of a list left its whole
    /// render behind for the life of the process.
    @Test("A snapshot's state, render cache and focus manager go with it, a list's closures over them included")
    func snapshotKeepsNothing() {
        weak var storage: StateStorage?
        weak var cache: RenderCache?
        weak var focus: FocusManager?
        do {
            let mock = MockTerminal()
            mock.size = (30, 8)
            let renderer = ViewRenderer(terminal: mock)
            renderer.render(
                List(selection: .constant(String?.none)) {
                    ForEach(["one", "two", "three"], id: \.self) { Text($0) }
                })
            storage = renderer.context.stateStorage
            cache = renderer.context.renderCache
            focus = renderer.focusManager
            #expect(visibleWrites(mock).contains { $0.contains("two") }, "the list was not drawn")
        }
        #expect(storage == nil, "the snapshot's state storage outlived it")
        #expect(cache == nil, "the snapshot's render cache outlived it")
        #expect(focus == nil, "the snapshot's focus manager outlived it")
    }

    /// The same oracle over every kind of registration a walk makes with the
    /// context's services, not only a list's: a hit-test handler, a shortcut,
    /// a focusable, a presentation, a drop target, a status-bar item, a help
    /// candidate. Any one of them left holding a closure over the walk's
    /// `RenderContext` keeps the whole snapshot alive.
    @Test("A snapshot goes with its renderer whatever it registered", arguments: SnapshotSubject.allCases)
    func snapshotOfAnySubjectKeepsNothing(_ subject: SnapshotSubject) {
        weak var storage: StateStorage?
        weak var cache: RenderCache?
        weak var focus: FocusManager?
        do {
            let mock = MockTerminal()
            mock.size = (40, 12)
            let renderer = ViewRenderer(terminal: mock)
            renderer.render(subject.view)
            storage = renderer.context.stateStorage
            cache = renderer.context.renderCache
            focus = renderer.focusManager
            #expect(!visibleWrites(mock).isEmpty, "nothing was drawn")
        }
        #expect(storage == nil, "\(subject): the snapshot's state storage outlived it")
        #expect(cache == nil, "\(subject): the snapshot's render cache outlived it")
        #expect(focus == nil, "\(subject): the snapshot's focus manager outlived it")
    }

    /// A snapshot's teardown runs none of the views' code. Its focus manager
    /// has to be emptied, or what it keeps keeps the snapshot alive (above),
    /// but `FocusManager.clear()` empties it by telling the focused control it
    /// lost the focus, which is `App.cleanup`'s commit point at quit. Here it
    /// told a text field the snapshot had auto-focused that its editing had
    /// ended: `onEditingChanged(false)`, after the frame was on the terminal.
    /// A snapshot has no teardown pass (see the type's documentation) and runs
    /// no effects.
    @Test("A snapshot's teardown tells no control it lost the focus")
    func snapshotTeardownIsSilent() {
        final class Log {
            var editing: [Bool] = []
        }
        let log = Log()
        let mock = MockTerminal()
        mock.size = (30, 4)

        ViewRenderer(terminal: mock).render(
            TextField("Name", text: .constant("x")).onEditingChanged { log.editing.append($0) })

        #expect(visibleWrites(mock).contains { $0.contains("x") }, "the field was not drawn")
        // The arrival is the snapshot's auto-focus, as before the teardown
        // existed; it is the departure that must not come.
        #expect(log.editing == [true], "the snapshot's teardown reported an edit's end: \(log.editing)")
    }

    /// A snapshot is a second screen root, and the root is where a displaced
    /// drawing lands: `.offset` paints NOTHING at its natural position and puts
    /// the glyphs in an `OverlayLayer`, so a flush that walked only
    /// `buffer.lines` wrote one empty row and the "A" reached the terminal
    /// never. Same mechanism for `.position`, `.popover`, `.sheet`, `.alert`.
    @Test("A snapshot composites a displaced drawing")
    func snapshotCompositesOverlayLayers() {
        let mock = MockTerminal()
        mock.size = (20, 4)

        ViewRenderer(terminal: mock).render(Text("A").offset(x: 2))

        // Column 2, which is the whole point of the offset: the composite pads
        // the one-cell placeholder out to three and inserts the layer at x = 2.
        // `stripped` removes ANSI and not whitespace, so this pins the COLUMN —
        // a composite at x = 0 still fails.
        #expect(visibleWrites(mock) == ["  A"])
    }

    /// …and the other half of the same root: `.opacity` records a region for a
    /// compositor to blend and leaves its cells at full strength, so a snapshot
    /// that resolved no region printed the faded row byte-for-byte identically
    /// to the unfaded one.
    ///
    /// Under a PINNED depth, because the assertion is that the row's colour
    /// changed and at ``ColorDepth/noColor`` a blend emits no colour at all —
    /// `Color.foregroundCodes()` returns `[]` there and `SGRState` deliberately
    /// does nothing with an empty list. Unpinned, this would pass in a
    /// developer's terminal and fail wherever `TERM=dumb`, which is what
    /// `ColorDepth.detect()` reads as `.noColor`.
    @Test("A snapshot resolves an opacity region")
    func snapshotResolvesOpacityRegions() throws {
        try withColorDepth(.truecolor) {
            let plain = MockTerminal()
            plain.size = (20, 4)
            let faded = MockTerminal()
            faded.size = (20, 4)

            ViewRenderer(terminal: plain).render(Text("faint"))
            ViewRenderer(terminal: faded).render(Text("faint").opacity(0.3))

            // The same glyphs — a fade is a colour, not a substitution …
            #expect(visibleWrites(faded) == visibleWrites(plain))
            // … and different bytes, because the blend names a colour 30% of the
            // way from the palette's foreground toward its background. The span
            // is uniform, so the escape lands once at column 0 and "faint" stays
            // contiguous.
            let fadedRow = try #require(faded.writtenOutput.first { $0.contains("faint") })
            let plainRow = try #require(plain.writtenOutput.first { $0.contains("faint") })
            #expect(fadedRow != plainRow, "the region was never resolved: \(fadedRow.debugDescription)")
        }
    }
}

/// What `ViewRendererTests.snapshotOfAnySubjectKeepsNothing` snapshots: one
/// view per kind of registration a walk makes with the context's services.
enum SnapshotSubject: String, CaseIterable, Sendable {
    case list, table, shortcutButton, textField, slider, stepper, toggle, picker, menu
    case scrollView, hoverAndHelp, tapGesture, keyPress, contextMenu, sheet, alert
    case dropDestination, statusBarItems, navigationStack, tabView
    /// A sheet posts the rows it docks for a root to lay the page out by: a
    /// dismissed one every frame, a live one while it is presented. Its
    /// resolver holds the presenter's environment, which holds the focus
    /// manager it was posted to, and a snapshot has no root to read it.
    case dismissedSheet, liveSheet

    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
    }

    @MainActor var view: AnyView {
        switch self {
        case .list:
            AnyView(List(selection: .constant(String?.none)) {
                ForEach(["one", "two"], id: \.self) { Text($0) }
            })
        case .table:
            AnyView(Table([Row(id: 0), Row(id: 1)], selection: .constant(Int?.none)) {
                TableColumn("Name", value: \Row.name)
            })
        case .shortcutButton:
            AnyView(Button("Go") {}.keyboardShortcut(.defaultAction))
        case .textField:
            AnyView(TextField("Name", text: .constant("x")))
        case .slider:
            AnyView(Slider(value: .constant(0.5)))
        case .stepper:
            AnyView(Stepper("Count", value: .constant(1)))
        case .toggle:
            AnyView(Toggle("On", isOn: .constant(true)))
        case .picker:
            AnyView(Picker("Pick", selection: .constant(1)) {
                Text("one").tag(1)
                Text("two").tag(2)
            })
        case .menu:
            AnyView(Menu("Menu") { Button("A") {} })
        case .scrollView:
            AnyView(ScrollView { ForEach(0..<30, id: \.self) { Text("line \($0)") } })
        case .hoverAndHelp:
            AnyView(Text("hover").onHover { _ in }.help("tip"))
        case .tapGesture:
            AnyView(Text("tap").onTapGesture {})
        case .keyPress:
            AnyView(Button("Key") {}.onKeyPress("k") { .handled })
        case .contextMenu:
            AnyView(Text("context").contextMenu { Button("A") {} })
        case .sheet:
            AnyView(Text("under").sheet(isPresented: .constant(true)) { Text("sheet") })
        case .alert:
            AnyView(Text("under").alert("Title", isPresented: .constant(true)) { Button("OK") {} })
        case .dropDestination:
            AnyView(Text("drop").dropDestination(for: String.self) { _, _ in true })
        case .statusBarItems:
            AnyView(Text("status").statusBarItems([StatusBarItem(shortcut: "n", label: "new") {}]))
        case .navigationStack:
            AnyView(NavigationStack { Text("root") })
        case .tabView:
            AnyView(TabView {
                Tab("Alpha", systemImage: "a.circle") { Text("ALPHA") }
                Tab("Beta", systemImage: "b.circle") { Text("BETA") }
            })
        case .dismissedSheet:
            AnyView(Text("under").sheet(isPresented: .constant(false)) { Text("sheet") })
        case .liveSheet:
            AnyView(Text("under").sheet(isPresented: .constant(true)) {
                Text("sheet")
                    .presentationDetents([.medium])
                    .presentationBackgroundInteraction(.enabled)
            })
        }
    }
}

// MARK: - Drawing where the cursor is

/// `renderOnce`'s path: from the line the cursor is on, a newline after every
/// row, and plain text where there is no terminal.
@MainActor
@Suite("ViewRenderer, inline")
struct ViewRendererInlineTests {

    @Test("Moves the cursor nowhere, and ends on the line after the last row")
    func noCursorMoves() {
        let mock = MockTerminal()
        ViewRenderer(terminal: mock).render(
            VStack(alignment: .leading) {
                Text("one")
                Text("two")
            },
            plainText: false)

        #expect(mock.cursorMoves.isEmpty)
        let written = mock.writtenOutput.joined()
        #expect(written.hasSuffix("\n"))
        #expect(!written.contains("\u{1B}[1;1H"))
        #expect(written.stripped.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) } == ["one", "two"])
    }

    @Test("Takes the height it asks for, not the terminal's: a Spacer is the least it can be")
    func naturalHeight() {
        let mock = MockTerminal()
        mock.size = (40, 10)
        ViewRenderer(terminal: mock).render(
            VStack {
                Text("top")
                Spacer()
            },
            plainText: true)
        #expect(mock.writtenOutput.count < 10)
        #expect(mock.writtenOutput.first == "top\n")
    }

    @Test("A stack taller than the terminal is all written")
    func tallerThanTheTerminal() {
        let mock = MockTerminal()
        mock.size = (40, 5)
        ViewRenderer(terminal: mock).render(
            VStack(alignment: .leading) {
                ForEach(0..<30, id: \.self) { Text("row \($0)") }
            },
            plainText: true)
        #expect(mock.writtenOutput == (0..<30).map { "row \($0)\n" })
    }

    @Test("Plain text holds no escape sequence and no trailing spaces")
    func plainText() {
        let mock = MockTerminal()
        ViewRenderer(terminal: mock).render(
            VStack(alignment: .leading) {
                Text("bold").bold().foregroundStyle(.red)
                Text("wider row")
            },
            plainText: true)
        #expect(mock.writtenOutput == ["bold\n", "wider row\n"])
    }

    @Test("Styled rows end their styling before the newline, so a scroll does not smear a colour")
    func styledRowsEndStyling() {
        let mock = MockTerminal()
        ViewRenderer(terminal: mock).render(Text("red").foregroundStyle(.red), plainText: false)
        let written = mock.writtenOutput.joined()
        #expect(written.contains("\u{1B}["))
        #expect(written.hasSuffix("\u{1B}[0m\n"))
    }
}

/// What `renderOnce` writes, by what stdout is and what the environment says.
@Suite("RenderOnceOutput")
struct RenderOnceOutputTests {
    private func automatic(terminal: Bool, _ environment: [String: String] = [:]) -> RenderOnceOutput.Resolved {
        RenderOnceOutput.automatic.resolved(stdoutIsTerminal: terminal, environment: environment)
    }

    @Test("By default: escape sequences to a terminal, plain text elsewhere")
    func byDefault() {
        #expect(automatic(terminal: true) == .styled)
        #expect(automatic(terminal: false) == .plainText)
    }

    @Test("TUI_FORCE_ESCAPES overrules both ways, and an empty value is no value")
    func tuiVariable() {
        #expect(automatic(terminal: false, ["TUI_FORCE_ESCAPES": "1"]) == .styled)
        #expect(automatic(terminal: true, ["TUI_FORCE_ESCAPES": "0"]) == .plainText)
        #expect(automatic(terminal: false, ["TUI_FORCE_ESCAPES": ""]) == .plainText)
        #expect(automatic(terminal: true, ["TUI_FORCE_ESCAPES": "0", "FORCE_COLOR": "1"]) == .plainText)
    }

    @Test("TUI_FORCE_ESCAPES is about the sequences: NO_COLOR still takes the colours out of them")
    func tuiVariableKeepsNoColor() {
        let environment = ["TUI_FORCE_ESCAPES": "1", "NO_COLOR": "1"]
        #expect(automatic(terminal: false, environment) == .styled)
        #expect(ColorDepth.detect(environment: environment) == .noColor)
    }

    @Test("FORCE_COLOR forces the sequences down a pipe, at its level", arguments: ["1", "2", "3", "true", "yes"])
    func forceColor(value: String) {
        #expect(automatic(terminal: false, ["FORCE_COLOR": value]) == .styled)
    }

    @Test("FORCE_COLOR=0 is no colour: a terminal keeps its attributes, and a pipe gets plain text")
    func forceColorOff() {
        #expect(automatic(terminal: true, ["FORCE_COLOR": "0"]) == .styled)
        #expect(ColorDepth.detect(environment: ["FORCE_COLOR": "0"]) == .noColor)
        #expect(automatic(terminal: false, ["FORCE_COLOR": "0"]) == .plainText)
    }

    @Test("CLICOLOR_FORCE forces as FORCE_COLOR does, and CLICOLOR doesn't")
    func cliColor() {
        #expect(automatic(terminal: false, ["CLICOLOR_FORCE": "1"]) == .styled)
        #expect(automatic(terminal: false, ["CLICOLOR_FORCE": "0"]) == .plainText)
        #expect(automatic(terminal: false, ["CLICOLOR": "1"]) == .plainText)
    }

    @Test("NO_COLOR beats FORCE_COLOR, so a pipe gets plain text, as it does for NO_COLOR alone")
    func noColorWins() {
        #expect(automatic(terminal: false, ["FORCE_COLOR": "3", "NO_COLOR": "1"]) == .plainText)
        #expect(automatic(terminal: false, ["CLICOLOR_FORCE": "1", "NO_COLOR": "1"]) == .plainText)
        #expect(automatic(terminal: true, ["FORCE_COLOR": "3", "NO_COLOR": "1"]) == .styled)
        #expect(ColorDepth.detect(environment: ["FORCE_COLOR": "3", "NO_COLOR": "1"]) == .noColor)
    }

    @Test("NO_COLOR leaves the colours out on a terminal; an empty one does not count")
    func noColor() {
        #expect(automatic(terminal: true, ["NO_COLOR": "1"]) == .styled)
        #expect(ColorDepth.detect(environment: ["NO_COLOR": "1"]) == .noColor)
        #expect(automatic(terminal: true, ["NO_COLOR": ""]) == .styled)
        #expect(ColorDepth.detect(environment: ["NO_COLOR": ""]) == .truecolor)
        #expect(automatic(terminal: false, ["NO_COLOR": "1"]) == .plainText)
    }

    @Test("A dumb terminal gets plain text, unless the program's user forces otherwise")
    func dumbTerminal() {
        #expect(automatic(terminal: true, ["TERM": "dumb"]) == .plainText)
        #expect(automatic(terminal: true, ["TERM": "dumb", "TUI_FORCE_ESCAPES": "1"]) == .styled)
        #expect(automatic(terminal: true, ["TERM": "dumb", "FORCE_COLOR": "1"]) == .styled)
    }

    @Test("A stated output beats the environment")
    func statedOutput() {
        let environment = ["TUI_FORCE_ESCAPES": "1", "NO_COLOR": "1"]
        #expect(RenderOnceOutput.plainText.resolved(stdoutIsTerminal: true, environment: environment) == .plainText)
        #expect(RenderOnceOutput.escapeSequences.resolved(stdoutIsTerminal: false, environment: [:]) == .styled)
    }

    @Test("Stated escape sequences get back the colours the environment took away, as far as the terminal has them")
    func statedEscapesOutrankNoColor() {
        func stated(_ environment: [String: String]) -> RenderOnceOutput.Resolved {
            RenderOnceOutput.escapeSequences.resolved(stdoutIsTerminal: false, environment: environment)
        }
        #expect(stated(["NO_COLOR": "1"]) == .styledAt(.truecolor))
        #expect(stated(["NO_COLOR": "1", "TERM": "xterm-256color"]) == .styledAt(.palette256))
        #expect(stated(["FORCE_COLOR": "0", "TERM": "xterm"]) == .styledAt(.basic16))
        #expect(stated(["NO_COLOR": "1", "TERM": "dumb"]) == .styledAt(.noColor))
    }
}
