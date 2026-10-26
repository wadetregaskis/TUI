//  🖥️ TUI — A Terminal UI framework for Swift
//  DynamicPropertyObjectStateTests.swift
//
//  A class property's `@State` is the object's own: no view's key holds it,
//  so no view showing another object binds it, no change of the views
//  holding it moves or drops it, and a write to it redraws every view drawn
//  holding the object, one served from the memo included (decisions-DYNVFIX
//  B-DYNVFIX-3, lane DYNVCLAIM). Under the claim it replaced, one view held
//  each object's boxes under its key, and two objects could share one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// What each body hands out, by the name of the view that handed it.
@MainActor
private final class StateTaps {
    var counts: [String: Binding<Int>] = [:]
    var flags: [String: Binding<Bool>] = [:]
}

/// A class property passed through a view that does not hold it as one, so
/// the views it is handed to are the first to reach it.
private struct Passed<Object: AnyObject> {
    let object: Object
}

/// A class app property holding a `@State`.
private final class Counter: DynamicProperty {
    @State var count = 0
}

/// A view showing a counter, drawn every time its parent is.
private struct CounterRow: View {
    let name: String
    let counter: Counter
    let taps: StateTaps

    var body: some View {
        taps.counts[name] = counter.$count
        return Text(verbatim: "\(name) \(counter.count)")
    }
}

/// A view showing a counter, served from the memo while its name and
/// generation are unchanged.
private struct MemoCounterRow: View, Equatable {
    let name: String
    var generation = 0
    let counter: Counter
    let taps: StateTaps

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.generation == rhs.generation
    }

    var body: some View {
        taps.counts[name] = counter.$count
        return Text(verbatim: "\(name) \(counter.count)")
    }
}

/// One counter, shown first by a memoised view and then by one drawn every
/// frame.
private struct MemoFirstCounterRows: View {
    let counter: Passed<Counter>
    let taps: StateTaps

    var body: some View {
        VStack {
            MemoCounterRow(name: "a", counter: counter.object, taps: taps).equatable()
            CounterRow(name: "b", counter: counter.object, taps: taps)
        }
    }
}

/// One counter shown by two memoised rows, the first of which can be removed.
private struct TwoMemoCounterRows: View {
    let showsFirst: Bool
    let generation: Int
    let counter: Passed<Counter>
    let taps: StateTaps

    var body: some View {
        VStack {
            if showsFirst {
                MemoCounterRow(name: "a", generation: generation, counter: counter.object, taps: taps)
                    .equatable().frame(height: 1)
            }
            MemoCounterRow(name: "b", generation: generation, counter: counter.object, taps: taps)
                .equatable().frame(height: 1)
        }
    }
}

/// One counter shown by a view an `if`/`else` swaps out, and a memoised one.
private struct BranchAndMemoRow: View {
    let showsFirst: Bool
    let counter: Passed<Counter>
    let taps: StateTaps

    var body: some View {
        VStack {
            if showsFirst {
                CounterRow(name: "a", counter: counter.object, taps: taps)
            } else {
                Text(verbatim: "none")
            }
            MemoCounterRow(name: "b", counter: counter.object, taps: taps).equatable()
        }
    }
}

/// The counter in a detail view, or a summary of it the view reads without
/// holding it — `Passed` is not looked into — served from the memo while
/// `showsDetail` is unchanged.
private struct DetailOrSummary: View, Equatable {
    let showsDetail: Bool
    let counter: Passed<Counter>
    let taps: StateTaps

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.showsDetail == rhs.showsDetail }

    var body: some View {
        if showsDetail {
            CounterRow(name: "detail", counter: counter.object, taps: taps)
        } else {
            Text(verbatim: "summary \(counter.object.count)")
        }
    }
}

/// `DetailOrSummary`, memoised, in a stack.
private struct MemoDetailOrSummary: View {
    let showsDetail: Bool
    let counter: Passed<Counter>
    let taps: StateTaps

    var body: some View {
        VStack {
            DetailOrSummary(showsDetail: showsDetail, counter: counter, taps: taps).equatable()
        }
    }
}

/// A detail view of the counter at `selection`, above rows for the counters
/// from `firstRow`: an array is not looked into, so the rows and the detail
/// view are the first to reach the counters.
private struct DetailOverRows: View {
    let counters: [Counter]
    let selection: Int
    let firstRow: Int
    let taps: StateTaps

