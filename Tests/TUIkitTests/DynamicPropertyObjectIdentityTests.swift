//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyObjectIdentityTests.swift
//
//  What views holding a class property change, and what they never do: a
//  holder whose identity changes leaves the app idle, a measure stores
//  nothing for the object, the object's ids are its own whichever view
//  draws it, and a weak holder's object may go (decisions-DYNVFIX
//  B-DYNVFIX-3 and B-DYNVFIX-5, lane DYNVCLAIM).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What each body hands out, by the name of the view that handed it.
@MainActor
private final class IdentityTaps {
    var counts: [String: Binding<Int>] = [:]
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
    let taps: IdentityTaps

    var body: some View {
        taps.counts[name] = counter.$count
        return Text(verbatim: "\(name) \(counter.count)")
    }
}

/// A view holding a counter under an identity new every frame.
private struct ChangingIdentityRow: View {
    let counter: Passed<Counter>
    let taps: IdentityTaps

    var body: some View {
        VStack {
            CounterRow(name: "row", counter: counter.object, taps: taps).id(UUID())
        }
    }
}

/// A view showing a counter, held without being drawn: what a measure
/// reaches.
private struct MeasuredCounter: View {
    let counter: Counter

    var body: some View {
        Text(verbatim: "measured \(counter.count)")
    }
}

/// A class app property holding a namespace and a `@State`.
private final class Scoped: DynamicProperty {
    @Namespace var space
    @State var count = 0
}

/// A view showing an object's namespace, noting it.
private struct ScopedView: View {
    let name: String
    let scoped: Scoped
    let log: NamespaceLog

    var body: some View {
        log.ids[name, default: []].append(scoped.space)
        return Text(verbatim: name)
    }
}

/// Holds a class property only weakly.
private struct WeakCounterRow: View {
    weak var counter: Counter?
    let taps: IdentityTaps

    var body: some View {
        if let counter { taps.counts["weak"] = counter.$count }
        return Text(verbatim: "weak \(counter?.count ?? -1)")
    }
}

/// One counter, shown by a view in each of two tabs.
private struct TabbedCounters: View {
    let tab: Int
    let counter: Passed<Counter>
    let taps: IdentityTaps

    var body: some View {
        TabView(selection: .constant(tab)) {
            Tab("One", value: 0) { CounterRow(name: "one", counter: counter.object, taps: taps) }
            Tab("Two", value: 1) { CounterRow(name: "two", counter: counter.object, taps: taps) }
        }
    }
}

/// The namespaces each view read, in the order read.
@MainActor
private final class NamespaceLog {
    var ids: [String: [Namespace.ID]] = [:]
}

/// The object at `selection`, shown by one view.
private struct ScopedSelection: View {
    let objects: [Scoped]
    let selection: Int
    let log: NamespaceLog

    var body: some View {
        ScopedView(name: "detail", scoped: objects[selection], log: log)
    }
}

/// One object shown by two views, the first of which can be removed.
private struct ScopedPair: View {
    let showsFirst: Bool
    let scoped: Passed<Scoped>
    let log: NamespaceLog

    var body: some View {
        VStack {
            if showsFirst { ScopedView(name: "a", scoped: scoped.object, log: log) }
            ScopedView(name: "b", scoped: scoped.object, log: log)
        }
    }
}

/// Objects made on demand, the first time each is asked for, and kept.
@MainActor
private final class ScopedStore {
    private var made: [Int: Scoped] = [:]
    private var pair: [Scoped]?

    func scoped(_ key: Int) -> Scoped {
        if let scoped = made[key] { return scoped }
        let scoped = Scoped()
        made[key] = scoped
        return scoped
    }

    /// Two objects made together, the first time they are asked for.
    func both() -> [Scoped] {
        if let pair { return pair }
        let made = [Scoped(), Scoped()]
        pair = made
        return made
    }
}

/// The object at `key`, made the first time it is shown, shown by one view.
private struct LazyScopedParent: View {
    let store: ScopedStore
    let key: Int
    let log: NamespaceLog

    var body: some View {
        ScopedView(name: "detail", scoped: store.scoped(key), log: log)
    }
}

