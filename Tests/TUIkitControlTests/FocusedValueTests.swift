//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusedValueTests.swift
//
//  `.focusedValue(_:_:)`, `.focusedSceneValue(_:_:)`, `@FocusedValue` and
//  `@FocusedBinding`, through the real input chain: which value a reader
//  sees for where the focus is, that a reader drawn ahead of its publisher
//  catches up in one frame and no more, and that memos above either side keep
//  them honest.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

// MARK: - Keys

private struct NoteKey: FocusedValueKey {
    typealias Value = String
}

private struct CountKey: FocusedValueKey {
    typealias Value = Binding<Int>
}

private struct ActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    fileprivate var note: String? {
        get { self[NoteKey.self] }
        set { self[NoteKey.self] = newValue }
    }

    fileprivate var count: Binding<Int>? {
        get { self[CountKey.self] }
        set { self[CountKey.self] = newValue }
    }

    fileprivate var action: (() -> Void)? {
        get { self[ActionKey.self] }
        set { self[ActionKey.self] = newValue }
    }
}

@Observable
private final class Model {
    var name = "model"
}

// MARK: - Readers

/// What a reader last read.
private final class Seen {
    var note: String?
    var count: Binding<Int?>?
    var model: Model?
}

/// Draws and records the focused note.
private struct NoteReader: View, Equatable {
    @FocusedValue(\.note) private var note
    let seen: Seen

    var body: some View {
        seen.note = note
        return Text("note: \(note ?? "none")")
    }

    /// Every reader a test builds records into one `Seen`, so any two compare
    /// equal: the memo above one would serve it, if nothing told it not to.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
}

private struct CountReader: View {
    @FocusedBinding(\.count) private var count
    let seen: Seen

    var body: some View {
        seen.count = $count
        return Text("count: \(count.map(String.init) ?? "none")")
    }
}

private struct ModelReader: View {
    @FocusedValue(Model.self) private var model
    let seen: Seen

    var body: some View {
        seen.model = model
        return Text(model?.name ?? "none")
    }
}

/// A pane that publishes a scene value from inside a memo boundary.
private struct ScenePane: View, Equatable {
    let note: String

    var body: some View {
        Text("pane").focusedSceneValue(\.note, note)
    }
}

/// A publisher of a binding to its own state.
private struct Counter: View {
    @State private var count = 3

    var body: some View {
        Button("count \(count)") {}.focusedValue(\.count, $count)
    }
}

// MARK: - Tests

@MainActor
@Suite("Focused values")
struct FocusedValueTests {
    private let tab = KeyEvent(key: .tab)

    @Test("A reader beside two publishers reads the one the focus is in, and follows the focus")
    func followsTheFocus() {
        let harness = InputChainHarness()
        let seen = Seen()
        let page = {
            VStack {
                NoteReader(seen: seen)
                Button("A") {}.focusedValue(\.note, "a")
                Button("B") {}.focusedValue(\.note, "b")
            }
        }
        harness.frame(page())
        harness.frame(page())
        #expect(seen.note == "a", "the first button holds the focus")
        harness.press(tab)
        harness.frame(page())
        #expect(seen.note == "b", "Tab moved the focus to the second publisher")
    }

    @Test("A focused value is seen only with the focus inside its view; a scene value everywhere")
    func focusedAgainstScene() {
        let harness = InputChainHarness()
        let seen = Seen()
        let page = {
            VStack {
                NoteReader(seen: seen)
                Button("A") {}
                Button("B") {}.focusedValue(\.note, "b")
                Text("scene").focusedSceneValue(\.note, "scene")
            }
        }
        harness.frame(page())
        harness.frame(page())
        #expect(seen.note == "scene", "focus is on A, outside B: only the scene value shows")
        harness.press(tab)
        harness.frame(page())
        #expect(seen.note == "b", "on B, its focused value wins over the scene value")
    }

