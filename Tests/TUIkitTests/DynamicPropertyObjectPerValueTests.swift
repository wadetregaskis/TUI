//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyObjectPerValueTests.swift
//
//  An object made with each value of the view that holds it (session notes
//  DYNV2/notes.md §4.11) is told from one made before by when its `@State`
//  was made: each `@State` notes the render pass it was made in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What each body hands out.
@MainActor
private final class PassTaps {
    /// The pass each `@State` a body made noted, in the order made.
    var made: [UInt32] = []
}

/// The render pass the `@State` `state` noted when it was made
/// (`StateBacking.createdIn`), read through its private backing.
private func createdIn<Value>(_ state: State<Value>) -> UInt32? {
    (Mirror(reflecting: state).descendant("backing") as? StateBacking<Value>)?.createdIn
}

/// A view whose body makes a `@State`, as a view value made there makes
/// one, and notes the pass it noted.
private struct StateMakingView: View {
    let taps: PassTaps

    var body: some View {
        taps.made.append(createdIn(State(wrappedValue: 0)) ?? .max)
        return Text(verbatim: "made")
    }
}

@MainActor
@Suite("DynamicProperty objects made with a view value")
struct DynamicPropertyObjectPerValueTests {

    /// One frame as the render loop draws it: invalidations drained, the pass
    /// begun, the view made and drawn in it (`StateStorage.inRenderPass(_:)`),
    /// what was not drawn pruned.
    @discardableResult
    private func frame<V: View>(_ view: @autoclosure () -> V, _ tui: TUIContext, height: Int = 1) -> [String] {
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

    /// What an object made with a view value is told by (lane DYNVCLAIM): a
    /// `@State` made in a frame notes that frame's pass, each frame its own;
    /// one made outside every frame, `0`.
    @Test("A @State made in a frame notes the frame's render pass, and one made outside every frame notes none")
    func stateNotesTheRenderPassItWasMadeIn() {
        let tui = TUIContext()
        let taps = PassTaps()
        frame(StateMakingView(taps: taps), tui)
        let first = tui.stateStorage.currentPass
        frame(StateMakingView(taps: taps), tui)
        let second = tui.stateStorage.currentPass
        #expect(first != 0)
        #expect(second != first)
        #expect(taps.made == [first, second])
        #expect(createdIn(State(wrappedValue: 0)) == 0, "made outside every frame")
    }

    /// A render no pass is bound around makes every `@State` note `0`, as
    /// one made in an event handler does: such a render takes every object
    /// for one made before it.
    @Test("A @State made in a render no pass is bound around notes no pass")
    func stateMadeInAnUnboundRenderNotesNoPass() {
        let tui = TUIContext()
        let taps = PassTaps()
        tui.stateStorage.beginRenderPass()
        _ = renderToBuffer(
            StateMakingView(taps: taps), context: RenderContext(availableWidth: 20, availableHeight: 1, tuiContext: tui))
        tui.stateStorage.endRenderPass()
        #expect(taps.made == [0])
    }

    /// The serial is the process's, not the storage's: a pass of one context
    /// is never another's, so a `@State` made in one context's frame is never
    /// taken for one made in another's.
    @Test("Two contexts' render passes never share a serial")
    func twoContextsNeverShareAPass() {
        let one = TUIContext()
        let other = TUIContext()
        var seen: Set<UInt32> = []
        for _ in 0..<3 {
            one.stateStorage.beginRenderPass()
            other.stateStorage.beginRenderPass()
            seen.insert(one.stateStorage.currentPass)
            seen.insert(other.stateStorage.currentPass)
            let made = one.stateStorage.inRenderPass { createdIn(State(wrappedValue: 0)) }
            #expect(made == one.stateStorage.currentPass)
            #expect(made != other.stateStorage.currentPass)
            one.stateStorage.endRenderPass()
            other.stateStorage.endRenderPass()
        }
        #expect(seen.count == 6)
        #expect(!seen.contains(0))
    }

    // MARK: - Objects made with a view value

    /// The action closure of the last frame — a `Button`'s, which the focus
    /// ring keeps through the next frame's walk — holds the object the last
    /// view value made, so that object is alive when the next value's is
    /// first walked. The new object still takes the place's state: whether
    /// the old one is alive says nothing (lane DYNVCLAIM's design, F1).
    @Test("An object made with each view value keeps its @State while a closure holds the last value's object")
    func perValueObjectKeepsStateWhileAClosureHoldsTheOldOne() {
        let tui = TUIContext()
        let taps = PagerTaps()
        #expect(frame(ClosurePagerView(taps: taps), tui) == ["page 0"])
        taps.actions.last?()
        #expect(frame(ClosurePagerView(taps: taps), tui) == ["page 1"])
        taps.actions.last?()
        #expect(frame(ClosurePagerView(taps: taps), tui) == ["page 2"])
        // The first frame's object, still alive in its closure, writes the
        // place's state too.
        taps.actions.first?()
        #expect(frame(ClosurePagerView(taps: taps), tui) == ["page 3"])
    }

    /// The same through a real `Button`, pressed with Return: its action is
    /// the one the focus ring kept from the last frame.
    @Test("An object made with each view value keeps its @State when a Button's action, kept by the focus ring, writes it")
    func perValueObjectKeepsStateThroughAButtonsAction() {
        let harness = InputChainHarness(width: 20, height: 3)
        let shown = { harness.frame(ButtonPagerView()).lines.map(\.stripped).joined(separator: "|") }
        #expect(shown().contains("page 0"))
        #expect(shown().contains("page 0"))
        harness.press(KeyEvent(key: .enter))
        #expect(shown().contains("page 1"), "\(shown())")
        harness.press(KeyEvent(key: .enter))
        #expect(shown().contains("page 2"), "\(shown())")
    }

    /// An object made with each view value reads an observable model from
    /// the environment: every holder walks it before its body.
    @Test("An object made with each view value reads an @Environment model and keeps its @State")
    func perValueObjectReadsAnEnvironmentModel() {
        let tui = TUIContext()
        let taps = PagerTaps()
        let model = PagerModel()
        #expect(frame(ModelPagerView(taps: taps).environment(model), tui) == ["model 0"])
        taps.page?.wrappedValue = 4
        #expect(frame(ModelPagerView(taps: taps).environment(model), tui) == ["model 4"])
    }

    /// An object made on demand in a body and kept is made in one pass and
    /// shown in later ones: once shown long-lived at its place, the next
    /// object made there is not taken for its successor, and starts at its
    /// default. Under the claim, it bound the box its holder's key kept —
    /// the first object's.
    @Test("Objects made on demand at one place, one after another, never take each other's @State")
    func lazilyMadeObjectsAtOnePlaceDoNotInheritEachOthersState() {
        let tui = TUIContext()
        let taps = PagerTaps()
        let store = LazyPagers()
        #expect(frame(LazyPagerParent(store: store, key: 0, taps: taps), tui) == ["page 0"])
        taps.page?.wrappedValue = 5
        #expect(frame(LazyPagerParent(store: store, key: 0, taps: taps), tui) == ["page 5"])
        #expect(frame(LazyPagerParent(store: store, key: 1, taps: taps), tui) == ["page 0"])
        #expect(frame(LazyPagerParent(store: store, key: 0, taps: taps), tui) == ["page 5"])
    }

    /// An object made on demand in a body, first shown in the pass it was
    /// made in, looks made with the view's value: the next object made at its
    /// place takes the place's state, which is the first one's box (design
    /// §8.5, decisions-DYNVCLAIM B-DYNVCLAIM-3). The two shared it, so what
    /// the second wrote was the first's when it was shown again (review1 of
    /// lane DYNVCLAIM, a7d1f8e75). The first keeps what it held when the
    /// second took the place's state.
    @Test("An object made on demand keeps its own @State after the next one made at its place took that place's")
    func lazilyMadeObjectKeepsItsStateFromTheNextOneAtItsPlace() {
        let tui = TUIContext()
        let taps = PagerTaps()
        let store = LazyPagers()
        #expect(frame(LazyPagerParent(store: store, key: 0, taps: taps), tui) == ["page 0"])
        taps.page?.wrappedValue = 5
        // Taken for the next object made with the view's value: it starts
        // where the place's state is.
        #expect(frame(LazyPagerParent(store: store, key: 1, taps: taps), tui) == ["page 5"])
        taps.page?.wrappedValue = 7
        #expect(frame(LazyPagerParent(store: store, key: 0, taps: taps), tui) == ["page 5"])
        #expect(frame(LazyPagerParent(store: store, key: 1, taps: taps), tui) == ["page 7"])
        taps.page?.wrappedValue = 8
        #expect(frame(LazyPagerParent(store: store, key: 0, taps: taps), tui) == ["page 5"])
        #expect(frame(LazyPagerParent(store: store, key: 1, taps: taps), tui) == ["page 8"])
    }

    /// What an object made with a view value leaves its live predecessor
    /// (B-DYNVCLAIM-3) is kept on the predecessor's hub until a walk takes it
    /// back. Kept sunk to that hub, it held the hub that held it: every pass
    /// that made the view value anew while the last one lived — a `Button`'s
    /// action, kept by the focus ring, keeps it so — leaked a hub and a box
    /// per `@State`, with their values (review2 of lane DYNVCLAIM, d29a46eaf).
    ///
    /// The hub table is keyed by the object's address, and the hub of a pager
    /// made at a freed pager's address takes that one's entry, which frees
    /// its hub. Left to the allocator, which hands a few addresses round, the
    /// table held a dozen entries at most over the 81 frames, never the 65
    /// the first sweep waits for, and whether the first hub went said only
    /// whether a later pager landed at the first one's address: it stayed in
    /// 12 runs of 20. Here every pager's memory is kept (``PagerMemory``), so
    /// each has an address of its own, and the first hub can go only by the
    /// sweep.
    @Test("The hub of an object made with a view value goes once the object has, after the next one took its place's state")
    func perValueObjectsHubGoesAfterTheNextOneTookItsPlace() {
        let tui = TUIContext()
        let taps = PagerTaps()
        var memories: [PagerMemory] = []
        func pagerView() -> ClosurePagerView {
            let view = ClosurePagerView(taps: taps)
            memories.append(PagerMemory(pager: view.pager))
            return view
        }
        frame(pagerView(), tui)
        weak let firstHub = tui.stateStorage.objectHubs.values.first
        #expect(firstHub != nil)
        // Each frame's object lives through the next frame's walk, as the
        // focus ring keeps a `Button`'s action, and is then let go: the
        // storage sweeps the hubs of objects that have gone at the end of the
        // pass that makes the 65th hub.
        for _ in 0..<80 {
            taps.actions = Array(taps.actions.suffix(1))
            frame(pagerView(), tui)
        }
        #expect(tui.stateStorage.objectHubsAfterSweep != 0, "the hub table was swept")
        #expect(firstHub == nil)
        // The storage is alive at the check, so the hub went by its sweep:
        // `tui` would otherwise end at its last use, taking every hub with it.
        withExtendedLifetime(tui) {}
    }

    /// The box an object made with a view value binds is its place's, kept
    /// under the first holder's key; its sink must be the object's hub, set
    /// after the storage stamps it, so a write redraws the second holder too
    /// — here one the memo serves, whose comparison ignores the object.
    @Test("A write to an object made with a view value redraws every view drawn holding it")
    func perValueObjectsWriteRedrawsItsSecondHolder() {
        let tui = TUIContext()
        let taps = PagerTaps()
        #expect(frame(SharedPagerParent(taps: taps), tui, height: 2) == ["a 0", "b 0"])
        taps.page?.wrappedValue = 4
        #expect(frame(SharedPagerParent(taps: taps), tui, height: 2) == ["a 4", "b 4"])
    }
}

// MARK: - Fixtures: objects made with a view value

/// What the views made with pagers hand out.
@MainActor
private final class PagerTaps {
    var actions: [() -> Void] = []
    var page: Binding<Int>?
}

/// A class app property made anew with every value of the view holding it.
private final class Pager: DynamicProperty {
    @State var page = 0