    var body: some View {
        VStack {
            CounterRow(name: "detail", counter: counters[selection], taps: taps)
            ForEach(firstRow..<firstRow + 2, id: \.self) { index in
                CounterRow(name: "row\(index)", counter: counters[index], taps: taps)
            }
        }
    }
}

/// A class app property holding a flag.
private final class Toggled: DynamicProperty {
    @State var expanded = false
}

/// A row showing an item's flag, served from the memo while its name is
/// unchanged: it shows the flag and changes nothing.
private struct ToggledRow: View, Equatable {
    let name: String
    let item: Toggled

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }

    var body: some View {
        Text(verbatim: "\(name) \(item.expanded)")
    }
}

/// The item whose flag is changed.
private struct ToggledDetail: View {
    let item: Toggled
    let taps: StateTaps

    var body: some View {
        taps.flags["detail"] = item.$expanded
        return Text(verbatim: "detail \(item.expanded)")
    }
}

/// Memoised rows over every item, and a detail view of the one at
/// `selection`.
private struct ToggledList: View {
    let items: [Toggled]
    let selection: Int
    let taps: StateTaps

    var body: some View {
        VStack {
            ForEach(0..<items.count, id: \.self) { index in
                ToggledRow(name: "r\(index)", item: items[index])
            }
            ToggledDetail(item: items[selection], taps: taps)
        }
    }
}

/// A detail view alone, of the item at `selection`.
private struct ToggledSelection: View {
    let items: [Toggled]
    let selection: Int
    let taps: StateTaps

    var body: some View {
        ToggledDetail(item: items[selection], taps: taps)
    }
}

/// A value holding a `@State`, which two objects can hold copies of.
private struct Tally: DynamicProperty {
    @State var count = 0
}

/// A class app property holding a value that holds a `@State`.
private final class TallyHolder: DynamicProperty {
    var tally = Tally()
}

private struct TallyView: View {
    let name: String
    let holder: TallyHolder
    let taps: StateTaps

    var body: some View {
        taps.counts[name] = holder.tally.$count
        return Text(verbatim: "\(name) \(holder.tally.count)")
    }
}

/// Two objects, each shown by a view of its own.
private struct TwoTallies: View {
    let first: Passed<TallyHolder>
    let second: Passed<TallyHolder>
    let taps: StateTaps

    var body: some View {
        VStack {
            TallyView(name: "first", holder: first.object, taps: taps)
            TallyView(name: "second", holder: second.object, taps: taps)
        }
    }
}

@MainActor
@Suite("DynamicProperty objects' own state")
struct DynamicPropertyObjectStateTests {

