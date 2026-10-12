//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyObjectTests.swift
//
//  What the property walk does with what a class property holds: its
//  `@State`, `@Environment` and nested properties belong to the first view
//  in each render pass that reaches the object, so views sharing one object
//  share one state, and an object made anew with each view value keeps its
//  state (decisions-DYNVFIX B-DYNVFIX-3). SwiftUI installs nothing inside a
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

@MainActor
@Suite("DynamicProperty objects")
struct DynamicPropertyObjectTests {

    private func lines<V: View>(_ view: V, context: RenderContext) -> [String] {
        renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    /// The walks bound the `@State` inside a class instance to each holding
    /// view's storage in turn, through the one backing the instance holds,
    /// so the last view drawn won: a write through view a's binding landed
    /// in view b's state and not in a's (drawn `["a 0", "b 5"]`). SwiftUI
    /// installs no property inside a class (op.out, case vii-f: the binding
    /// is a constant, with a run-time warning), so the write changes
    /// nothing. TUIkit keeps binding what an object holds, by the first view
    /// in each render pass that reaches it: one object, one state, which
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
    /// resolves it to the environment of the first view that reaches it.
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
}
