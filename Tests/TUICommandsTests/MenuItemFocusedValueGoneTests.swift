//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuItemFocusedValueGoneTests.swift
//
//  A command disabled while the focused value it acts on is absent goes
//  disabled once its publisher stops publishing — publishes `nil`, or is taken
//  away — in the frame the end of the pass asks for, with no other event to
//  draw it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// What the page publishes, and what the command did: reachable from an `App`.
@Observable
private final class GoneSource: @unchecked Sendable {
    static let shared = GoneSource()
    var note: String? = "x"
    var shows = true
    @ObservationIgnored var log: [String] = []
}

private struct GoneNoteKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    fileprivate var goneNote: String? {
        get { self[GoneNoteKey.self] }
        set { self[GoneNoteKey.self] = newValue }
    }
}

/// A command enabled by the focused note alone, with a shortcut to try it by.
private struct GoneCommands: Commands {
    @FocusedValue(\.goneNote) private var note

    var body: some Commands {
        CommandMenu("Note") {
            Button("Show") { GoneSource.shared.log.append("show \(note ?? "none")") }
                .keyboardShortcut("s", modifiers: .control)
                .disabled(note == nil)
        }
    }
}

/// A page publishing the note as a scene value, while it shows.
private struct GonePage: View {
    let source = GoneSource.shared

    var body: some View {
        VStack(spacing: 0) {
            if source.shows { Text("pane").focusedSceneValue(\.goneNote, source.note) }
            Button("A") {}
        }
    }
}

private struct GoneApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { GonePage() }
            .commandsRemoved()
            .commands { GoneCommands() }
    }
}

// MARK: - Tests

@MainActor
@Suite("A command gated by a focused value whose publisher stops", .serialized)
struct MenuItemFocusedValueGoneTests {
    enum Stop: CaseIterable, Sendable {
        case publishesNil, removed
    }

    /// FOCUS-4: no frame was asked for, so the command stayed enabled and its
    /// shortcut ran with nothing to act on.
    @Test("The command goes disabled in the frame the pass asks for", arguments: Stop.allCases)
    func commandGoesDisabled(stop: Stop) {
        let source = GoneSource.shared
        source.note = "x"
        source.shows = true
        source.log = []
        let app = TestApp(GoneApp(), width: 40, height: 8)
        var now: Int64 = 0
        func frame() {
            app.frame(atNanos: now)
            now += 20_000_000
        }
        for _ in 0..<3 { frame() }
        app.send(KeyEvent(key: .character("s"), ctrl: true))
        #expect(source.log == ["show x"], "sanity: the command is enabled by the note")
        frame()
        let asked = app.framesAsked
        switch stop {
        case .publishesNil: source.note = nil
        case .removed: source.shows = false
        }
        frame()
        // A command read before the page published asks for one frame; one
        // read after it reads the `nil` the page published in place of the
        // note, and needs none.
        #expect(app.framesAsked <= asked + 1, "at most one frame is asked for")
        // The run loop draws the frame asked for, and only that.
        if app.framesAsked > asked { frame() }
        app.send(KeyEvent(key: .character("s"), ctrl: true))
        #expect(source.log == ["show x"], "the command is disabled, so its shortcut does nothing")
    }
}
