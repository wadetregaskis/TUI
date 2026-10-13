//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyObjectTests.swift
//
//  What the property walk does with what a class property holds: its
//  `@State`, `@Environment` and nested properties belong to one view, the
//  first drawn in each render pass that reaches the object, its state going
//  with it from view to view, so views sharing one object share one state,
//  and an object made anew with each view value keeps its state
//  (decisions-DYNVFIX B-DYNVFIX-3). SwiftUI installs nothing inside a
//  class (measured on macOS 15.8.1, SwiftUI 6.5.4: session notes
//  DYNP/optional/op.out, case vii-f); the walk did, per view, so one view's
//  writes landed in another's state (DYNV bugs 3 and 4, session notes
//  DYNV/notes.md).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What each body hands out, by the name of the view that handed it.
@MainActor
private final class Taps {
    var bindings: [String: Binding<Int>] = [:]
    var readers: [String: () -> String] = [:]
    var texts: [String: Binding<String>] = [:]
}

// MARK: - A class property shared by two views

private struct DiscoveryAccent: EnvironmentKey {
    static let defaultValue = "plain"
}

extension EnvironmentValues {
    fileprivate var discoveryAccent: String {
        get { self[DiscoveryAccent.self] }
        set { self[DiscoveryAccent.self] = newValue }
    }
}

/// A class app property holding a `@State`: one instance, handed to every
/// view that shows it. Nothing else in it, so what a view draws does not
/// depend on whether an `@Environment` inside it is resolved.
private final class SharedCounter: DynamicProperty {
    @State var count = 0
}

private struct CounterView: View {
    let name: String
    let counter: SharedCounter
    let taps: Taps

    var body: some View {
        taps.bindings[name] = counter.$count
        return Text(verbatim: "\(name) \(counter.count)")
    }
}

/// One counter, shown by two views.
private struct TwoCounterViews: View {
    let counter: SharedCounter
    let taps: Taps

    var body: some View {
        VStack {
            CounterView(name: "a", counter: counter, taps: taps)
            CounterView(name: "b", counter: counter, taps: taps)
        }
    }
}

/// A class app property holding an `@Environment`: one instance, handed to
/// every view that shows it.
private final class SharedObject: DynamicProperty {
    @Environment(\.discoveryAccent) var accent
}

private struct ObjectView: View {
    let name: String
    let object: SharedObject
    let taps: Taps

    var body: some View {
        let object = object
        taps.readers[name] = { object.accent }
        return Text(verbatim: "\(name) \(object.accent)")
    }
}

/// One object, shown by two views under different environments.
private struct TwoObjectViews: View {
    let object: SharedObject
    let taps: Taps

    var body: some View {
        VStack {
            ObjectView(name: "a", object: object, taps: taps)
                .environment(\.discoveryAccent, "red")
            ObjectView(name: "b", object: object, taps: taps)
                .environment(\.discoveryAccent, "blue")
        }
    }
}

/// A class app property made anew with every value of the view that holds
/// it, holding a `@State` and an `@Environment` (session notes
/// DYNV2/notes.md §4.11).
private final class Pager: DynamicProperty {
    @State var page = 0
    @Environment(\.discoveryAccent) var accent
}

private struct PagerView: View {
    let taps: Taps
    let pager = Pager()

    var body: some View {
        taps.bindings["page"] = pager.$page
        return Text(verbatim: "page \(pager.page) \(pager.accent)")
    }
}

/// An observable model a class property reads from the environment.
@Observable
private final class DiscoveryModel {
    var name = "model"
}

private final class ModelReader: DynamicProperty {
    @Environment(DiscoveryModel.self) var model
}

private struct ModelReaderView: View {
    let reader = ModelReader()

    var body: some View {
        Text(verbatim: reader.model.name)
    }
}

/// Holds a class property only weakly.
private struct WeakCounterView: View {
    weak var counter: SharedCounter?
    let taps: Taps

    var body: some View {
        if let counter { taps.bindings["weak"] = counter.$count }
        return Text(verbatim: "weak \(counter?.count ?? -1)")
    }
}

// MARK: - Claims across render passes

/// A class app property holding a draft's text, shared by the two
/// candidates of a `ViewThatFits`.
private final class Draft: DynamicProperty {
    @State var text = ""
}

/// A candidate showing the draft, `wide` enough not to fit, or not.
private struct DraftView: View {
    let name: String
    let wide: Bool
    let draft: Draft
    let taps: Taps

    var body: some View {
        taps.texts[name] = draft.$text
        let padding = wide ? String(repeating: "-", count: 40) : ""
        return Text(verbatim: "\(name) \(draft.text)\(padding)")
    }
}

/// A class property passed through a view that does not hold it as one, so
/// the views it is handed to are the first to reach it.
private struct Handed<Object: AnyObject> {
    let object: Object
}

