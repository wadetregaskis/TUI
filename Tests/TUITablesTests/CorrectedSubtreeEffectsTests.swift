//  🖥️ TUI — A Terminal UI framework for Swift
//  CorrectedSubtreeEffectsTests.swift
//
//  A subtree that geometry correction draws twice in one frame does what it
//  does once, for the drawing that reaches the screen (decisions B-D5G-4):
//  every effect a view inside makes — `onChange`, `onPreferenceChange`,
//  `onGeometryChange`, `onAppear`, `onDisappear`, `.task`,
//  `onModifierKeysChanged`, `onInteractiveResizeChange`, the scroll
//  observers — is the kept drawing's, and a view only the discarded drawing
//  drew does nothing at all.
//
//  The reader below is told a guess on its first frame (the container it is
//  in moves it without carrying the move), draws from the guess, and is drawn
//  again from the answer: the guess and the answer pick different branches,
//  so the discarded drawing draws views the kept one does not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITables
@testable import TUITestSupport
@testable import TUIView

/// What the views did, in order, by reference so every frame's views reach it.
@MainActor
private final class EffectLog {
    var lines: [String] = []

    func count(_ prefix: String) -> Int { lines.filter { $0.hasPrefix(prefix) }.count }
}

/// The reader's y, reduced up to whoever asks.
private struct ReaderY: PreferenceKey {
    static var defaultValue: Int { -1 }
    static func reduce(value: inout Int, nextValue: () -> Int) { value = max(value, nextValue()) }
}

/// A one-line reader of `space` whose content is built from where it is: a
/// view for the answer (`y >= 1`) and another for the guess, each carrying
/// every effect under test.
@MainActor
private func effectsReader(_ log: EffectLog, in space: CoordinateSpace) -> some View {
    GeometryReader { proxy in
        let y = proxy.frame(in: space).minY
        VStack(alignment: .leading, spacing: 0) {
            if y >= 1 {
                effects(log, "kept")
            } else {
                effects(log, "guess")
            }
            Text(String(repeating: "y", count: max(1, y + 1)))
                .onGeometryChange(for: Int.self) { $0.size.width } action: { old, new in
                    log.lines.append("width \(old)→\(new)")
                }
        }
        .onChange(of: y) { old, new in log.lines.append("change \(old)→\(new)") }
        .preference(key: ReaderY.self, value: y)
    }
    .frame(width: 12, height: 3)
}

/// A view named `name` carrying every lifecycle and observer effect.
@MainActor
private func effects(_ log: EffectLog, _ name: String) -> some View {
    ScrollView {
        Text(name)
    }
    .onScrollGeometryChange(for: Int.self) { $0.contentSize.height } action: { _, new in
        log.lines.append("\(name) scroll geometry \(new)")
    }
    .onScrollPhaseChange { _, new in log.lines.append("\(name) scroll phase \(new)") }
    .frame(height: 1)
    .onAppear { log.lines.append("\(name) appear") }
    .onDisappear { log.lines.append("\(name) disappear") }
    .task { log.lines.append("\(name) task") }
    .onModifierKeysChanged(mask: .shift, initial: true) { _, _ in log.lines.append("\(name) keys") }
    .onInteractiveResizeChange { resizing in log.lines.append("\(name) resizing \(resizing)") }
}

/// A value an `onAppear` in a scroll view writes, shown above the scroll
/// view and in it, after the view that writes it.
private struct WritesOnAppear: View {
    @State private var value = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("above \(value)")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("first").onAppear { value = 7 }
                    Text("after \(value)")
                }
            }
            .coordinateSpace(.named("s"))
        }
    }
}