    @Test("Of two publishers on the focus's path, the innermost wins")
    func innermostWins() {
        let harness = InputChainHarness()
        let seen = Seen()
        let page = {
            VStack {
                NoteReader(seen: seen)
                VStack {
                    Button("A") {}.focusedValue(\.note, "inner")
                    Button("B") {}
                }
                .focusedValue(\.note, "outer")
            }
        }
        harness.frame(page())
        harness.frame(page())
        #expect(seen.note == "inner")
        harness.press(tab)
        harness.frame(page())
        #expect(seen.note == "outer", "B publishes nothing of its own; its container's value shows")
    }

    @Test("A reader drawn ahead of its publisher catches up in one more frame, and then asks for none")
    func oneCatchUpFrame() {
        let harness = InputChainHarness()
        var requests = 0
        harness.focusManager.focusedValues.requestFrame = { requests += 1 }
        let seen = Seen()
        let page = {
            VStack {
                NoteReader(seen: seen)
                Button("A") {}.focusedValue(\.note, "a")
            }
        }
        harness.frame(page())
        #expect(seen.note == nil, "the first frame's reader drew before anything was published")
        #expect(requests == 1, "so the pass asked for the frame that shows the value")
        harness.frame(page())
        #expect(seen.note == "a")
        harness.frame(page())
        #expect(requests == 1, "a steady page asks for nothing more")
    }

    @Test("A closure published afresh every frame does not ask for frames forever")
    func uncomparableValueSettles() {
        let harness = InputChainHarness()
        var requests = 0
        harness.focusManager.focusedValues.requestFrame = { requests += 1 }
        let page = {
            VStack {
                Button("A") {}.focusedValue(\.action) {}
                ActionReader()
            }
        }
        // The first frame measures the reader before anything is published, so
        // it may ask for one frame; after that, nothing.
        harness.frame(page())
        harness.frame(page())
        let settled = requests
        for _ in 0..<4 { harness.frame(page()) }
        #expect(requests == settled, "one view publishing a new closure each frame is the same value")
    }

    @Test("@FocusedBinding reads through the published binding and writes back through it")
    func bindingWritesThrough() {
        let harness = InputChainHarness()
        let seen = Seen()
        let page = {
            VStack {
                CountReader(seen: seen)
                Counter()
            }
        }
        harness.frame(page())
        let first = harness.frame(page())
        #expect(seen.count?.wrappedValue == 3)
        #expect(first.lines.contains { $0.stripped.contains("count: 3") })
        seen.count?.wrappedValue = 9
        harness.frame(page())
        let after = harness.frame(page())
        #expect(after.lines.contains { $0.stripped.contains("count 9") }, "the publisher's own state changed")
        seen.count?.wrappedValue = nil
        harness.frame(page())
        #expect(seen.count?.wrappedValue == 9, "setting nil writes nothing")
    }

    @Test("An @Observable object is published and read by its type")
    func observableObject() {
        let harness = InputChainHarness()
        let seen = Seen()
        let model = Model()
        let page = {
            VStack {
                ModelReader(seen: seen)
                Button("A") {}.focusedValue(model)
            }
        }
        harness.frame(page())
        harness.frame(page())
        #expect(seen.model === model)
    }

    @Test("A publisher served from a memo still publishes, and a memoized reader still follows the focus")
    func memosKeepBothSidesHonest() {
        let harness = InputChainHarness()
        let seen = Seen()
        let page = {
            VStack {
                NoteReader(seen: seen).equatable()
                ScenePane(note: "pane").equatable()
                Button("A") {}
                Button("B") {}.focusedValue(\.note, "b")
            }
        }
        for _ in 0..<4 { harness.frame(page()) }
        #expect(seen.note == "pane", "the memoized pane's scene value survives its served frames")
        harness.press(tab)
        let buffer = harness.frame(page())
        #expect(seen.note == "b", "the memoized reader re-read when the focus moved")
        #expect(buffer.lines.contains { $0.stripped.contains("note: b") })
    }
}

/// Reads the published closure, so the end-of-pass check has a read to compare.
private struct ActionReader: View {
    @FocusedValue(\.action) private var action

    var body: some View {
        Text(action == nil ? "no action" : "action")
    }
}