/// The wide candidate, measured and never drawn on a narrow terminal, ahead
/// of the narrow one.
private struct DraftCandidates: View {
    let draft: Handed<Draft>
    let taps: Taps

    var body: some View {
        ViewThatFits {
            DraftView(name: "wide", wide: true, draft: draft.object, taps: taps)
            DraftView(name: "narrow", wide: false, draft: draft.object, taps: taps)
        }
    }
}

/// A row's name, and the frame it is drawn in, so that no frame serves the
/// row from the memo.
private struct TickedRow: Identifiable, Equatable {
    let id: String
    let tick: Int
}

/// `CounterView` with the frame it is drawn in.
private struct TickedCounterView: View {
    let row: TickedRow
    let counter: SharedCounter
    let taps: Taps

    var body: some View {
        taps.bindings[row.id] = counter.$count
        return Text(verbatim: "\(row.id) \(counter.count)")
    }
}

/// The counter shown by a row per name.
private struct CounterRows: View {
    let rows: [TickedRow]
    let counter: Handed<SharedCounter>
    let taps: Taps

    var body: some View {
        VStack {
            ForEach(rows) { row in
                TickedCounterView(row: row, counter: counter.object, taps: taps)
            }
        }
    }
}

/// `CounterView` as a memoised row: equal while its name is.
private struct MemoCounterView: View, Equatable {
    let name: String
    let counter: SharedCounter
    let taps: Taps

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }

    var body: some View {
        taps.bindings[name] = counter.$count
        return Text(verbatim: "\(name) \(counter.count)")
    }
}

/// One counter, shown first by a memoised view and then by one drawn every
/// frame.
private struct MemoFirstCounterViews: View {
    let counter: Handed<SharedCounter>
    let taps: Taps

    var body: some View {
        VStack {
            MemoCounterView(name: "a", counter: counter.object, taps: taps).equatable()
            CounterView(name: "b", counter: counter.object, taps: taps)
        }
    }
}

// MARK: - An enum in an object's storage

/// A class app property holding an enum property: its field lies in the
/// object's storage, which anything holding the object can read.
private final class ModeOwner: DynamicProperty {
    var mode: Mode

    init(_ mode: Mode) {
        self.mode = mode
    }
}

/// An enum property with two payload cases whose payload holds a reference,
/// so its case lies in the reference's spare bits.
private enum Mode: DynamicProperty {
    case first(ModePayload)
    case second(ModePayload)
}

private struct ModePayload: DynamicProperty {
    let reader: ModeReader
}

/// A class property inside the enum's payload, whose `update()` reads the
/// enum back through its owner.
private final class ModeReader: DynamicProperty {
    weak var owner: ModeOwner?
    var seen = "nothing"

    func update() {
        guard let owner else { return }
        switch owner.mode {
        case .first: seen = "first"
        case .second: seen = "second"
        }
    }
}

private struct ModeOwnerView: View {
    let owner: ModeOwner
    let reader: Handed<ModeReader>

    var body: some View {
        Text(verbatim: "seen \(reader.object.seen)")
    }
}

@MainActor
@Suite("DynamicProperty objects")
struct DynamicPropertyObjectTests {