    func next() { page += 1 }
}

/// A pager's memory, not the pager: an `unowned` reference keeps the
/// allocation from being freed, and so its address from being given to a
/// pager made later, but not the pager alive. It is deinitialised when the
/// last strong reference goes, as it would be without this, and a `weak`
/// reference to it — its hub's — reads `nil` from then on.
private struct PagerMemory {
    unowned let pager: Pager
}

/// A view made with a pager of its own, whose body hands out a closure
/// holding the pager, as a `Button`'s action holds what it captures.
private struct ClosurePagerView: View {
    let taps: PagerTaps
    let pager = Pager()

    var body: some View {
        let pager = pager
        taps.actions.append { pager.next() }
        return Text(verbatim: "page \(pager.page)")
    }
}

/// A view made with a pager of its own, and a `Button` that turns it.
private struct ButtonPagerView: View {
    let pager = Pager()

    var body: some View {
        let pager = pager
        return VStack {
            Text(verbatim: "page \(pager.page)")
            Button("Next") { pager.next() }
        }
    }
}

/// An observable model a pager reads from the environment.
@Observable
private final class PagerModel {
    var name = "model"
}

/// A pager reading a model from the environment.
private final class ModelPager: DynamicProperty {
    @State var page = 0
    @Environment(PagerModel.self) var model
}

private struct ModelPagerView: View {
    let taps: PagerTaps
    let pager = ModelPager()