@MainActor
@Suite("A corrected subtree's side effects")
struct CorrectedSubtreeEffectsTests {
    /// A frame of the reader: `lead` rows down, which the prediction follows,
    /// then `top` rows more, which it does not — in a named space, asking it
    /// or `.global`.
    private func page(_ log: EffectLog, lead: Int = 0, top: Int, in space: CoordinateSpace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<lead, id: \.self) { Text("lead \($0)") }
            UnconvertedContainer(rows: top) { effectsReader(log, in: space) }
        }
        .onPreferenceChange(ReaderY.self) { log.lines.append("preference \($0)") }
        .coordinateSpace(.named("s"))
    }

    private func harness() -> InputChainHarness {
        let harness = InputChainHarness(keyboard: .requested)
        // Shift held, so `onModifierKeysChanged(initial: true)` fires on
        // appearing; and a resize this instant, so `onInteractiveResizeChange`
        // is told `true` on a first frame.
        harness.tui.modifierKeys.record(ModifierKeyState(shift: true))
        harness.tui.renderCache.terminalResizedAtNanos = harness.now
        return harness
    }

    @Test(
        "Each effect in a corrected subtree runs once, for the kept drawing; the guess's views do nothing",
        arguments: [false, true])
    func firstFrame(global: Bool) async {
        // A named space's owner corrects the subtree; `.global`'s is the
        // scene root, which walks the scene again.
        let space: CoordinateSpace = global ? .global : .named("s")
        let log = EffectLog()
        let harness = harness()
        harness.frame(page(log, top: 1, in: space))
        #expect(harness.geometryCorrections.total == 1, "the reader's guess was not corrected")
        await settle(until: { log.count("kept task") == 1 })
        // SwiftUI fires no onChange on a first appearance, and the guess was
        // never shown.
        #expect(log.count("change") == 0, "\(log.lines)")
        #expect(!log.lines.contains { $0.hasPrefix("guess") }, "\(log.lines)")
        for effect in ["appear", "task", "keys", "resizing true", "scroll geometry", "scroll phase"] {
            #expect(log.count("kept \(effect)") == 1, "kept \(effect): \(log.lines)")
        }
        #expect(log.lines.filter { $0.hasPrefix("preference") } == ["preference 1"], "\(log.lines)")
        #expect(log.lines.filter { $0.hasPrefix("width") } == ["width 2→2"], "\(log.lines)")

        // The next frame is predicted right: nothing new, and the guess,
        // never on screen, does not disappear.
        harness.frame(page(log, top: 1, in: space))
        #expect(harness.geometryCorrections.total == 1)
        #expect(!log.lines.contains { $0.hasPrefix("guess") }, "\(log.lines)")
        #expect(log.count("kept disappear") == 0)
    }

    @Test("A corrected move fires onChange, onPreferenceChange and onGeometryChange once, old answer to new")
    func correctedMove() {
        let log = EffectLog()
        let harness = harness()
        harness.frame(page(log, top: 1, in: .named("s")))
        harness.frame(page(log, top: 1, in: .named("s")))
        log.lines.removeAll()
        let before = harness.geometryCorrections.named
        // The prediction follows the lead row, to 2, and misses the two rows
        // more the container adds: the first drawing draws from 2, which is
        // neither where the reader was nor where it is.
        harness.frame(page(log, lead: 1, top: 3, in: .named("s")))
        #expect(harness.geometryCorrections.named == before + 1, "the move was not corrected")
        #expect(log.lines.filter { $0.hasPrefix("change") } == ["change 1→4"], "\(log.lines)")
        #expect(log.lines.filter { $0.hasPrefix("preference") } == ["preference 4"], "\(log.lines)")
        #expect(log.lines.filter { $0.hasPrefix("width") } == ["width 2→5"], "\(log.lines)")
        #expect(!log.lines.contains { $0.hasPrefix("kept") }, "the kept views were drawn in both: \(log.lines)")
    }

    @Test("The kept drawing's effects run in the order its views made them")
    func keptOrder() {
        let log = EffectLog()
        let harness = harness()
        harness.frame(page(log, top: 1, in: .named("s")))
        // SwiftUI's order by kind — geometry, preference, appearance, then
        // the value observers — and the walk's within a kind: the modifiers
        // outermost first (`EffectStage.Kind`).
        let order = ["width 2→2", "preference 1", "kept appear", "kept resizing true", "kept keys"]
        let places = order.map { log.lines.firstIndex(of: $0) }
        #expect(!places.contains(nil), "\(log.lines)")
        let found = places.compactMap(\.self)
        #expect(found == found.sorted(), "\(log.lines)")
    }

    @Test(
        "Adversarial: inside a scroll view or a list in the corrected space, each effect still runs once",
        arguments: [false, true])
    func nestedOwners(list: Bool) async {
        let log = EffectLog()
        let harness = harness()
        // Owners within owners: the named space's correction draws the scroll
        // view (or the list) again, which opened a drawing of its own inside.
        let view = { (lead: Int, top: Int) in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<lead, id: \.self) { Text("lead \($0)") }
                if list {
                    List { UnconvertedContainer(rows: top) { effectsReader(log, in: .named("s")) } }
                        .frame(height: 8)
                } else {
                    ScrollView { UnconvertedContainer(rows: top) { effectsReader(log, in: .named("s")) } }
                        .frame(height: 8)
                }
            }
            .onPreferenceChange(ReaderY.self) { log.lines.append("preference \($0)") }
            .coordinateSpace(.named("s"))
        }
        harness.frame(view(0, 1))
        #expect(harness.geometryCorrections.total >= 1, "the reader's guess was not corrected")
        await settle(until: { log.count("kept task") == 1 })
        #expect(!log.lines.contains { $0.hasPrefix("guess") }, "\(log.lines)")
        #expect(log.count("change") == 0, "\(log.lines)")
        for effect in ["appear", "task", "keys", "resizing true", "scroll geometry", "scroll phase"] {
            #expect(log.count("kept \(effect)") == 1, "kept \(effect): \(log.lines)")
        }
        #expect(log.count("preference") == 1, "\(log.lines)")
        harness.frame(view(0, 1))
        log.lines.removeAll()
        harness.frame(view(1, 3))
        let changes = log.lines.filter { $0.hasPrefix("change") }
        let preferences = log.lines.filter { $0.hasPrefix("preference") }
        #expect(changes.count == 1, "\(log.lines)")
        #expect(preferences.count == 1, "\(log.lines)")
        #expect(log.count("width") == 1, "\(log.lines)")
        #expect(!log.lines.contains { $0.hasPrefix("guess") || $0.hasPrefix("kept") }, "\(log.lines)")
        // The preference reports the answer the change moved to.
        if let change = changes.first, let preference = preferences.first {
            #expect(preference == "preference \(change.split(separator: "→").last ?? "")", "\(log.lines)")
        }
    }

    @Test("With no reader, an onAppear's write waits for the walk, and the frame walked again shows it before and after")
    func noReaderSettlesBeforeTheFrame() {
        let harness = InputChainHarness()
        let buffer = harness.frame(WritesOnAppear())
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.contains { $0.contains("above 7") }, "\(lines)")
        #expect(lines.contains { $0.contains("after 7") }, "\(lines)")
    }
}