@MainActor
@Suite("DynamicProperty objects' holders and ids")
struct DynamicPropertyObjectIdentityTests {

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

    // MARK: - Idle, measures, ids

    /// Each frame a new holder, under a new identity, registers on the object
    /// and the old one is pruned: nothing is written, so nothing asks for a
    /// frame, and the object's state is kept (review4 of DYNVFIX,
    /// deac1c31f(3)).
    @Test("A holder under an identity new every frame leaves the app idle and keeps the object's @State")
    func holderUnderChangingIDStaysIdle() {
        let tui = TUIContext()
        let taps = IdentityTaps()
        let counter = Passed(object: Counter())
        _ = frame(ChangingIdentityRow(counter: counter, taps: taps), tui, height: 1)
        taps.counts["row"]?.wrappedValue = 4
        for _ in 0..<4 {
            #expect(frame(ChangingIdentityRow(counter: counter, taps: taps), tui, height: 1) == ["row 4"])
        }
        #expect(isIdle(tui), "a frame with nothing written asks for none")
    }

    /// A measure took a provisional claim and bound the object's `@State`
    /// under the measured view's key, creating its box (review5 of
    /// DYNVFIX). A measure makes nothing a view's key holds for an object.
    @Test("A measure of a view holding a class property stores nothing for it")
    func measureMakesNothingForAnObject() {
        let tui = TUIContext()
        let counter = Counter()
        let context = RenderContext(availableWidth: 20, availableHeight: 1, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        let stored = tui.stateStorage.count
        let size = tui.stateStorage.inRenderPass {
            measureChild(MeasuredCounter(counter: counter), proposal: .unspecified, context: context)
        }
        #expect(size.width == "measured 0".count)
        #expect(tui.stateStorage.count == stored)
        #expect(tui.stateStorage.objectHubs.isEmpty)
        tui.stateStorage.endRenderPass()
    }

    /// The ids inside an object were bound from its claimant's path, so two
    /// objects shown one after the other by one view shared them (B-DYNVFIX-5
    /// class). Each object's are its own.
    @Test("Two objects shown one after the other by one view get distinct namespaces")
    func twoObjectsSeenByOneViewGetDistinctNamespaceIDs() {
        let tui = TUIContext()
        let log = NamespaceLog()
        let objects = [Scoped(), Scoped()]
        _ = frame(ScopedSelection(objects: objects, selection: 0, log: log), tui, height: 1)
        _ = frame(ScopedSelection(objects: objects, selection: 1, log: log), tui, height: 1)
        _ = frame(ScopedSelection(objects: objects, selection: 0, log: log), tui, height: 1)
        let ids = log.ids["detail"] ?? []
        #expect(ids.count == 3)
        #expect(ids.first != ids.dropFirst().first, "\(ids)")
        #expect(ids.first == ids.last, "\(ids)")
    }

    /// Two objects made in the first frame, where the first is shown: it
    /// looks made with the view's value, so the second, shown next by the
    /// same view, took its ids for good, though it was made before the pass
    /// that first walks it (review1 of lane DYNVCLAIM, a7d1f8e75 (a)). An
    /// object made before the pass that walks it has ids of its own.
    @Test("An object made in an earlier frame, shown after one made with it, gets a namespace of its own")
    func objectMadeEarlierGetsItsOwnNamespaceAfterAChain() {
        let tui = TUIContext()
        let log = NamespaceLog()
        let store = ScopedStore()
        _ = frame(ScopedSelection(objects: store.both(), selection: 0, log: log), tui, height: 1)
        _ = frame(ScopedSelection(objects: store.both(), selection: 1, log: log), tui, height: 1)
        _ = frame(ScopedSelection(objects: store.both(), selection: 1, log: log), tui, height: 1)
        _ = frame(ScopedSelection(objects: store.both(), selection: 0, log: log), tui, height: 1)
        let ids = log.ids["detail"] ?? []
        #expect(ids.count == 4)
        #expect(ids[1] != ids[0], "\(ids)")
        #expect(ids[2] == ids[1], "\(ids)")
        #expect(ids[3] == ids[0], "\(ids)")
    }

    /// An object made on demand and first shown in the pass it was made in
    /// looks made with the view's value, so it takes the ids of the chain at
    /// its place — the object shown there before (decisions-DYNVCLAIM
    /// B-DYNVCLAIM-1). They were its for good, though the next walk found it
    /// outlived its pass (review1 of lane DYNVCLAIM, ac4bf0644). Then it gets
    /// ids of its own.
    @Test("An object made on demand takes ids of its own once it outlives the pass it was made in")
    func lazilyMadeObjectTakesItsOwnNamespaceOnceItOutlivesItsPass() {
        let tui = TUIContext()
        let log = NamespaceLog()
        let store = ScopedStore()
        for key in [0, 1, 1, 0, 1] {
            _ = frame(LazyScopedParent(store: store, key: key, log: log), tui, height: 1)
        }
        let ids = log.ids["detail"] ?? []
        #expect(ids.count == 5)
        #expect(ids[1] == ids[0], "taken for the chain's next object: \(ids)")
        #expect(ids[2] != ids[0], "its own once it outlived its pass: \(ids)")
        #expect(ids[3] == ids[0], "\(ids)")
        #expect(ids[4] == ids[2], "\(ids)")
    }

    /// The ids followed the claimant: when the first view holding the object
    /// left, they changed to the next one's path.
    @Test("An object's namespace stays the same when the first view holding it leaves")
    func objectIDsStableWhenItsFirstHolderLeaves() {
        let tui = TUIContext()
        let log = NamespaceLog()
        let scoped = Passed(object: Scoped())
        // What each view's drawn body read: its last read in the frame, after
        // the stack's measure. (A measure made before any render walk reached
        // the object binds no ids, so the first frame's measure reads an
        // unbound one.)
        var drawn: [Namespace.ID?] = []
        _ = frame(ScopedPair(showsFirst: true, scoped: scoped, log: log), tui, height: 2)
        drawn += [log.ids["a"]?.last, log.ids["b"]?.last]
        for _ in 0..<2 {
            log.ids.removeAll()
            _ = frame(ScopedPair(showsFirst: false, scoped: scoped, log: log), tui, height: 2)
            drawn.append(log.ids["b"]?.last)
        }
        #expect(!drawn.contains(nil))
        #expect(Set(drawn).count == 1, "\(drawn)")
    }

    // MARK: - Holders that change or let go

    /// The object a view held `weak` goes between frames: the field reads
    /// `nil`, and nothing the walk keeps reaches it (decisions-DYNP
    /// A-DYNP-1).
    @Test("A class property held weak whose object goes between frames reads nil, and nothing traps")
    func weakObjectThatGoesBetweenFramesReadsNil() {
        let tui = TUIContext()
        let taps = IdentityTaps()
        var counter: Counter? = Counter()
        #expect(frame(WeakCounterRow(counter: counter, taps: taps), tui, height: 1) == ["weak 0"])
        taps.counts["weak"]?.wrappedValue = 3
        #expect(frame(WeakCounterRow(counter: counter, taps: taps), tui, height: 1) == ["weak 3"])
        counter = nil
        #expect(frame(WeakCounterRow(counter: counter, taps: taps), tui, height: 1) == ["weak -1"])
        #expect(frame(WeakCounterRow(counter: counter, taps: taps), tui, height: 1) == ["weak -1"])
    }

    /// The tab shown changes the view holding the object: the object's state
    /// is its own, so the new tab's view reads it, and what it writes the
    /// first tab's reads in turn.
    @Test("A class property shown by two tabs keeps its @State as the tab changes")
    func tabSwitchKeepsTheObjectsState() {
        let tui = TUIContext()
        let taps = IdentityTaps()
        let counter = Passed(object: Counter())
        let shown = { (tab: Int) in frame(TabbedCounters(tab: tab, counter: counter, taps: taps), tui, height: 4).joined() }
        #expect(shown(0).contains("one 0"))
        taps.counts["one"]?.wrappedValue = 6
        #expect(shown(0).contains("one 6"))
        #expect(shown(1).contains("two 6"))
        taps.counts["two"]?.wrappedValue = 7
        #expect(shown(1).contains("two 7"))
        #expect(shown(0).contains("one 7"))
    }
}