    /// One frame as the render loop draws it: invalidations drained, the pass
    /// begun, the view made and drawn in it (`StateStorage.inRenderPass(_:)`),
    /// what was not drawn pruned.
    private func frame<V: View>(_ view: @autoclosure () -> V, _ tui: TUIContext, height: Int = 3) -> [String] {
        let context = RenderContext(availableWidth: 20, availableHeight: height, tuiContext: tui)
        tui.renderCache.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        defer {
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
        return tui.stateStorage.inRenderPass { renderToBuffer(view(), context: context) }.lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Whether the frames so far asked for nothing more: no invalidation
    /// queued since the last frame began.
    private func isIdle(_ tui: TUIContext) -> Bool {
        let pending = tui.renderCache.link.drain()
        return !pending.clearAll && pending.identities.isEmpty
    }

    // MARK: - Every holder redrawn by a write

    /// The claim moved to the view drawn every frame once the memoised view
    /// was served from the memo, and a write redrew only the claimant: the
    /// memoised view went on showing the old value (review of 8de82a920 and
    /// review5 of DYNVFIX, R3). Every view drawn holding the object is
    /// registered on it, and a write redraws each.
    @Test("A write to a class property's @State redraws a holder served from the memo")
    func memoServedHolderRedrawsOnAWrite() {
        let tui = TUIContext()
        let taps = StateTaps()
        let counter = Passed(object: Counter())
        #expect(frame(MemoFirstCounterRows(counter: counter, taps: taps), tui) == ["a 0", "b 0"])
        taps.counts["a"]?.wrappedValue = 5
        #expect(frame(MemoFirstCounterRows(counter: counter, taps: taps), tui) == ["a 5", "b 5"])
        #expect(frame(MemoFirstCounterRows(counter: counter, taps: taps), tui) == ["a 5", "b 5"])
        taps.counts["a"]?.wrappedValue = 9
        #expect(frame(MemoFirstCounterRows(counter: counter, taps: taps), tui) == ["a 9", "b 9"])
    }

    /// The holder left is served from the memo, with nothing new to draw:
    /// only the write can redraw it.
    @Test("A write to a class property's @State redraws the holder left, served from the memo")
    func remainingMemoServedHolderRedrawsOnAWrite() {
        let tui = TUIContext()
        let taps = StateTaps()
        let counter = Passed(object: Counter())
        let view = { (showsFirst: Bool, generation: Int) in
            TwoMemoCounterRows(showsFirst: showsFirst, generation: generation, counter: counter, taps: taps)
        }
        #expect(frame(view(true, 0), tui, height: 2) == ["a 0", "b 0"])
        taps.counts["a"]?.wrappedValue = 5
        #expect(frame(view(true, 1), tui, height: 2) == ["a 5", "b 5"])
        #expect(frame(view(false, 1), tui, height: 2).first == "b 5")
        taps.counts["b"]?.wrappedValue = 7
        #expect(frame(view(false, 1), tui, height: 2).first == "b 7")
    }

    /// Display-only rows, served from the memo, show each item's flag; the
    /// detail view changes the selected item's. Every row showing the item is
    /// redrawn.
    @Test("Memoised rows showing a class property are redrawn when a detail view writes its @State")
    func memoisedRowsRedrawWhenTheDetailWrites() {
        let tui = TUIContext()
        let taps = StateTaps()
        let items = [Toggled(), Toggled()]
        let view = { ToggledList(items: items, selection: 0, taps: taps) }
        #expect(frame(view(), tui) == ["r0 false", "r1 false", "detail false"])
        #expect(frame(view(), tui) == ["r0 false", "r1 false", "detail false"])
        taps.flags["detail"]?.wrappedValue = true
        #expect(frame(view(), tui) == ["r0 true", "r1 false", "detail true"])
    }

    /// The claim was dropped with the first holder's branch, and the
    /// memoised holder, served from the memo, took none: a write redrew the
    /// view that had left (review4 of DYNVFIX, deac1c31f(5)).
    @Test("A memoised holder is redrawn by a write after the other holder leaves through an if/else")
    func memoisedHolderRedrawsAfterTheOtherLeavesThroughAConditional() {
        let tui = TUIContext()
        let taps = StateTaps()
        let counter = Passed(object: Counter())
        let view = { (showsFirst: Bool) in BranchAndMemoRow(showsFirst: showsFirst, counter: counter, taps: taps) }
        #expect(frame(view(true), tui, height: 2) == ["a 0", "b 0"])
        taps.counts["a"]?.wrappedValue = 5
        #expect(frame(view(true), tui, height: 2) == ["a 5", "b 5"])
        #expect(frame(view(false), tui, height: 2) == ["none", "b 5"])
        taps.counts["b"]?.wrappedValue = 7
        #expect(frame(view(false), tui, height: 2) == ["none", "b 7"])
    }

    // MARK: - No state shared between objects

    /// A detail view moving to an object never drawn before bound its
    /// `@State` to the box kept under the detail view's key — the last
    /// object's — so the two objects shared one state (review5 of DYNVFIX,
    /// S2).
    @Test("An object a view shows for the first time never takes the state of the object it showed before")
    func aNeverDrawnObjectNeverTakesAnotherObjectsState() {
        let tui = TUIContext()
        let taps = StateTaps()
        let items = [Toggled(), Toggled()]
        let view = { (selection: Int) in ToggledSelection(items: items, selection: selection, taps: taps) }
        #expect(frame(view(0), tui, height: 1) == ["detail false"])
        taps.flags["detail"]?.wrappedValue = true
        #expect(frame(view(0), tui, height: 1) == ["detail true"])
        #expect(frame(view(1), tui, height: 1) == ["detail false"])
        taps.flags["detail"]?.wrappedValue = true
        #expect(frame(view(1), tui, height: 1) == ["detail true"])
        taps.flags["detail"]?.wrappedValue = false
        #expect(frame(view(0), tui, height: 1) == ["detail true"])
    }

    /// The detail view moved to an object whose row was not drawn, which
    /// bound the box the detail view's key kept — the first row's object's —
    /// and the two objects then moved that box between their holders' keys
    /// on every frame (review4 of DYNVFIX, 4df65e5ef(2)).
    @Test("Two objects shown at one place one after the other never share or swap their @State")
    func twoObjectsAtOnePlaceNeverShareOrSwap() {
        let tui = TUIContext()
        let taps = StateTaps()
        let counters = (0..<6).map { _ in Counter() }
        let view = { (selection: Int, firstRow: Int) in
            DetailOverRows(counters: counters, selection: selection, firstRow: firstRow, taps: taps)
        }
        #expect(frame(view(0, 0), tui) == ["detail 0", "row0 0", "row1 0"])
        taps.counts["row0"]?.wrappedValue = 3
        #expect(frame(view(0, 0), tui) == ["detail 3", "row0 3", "row1 0"])
        #expect(frame(view(5, 0), tui) == ["detail 0", "row0 3", "row1 0"])
        #expect(frame(view(5, 4), tui) == ["detail 0", "row4 0", "row5 0"])
        #expect(frame(view(5, 0), tui) == ["detail 0", "row0 3", "row1 0"])
        #expect(frame(view(5, 0), tui) == ["detail 0", "row0 3", "row1 0"])
        #expect(isIdle(tui), "a frame with nothing written asks for none")
        #expect(frame(view(5, 0), tui) == ["detail 0", "row0 3", "row1 0"])
        #expect(isIdle(tui), "a frame with nothing written asks for none")
        taps.counts["row0"]?.wrappedValue = 4
        #expect(frame(view(5, 0), tui) == ["detail 0", "row0 4", "row1 0"])
        taps.counts["detail"]?.wrappedValue = 7
        #expect(frame(view(5, 0), tui) == ["detail 7", "row0 4", "row1 0"])
    }

    /// A value holding a `@State`, copied from one live object into another,
    /// shares the first object's backing: the second is given its own, at
    /// its default, so a write to one never shows in the other.
    @Test("A @State copied from one live object into another is the second's own, at its default")
    func stateCopiedBetweenObjectsIsEachObjectsOwn() {
        let tui = TUIContext()
        let taps = StateTaps()
        let first = Passed(object: TallyHolder())
        let second = Passed(object: TallyHolder())
        let view = { TwoTallies(first: first, second: second, taps: taps) }
        #expect(frame(view(), tui, height: 2) == ["first 0", "second 0"])
        taps.counts["first"]?.wrappedValue = 5
        #expect(frame(view(), tui, height: 2) == ["first 5", "second 0"])
        second.object.tally = first.object.tally
        #expect(frame(view(), tui, height: 2) == ["first 5", "second 0"])
        taps.counts["second"]?.wrappedValue = 2
        #expect(frame(view(), tui, height: 2) == ["first 5", "second 2"])
    }

    /// Once every view holding the object has left, a write to its state
    /// redrew nothing, so a view reading it without holding it — its last
    /// holder's parent, served from the memo — went on showing the old value.
    /// Under the claim, the box was the last claimant's, and a write redrew
    /// what was above it (review1 of lane DYNVCLAIM, a7d1f8e75 (d)). It
    /// redraws what was above the last view to leave.
    @Test("A write to a class property no drawn view holds redraws what was above the last view that held it")
    func writeToAnObjectNoViewHoldsRedrawsAboveItsLastHolder() {
        let tui = TUIContext()
        let taps = StateTaps()
        let counter = Passed(object: Counter())
        let view = { (showsDetail: Bool) in MemoDetailOrSummary(showsDetail: showsDetail, counter: counter, taps: taps) }
        #expect(frame(view(true), tui, height: 1) == ["detail 0"])
        #expect(frame(view(false), tui, height: 1) == ["summary 0"])
        #expect(frame(view(false), tui, height: 1) == ["summary 0"])
        counter.object.count = 4
        #expect(frame(view(false), tui, height: 1) == ["summary 4"])
    }
}