    private func lines<V: View>(_ view: V, context: RenderContext) -> [String] {
        renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    /// One frame as the render loop draws it, its render cache the one its
    /// state's writes invalidate: invalidations drained, the pass begun, the
    /// view drawn, what was not drawn pruned.
    private func frame<V: View>(_ view: V, _ tui: TUIContext, width: Int = 20, height: Int = 2) -> [String] {
        let context = RenderContext(availableWidth: width, availableHeight: height, tuiContext: tui)
        tui.renderCache.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        defer {
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
        return lines(view, context: context)
    }

    /// The walks bound the `@State` inside a class instance to each holding
    /// view's storage in turn, through the one backing the instance holds,
    /// so the last view drawn won: a write through view a's binding landed
    /// in view b's state and not in a's (drawn `["a 0", "b 5"]`). SwiftUI
    /// installs no property inside a class (op.out, case vii-f: the binding
    /// is a constant, with a run-time warning), so the write changes
    /// nothing. TUIkit keeps binding what an object holds, by one view, the
    /// first drawn that reaches it: one object, one state, which
    /// both views read and write. What passes: a sees its own write, or b is
    /// untouched (a constant binding, as in SwiftUI).
    @Test("A write through one view's binding to a class property's @State never lands only in another view")
    func sharedObjectStateWrite() {
        let context = makeRenderContext(width: 20, height: 2)
        let taps = Taps()
        let counter = SharedCounter()
        #expect(lines(TwoCounterViews(counter: counter, taps: taps), context: context) == ["a 0", "b 0"])
        taps.bindings["a"]?.wrappedValue = 5
        let after = lines(TwoCounterViews(counter: counter, taps: taps), context: context)
        #expect(after.first == "a 5" || after.last == "b 0", "drawn: \(after)")
    }

    /// The same, as TUIkit keeps it: either view's write is the one state
    /// both views draw.
    @Test("Two views showing one class property share its @State, whichever writes it")
    func sharedObjectStateIsOne() {
        let context = makeRenderContext(width: 20, height: 2)
        let taps = Taps()
        let counter = SharedCounter()
        _ = lines(TwoCounterViews(counter: counter, taps: taps), context: context)
        taps.bindings["a"]?.wrappedValue = 5
        #expect(lines(TwoCounterViews(counter: counter, taps: taps), context: context) == ["a 5", "b 5"])
        taps.bindings["b"]?.wrappedValue = 7
        #expect(lines(TwoCounterViews(counter: counter, taps: taps), context: context) == ["a 7", "b 7"])
    }

    /// The same for an `@Environment` inside a class property: resolved into
    /// the instance's one box for each view in turn, so a closure made in
    /// view a's body read view b's environment. SwiftUI does not resolve it
    /// at all (op.out, case vii-f), so the closure reads the default. TUIkit
    /// resolves it to the environment of its claimant, the first view drawn
    /// that reaches it.
    @Test("A class property's @Environment read in a view's closure is never another view's environment")
    func sharedObjectEnvironmentInClosure() {
        let context = makeRenderContext(width: 20, height: 2)
        let taps = Taps()
        let object = SharedObject()
        _ = lines(TwoObjectViews(object: object, taps: taps), context: context)
        #expect(taps.readers["a"]?() != "blue", "view a sits under red")
    }

    /// A class property made anew with each value of the one view that holds
    /// it keeps its `@State` from frame to frame and reads its view's
    /// environment: what holds it is bound to that view's key, as before
    /// (session notes DYNV2/notes.md §4.11; SwiftUI installs neither).
    @Test("A class property made anew with each view value keeps its @State and reads its view's environment")
    func perValueObjectKeepsState() {
        let context = makeRenderContext(width: 30, height: 1)
        let taps = Taps()
        let view = { PagerView(taps: taps).environment(\.discoveryAccent, "red") }
        #expect(lines(view(), context: context) == ["page 0 red"])
        taps.bindings["page"]?.wrappedValue = 5
        #expect(lines(view(), context: context) == ["page 5 red"])
    }

    /// An `@Environment(Model.self)` inside a class property is resolved,
    /// so reading it does not trap for want of a model.
    @Test("A class property's @Environment of an observable type reads the model the view's environment holds")
    func objectReadsEnvironmentModel() {
        let context = makeRenderContext(width: 20, height: 1)
        #expect(lines(ModelReaderView().environment(DiscoveryModel()), context: context) == ["model"])
    }

    /// What a class property held `weak` holds is bound while it lives
    /// (decisions-DYNP A-DYNP-1): its `@State` is kept from frame to frame.
    @Test("A class property held weak has its @State bound while it lives")
    func weakObjectContentsAreBound() {
        let context = makeRenderContext(width: 20, height: 1)
        let taps = Taps()
        let counter = SharedCounter()
        #expect(lines(WeakCounterView(counter: counter, taps: taps), context: context) == ["weak 0"])
        taps.bindings["weak"]?.wrappedValue = 3
        #expect(lines(WeakCounterView(counter: counter, taps: taps), context: context) == ["weak 3"])
        withExtendedLifetime(counter) {}
    }

    /// A claim that lasted one render pass was taken by the first walk to
    /// reach the object, and a measure is a walk: the wide candidate, measured
    /// and never drawn, took it, bound the draft to its own key, and that key
    /// was pruned at the end of every pass, so what the narrow candidate's
    /// field wrote was gone by the next frame. A measure's claim is now only
    /// provisional: the candidate drawn takes it, and keeps it.
    @Test("A class property shared by a measured candidate and the drawn one keeps what the drawn one writes")
    func measuredHolderDoesNotKeepTheClaim() {
        let tui = TUIContext()
        let taps = Taps()
        let draft = Draft()
        #expect(frame(DraftCandidates(draft: Handed(object: draft), taps: taps), tui) == ["narrow"])
        taps.texts["narrow"]?.wrappedValue = "hi"
        #expect(frame(DraftCandidates(draft: Handed(object: draft), taps: taps), tui) == ["narrow hi"])
        #expect(frame(DraftCandidates(draft: Handed(object: draft), taps: taps), tui) == ["narrow hi"])
    }

    /// The first view to reach the object was a memoised one; on a frame
    /// that served it from the memo, its walk did not run, and the next
    /// holder took a claim that lasted only the pass: the object's `@State`
    /// was bound to that holder's key, and it drew its own default. A claim
    /// now lasts while its claimant's state does, which a memo hit keeps.
    @Test("A class property's first holder served from the memo keeps its claim, and the next holder reads its state")
    func memoServedClaimantKeepsTheClaim() {
        let tui = TUIContext()
        let taps = Taps()
        let counter = SharedCounter()
        #expect(frame(MemoFirstCounterViews(counter: Handed(object: counter), taps: taps), tui) == ["a 0", "b 0"])
        taps.bindings["a"]?.wrappedValue = 5
        #expect(frame(MemoFirstCounterViews(counter: Handed(object: counter), taps: taps), tui) == ["a 5", "b 5"])
        #expect(frame(MemoFirstCounterViews(counter: Handed(object: counter), taps: taps), tui) == ["a 5", "b 5"])
    }

    /// The claim stayed with a claimant drawn in an earlier pass while it was
    /// only measured: on the frame the terminal narrowed, the narrow
    /// candidate drawn read the wide one's state, and what it wrote before
    /// the next frame went into the wide one's box, dropped with it at that
    /// frame's end; the next frame showed the default (review of 5af4853ba,
    /// 2026-10-12). The view drawn takes the claim in the pass it is drawn
    /// in, and the object's state with it.
    @Test("A class property whose drawn holder changes on a resize keeps its @State and what the new holder writes")
    func holderChangeOnResizeKeepsTheState() {
        let tui = TUIContext()
        let taps = Taps()
        let draft = Draft()
        let view = { DraftCandidates(draft: Handed(object: draft), taps: taps) }
        #expect(frame(view(), tui, width: 80).first?.hasPrefix("wide -") == true)
        taps.texts["wide"]?.wrappedValue = "abc"
        #expect(frame(view(), tui, width: 80).first?.hasPrefix("wide abc-") == true)
        #expect(frame(view(), tui) == ["narrow abc"])
        taps.texts["narrow"]?.wrappedValue = "abcd"
        #expect(frame(view(), tui) == ["narrow abcd"])
        #expect(frame(view(), tui) == ["narrow abcd"])
    }

    /// The same when the claimant's row is removed: the row left drew the
    /// removed row's state for a frame, and lost what it wrote then.
    @Test("A class property whose claimant's row is removed keeps its @State in the row left")
    func claimantRowRemovedKeepsTheState() {
        let tui = TUIContext()
        let taps = Taps()
        let counter = SharedCounter()
        var tick = 0
        let rows = { (names: [String]) -> CounterRows in
            tick += 1
            let rows = names.map { TickedRow(id: $0, tick: tick) }
            return CounterRows(rows: rows, counter: Handed(object: counter), taps: taps)
        }
        #expect(frame(rows(["a", "b"]), tui) == ["a 0", "b 0"])
        taps.bindings["a"]?.wrappedValue = 5
        #expect(frame(rows(["a", "b"]), tui) == ["a 5", "b 5"])
        #expect(frame(rows(["b"]), tui, height: 1) == ["b 5"])
        taps.bindings["b"]?.wrappedValue = 7
        #expect(frame(rows(["b"]), tui, height: 1) == ["b 7"])
    }

    /// An enum's payload was projected out of the enum where it lay, inside
    /// the object's storage, and its properties updated before the case was
    /// put back: an `update()` there that read the enum through the object
    /// saw it with its case cleared from the payload's spare bits, the first
    /// case. Inside an object, the enum is walked on a copy and assigned back.
    @Test("An update() inside an enum held by a class property reads the enum's own case through the object")
    func enumInObjectStorageKeepsItsCase() {
        let context = makeRenderContext(width: 20, height: 1)
        let reader = ModeReader()
        let owner = ModeOwner(.second(ModePayload(reader: reader)))
        reader.owner = owner
        #expect(lines(ModeOwnerView(owner: owner, reader: Handed(object: reader)), context: context) == ["seen second"])
    }

    /// A pass that walks the tree twice — a geometry reader's correction, the
    /// first frame's walk for the window chrome — walked an object's
    /// contents on its first walk only, so a closure made in the drawn walk
    /// read the environment of the walk thrown away. The claimant walks them
    /// on every walk of its own, and the last decides.
    @Test("A class property's @Environment is the one of its claimant's last walk in a pass")
    func lastWalkInAPassResolvesTheObject() {
        let tui = TUIContext()
        let taps = Taps()
        let object = SharedObject()
        let context = RenderContext(availableWidth: 20, availableHeight: 1, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        _ = lines(ObjectView(name: "a", object: object, taps: taps).environment(\.discoveryAccent, "red"), context: context)
        _ = lines(ObjectView(name: "a", object: object, taps: taps).environment(\.discoveryAccent, "blue"), context: context)
        tui.stateStorage.endRenderPass()
        #expect(taps.readers["a"]?() == "blue")
    }
}