    var body: some View {
        taps.page = pager.$page
        return Text(verbatim: "\(pager.model.name) \(pager.page)")
    }
}

/// Pagers made on demand inside a body, and kept.
@MainActor
private final class LazyPagers {
    private var made: [Int: Pager] = [:]

    func pager(_ key: Int) -> Pager {
        if let pager = made[key] { return pager }
        let pager = Pager()
        made[key] = pager
        return pager
    }
}

/// The pager at `key`, made the first time it is shown, shown by one view.
private struct LazyPagerParent: View {
    let store: LazyPagers
    let key: Int
    let taps: PagerTaps

    var body: some View {
        PagerLine(name: nil, pager: store.pager(key), taps: taps)
    }
}

/// A view showing a pager, handing out a binding to its page.
private struct PagerLine: View {
    let name: String?
    let pager: Pager
    let taps: PagerTaps

    var body: some View {
        taps.page = pager.$page
        return Text(verbatim: name.map { "\($0) \(pager.page)" } ?? "page \(pager.page)")
    }
}

/// A view showing a pager, served from the memo while its name is
/// unchanged, whatever pager it is handed.
private struct MemoPagerLine: View, Equatable {
    let name: String
    let pager: Pager

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }

    var body: some View {
        Text(verbatim: "\(name) \(pager.page)")
    }
}

/// A pager made in the body, with each value of the view, and handed to two
/// views, the second memoised.
private struct SharedPagerParent: View {
    let taps: PagerTaps

    var body: some View {
        let pager = Pager()
        return VStack {
            PagerLine(name: "a", pager: pager, taps: taps)
            MemoPagerLine(name: "b", pager: pager).equatable()
        }
    }
}
