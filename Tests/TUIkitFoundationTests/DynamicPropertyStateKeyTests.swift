//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyStateKeyTests.swift
//
//  A `@State` nested in an app's `DynamicProperty` is keyed by the next index
//  of its view's one state counter, in `Mirror` order. A property whose
//  presence depends on the view's VALUE — an optional, an existential, an
//  enum's payload — then moves the keys of everything after it from one
//  value to the next. These tests change only that value, at one identity,
//  and ask whether each `@State` keeps its own value
//  (`Tools/SwiftUIProbes/Dynamic property discovery/notes.md` §5.5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// An app property holding one `@State`, starting at 100.
private struct Full: DynamicProperty {
    @State private var kept = 100

    var value: Int { kept }
    var binding: Binding<Int> { $kept }
}

/// An app property holding nothing to bind.
private struct Empty: DynamicProperty {}

/// An app property holding two `@State`s, starting at 1 and 2.
private struct Pair: DynamicProperty {
    @State private var first = 1
    @State private var second = 2

    var values: String { "\(first) \(second)" }
}

/// What each body hands out, so a test can write a view's state between
/// frames.
@MainActor
private final class StateTap {
    var x: Binding<Int>?
    var kept: Binding<Int>?
}

/// An optional app property declared before the view's own `@State`.
private struct OptionalFullView: View {
    let tap: StateTap
    let p: Full?
    @State private var x = 0

    var body: some View {
        tap.x = $x
        tap.kept = p?.binding
        return Text(verbatim: "x \(x) kept \(p.map { String($0.value) } ?? "-")")
    }
}

/// Holds `OptionalFullView` at one child identity, and decides from its own
/// `@State` whether to give it a property — as an app would.
private struct OptionalFullParent: View {
    let tap: StateTap
    let showTap: ShowTap
    @State private var show = false

    var body: some View {
        showTap.show = $show
        return OptionalFullView(tap: tap, p: show ? Full() : nil)
    }
}

@MainActor
private final class ShowTap {
    var show: Binding<Bool>?
}

/// An existential app property declared before the view's own `@State`.
private struct ExistentialView: View {
    let tap: StateTap
    let p: any DynamicProperty
    @State private var x = 0

    var body: some View {
        tap.x = $x
        let kept = (p as? Full).map { String($0.value) } ?? "-"
        return Text(verbatim: "x \(x) kept \(kept)")
    }
}

/// `Full`, handing its binding to a tap of its own, so an enum case can hold
/// it as its one payload value.
private struct TappedFull: DynamicProperty {
    let tap: StateTap
    @State private var kept = 100

    /// Main-actor isolated, as the `body` that reads it is: the tap is.
    @MainActor var value: Int {
        tap.kept = $kept
        return kept
    }
}

/// A view that is an enum, its cases holding different numbers of `@State`,
/// each case's payload one value.
private enum Screen: View {
    case one(TappedFull)
    case two(Pair)

    var body: some View {
        switch self {
        case .one(let full): Text(verbatim: "one \(full.value)")
        case .two(let pair): Text(verbatim: "two \(pair.values)")
        }
    }
}

/// A view that is an enum whose case holds an app property beside another
/// value: `Mirror` shows the payload as one child, a tuple.
private enum PairedScreen: View {
    case one(Full, StateTap)

    var body: some View {
        switch self {
        case let .one(full, tap):
            tap.kept = full.binding
            return Text(verbatim: "one \(full.value)")
        }
    }
}

/// An app property reading `isEnabled` from the environment.
private struct EnabledReader: DynamicProperty {
    @Environment(\.isEnabled) private var isEnabled

    var text: String { isEnabled ? "enabled" : "disabled" }
}

/// Counts the `update()` calls of the properties holding it.
@MainActor
private final class UpdateCounter {
    var updates = 0
}

/// An app property whose `update()` counts itself.
private struct Counting: DynamicProperty {
    let counter: UpdateCounter

    mutating func update() {
        MainActor.assumeIsolated { counter.updates += 1 }
    }
}

/// A view that is an enum whose case holds two app properties beside
/// another value.
private enum PairedPropertiesScreen: View {
    case one(EnabledReader, Counting, Int)

    var body: some View {
        switch self {
        case let .one(reader, _, _): Text(verbatim: reader.text)
        }
    }
}

/// A view that is an enum whose two cases hold the same property type.
private enum Twins: View {
    case left(TappedFull)
    case right(TappedFull)

    var body: some View {
        switch self {
        case .left(let full): Text(verbatim: "left \(full.value)")
        case .right(let full): Text(verbatim: "right \(full.value)")
        }
    }
}

/// An app property that is an enum, its cases holding different numbers of
/// `@State`.
private enum Phase: DynamicProperty {
    case one(TappedFull)
    case two(Pair)

    @MainActor var summary: String {
        switch self {
        case .one(let full): "one \(full.value)"
        case .two(let pair): "two \(pair.values)"
        }
    }
}

/// A view that is an enum whose case holds an optional app property, so the
/// case can come back holding nothing.
private enum OptionalScreen: View {
    case one(TappedFull?)
    case two

    var body: some View {
        switch self {
        case .one(let full): Text(verbatim: "one \(full.map { String($0.value) } ?? "-")")
        case .two: Text(verbatim: "two")
        }
    }
}

/// A view that is an enum whose case holds an existential app property, so
/// the case can come back holding another type.
private enum ExistentialScreen: View {
    case one(any DynamicProperty)
    case two

    var body: some View {
        switch self {
        case .one(let property): Text(verbatim: "one \((property as? TappedFull).map { String($0.value) } ?? "-")")
        case .two: Text(verbatim: "two")
        }
    }
}

/// A view that is an enum whose case holds an enum app property.
private enum NestedScreen: View {
    case outer(Phase)
    case other

    var body: some View {
        switch self {
        case .outer(let phase): Text(verbatim: phase.summary)
        case .other: Text(verbatim: "other")
        }
    }
}

/// An enum app property declared before the view's own `@State`.
private struct PhaseView: View {
    let tap: StateTap
    let phase: Phase
    @State private var x = 0

    var body: some View {
        tap.x = $x
        return Text(verbatim: "\(phase.summary) x \(x)")
    }
}

/// An app property with one `@State` of `Int`, whatever its type.
private protocol KeptHolder: DynamicProperty {
    var value: Int { get }
    var binding: Binding<Int> { get }
}

extension Full: KeptHolder {}

/// Another type than `Full`, its one `@State` of the same type at the same
/// place, starting at 200.
private struct OtherFull: KeptHolder {
    @State private var kept = 200

    var value: Int { kept }
    var binding: Binding<Int> { $kept }
}

/// An existential app property, whichever type it holds, declared before
/// the view's own `@State`.
private struct KeptHolderView: View {
    let tap: StateTap
    let p: any KeptHolder
    @State private var x = 0

    var body: some View {
        tap.x = $x
        tap.kept = p.binding
        return Text(verbatim: "x \(x) kept \(p.value)")
    }
}

/// An app property holding a `@FocusState`.
private struct FocusHolder: DynamicProperty {
    @FocusState private var inner: Bool

    /// The id the binding walk gave `inner`.
    var innerID: String { _inner.store.storeID }
}

/// An optional app property holding a `@FocusState`, declared before the
/// view's own.
private struct OptionalFocusView: View {
    let p: FocusHolder?
    @FocusState private var own: Bool

    /// The id the binding walk gave `own`.
    var ownID: String { _own.store.storeID }

    var body: some View { Text(verbatim: "") }
}

@MainActor
@Suite("DynamicProperty state keys")
struct DynamicPropertyStateKeyTests {

    private func line<V: View>(_ view: V, context: RenderContext) -> String {
        renderToBuffer(view, context: context).lines.first?.stripped
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    @Test("A view's @State keeps its value when an optional app property before it goes from nil to a value")
    func optionalPropertyArriving() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(OptionalFullView(tap: tap, p: nil), context: context) == "x 0 kept -")
        tap.x?.wrappedValue = 7
        #expect(line(OptionalFullView(tap: tap, p: nil), context: context) == "x 7 kept -")

        #expect(line(OptionalFullView(tap: tap, p: Full()), context: context) == "x 7 kept 100",
                "x keeps 7, and the property's own state starts at its own default")
    }

    @Test("A view's @State keeps its value when an optional app property before it goes from a value to nil")
    func optionalPropertyLeaving() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(OptionalFullView(tap: tap, p: Full()), context: context) == "x 0 kept 100")
        tap.x?.wrappedValue = 7
        tap.kept?.wrappedValue = 50
        #expect(line(OptionalFullView(tap: tap, p: Full()), context: context) == "x 7 kept 50")

        #expect(line(OptionalFullView(tap: tap, p: nil), context: context) == "x 7 kept -",
                "x keeps 7")
    }

    @Test("A parent's @State that gives its child an optional app property leaves the child's own @State alone")
    func optionalPropertyFromParentState() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        let showTap = ShowTap()
        #expect(line(OptionalFullParent(tap: tap, showTap: showTap), context: context) == "x 0 kept -")
        tap.x?.wrappedValue = 7
        #expect(line(OptionalFullParent(tap: tap, showTap: showTap), context: context) == "x 7 kept -")

        showTap.show?.wrappedValue = true
        #expect(line(OptionalFullParent(tap: tap, showTap: showTap), context: context) == "x 7 kept 100",
                "x keeps 7, and the property's own state starts at its own default")
    }

    @Test("A view's @State keeps its value when an existential app property before it changes type")
    func existentialPropertyChangingType() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(ExistentialView(tap: tap, p: Empty()), context: context) == "x 0 kept -")
        tap.x?.wrappedValue = 7
        #expect(line(ExistentialView(tap: tap, p: Empty()), context: context) == "x 7 kept -")

        #expect(line(ExistentialView(tap: tap, p: Full()), context: context) == "x 7 kept 100",
                "x keeps 7, and the property's own state starts at its own default")
    }

    @Test("An enum view's new case starts its @State at its own defaults, not at the old case's values")
    func enumViewChangingCase() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(Screen.one(TappedFull(tap: tap)), context: context) == "one 100")
        tap.kept?.wrappedValue = 7
        #expect(line(Screen.one(TappedFull(tap: tap)), context: context) == "one 7")

        #expect(line(Screen.two(Pair()), context: context) == "two 1 2",
                "the new case's state starts at its own defaults")
    }

    /// Found writing the test above: a case holding two values. OpenSwiftUI's
    /// `DynamicPropertyCache` takes each case's payload as a tuple and keeps
    /// its elements that conform
    /// (`Tools/SwiftUIProbes/Dynamic property discovery/notes.md` §2).
    @Test("An app property beside another value in an enum view's payload keeps its @State")
    func enumPayloadOfTwoValues() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(Mirror(reflecting: PairedScreen.one(Full(), tap)).children.first?.value is (Full, StateTap),
                "precondition: Mirror shows the payload as one child, a tuple")
        #expect(line(PairedScreen.one(Full(), tap), context: context) == "one 100")
        tap.kept?.wrappedValue = 7
        #expect(line(PairedScreen.one(Full(), tap), context: context) == "one 7")
    }

    @Test("An app property beside other values in an enum view's payload reads its environment")
    func enumPayloadOfThreeValuesResolvesEnvironment() {
        let context = makeRenderContext(width: 30, height: 1)
        let view = PairedPropertiesScreen.one(EnabledReader(), Counting(counter: UpdateCounter()), 0)
        #expect(line(view.disabled(true), context: context) == "disabled",
                "the property's @Environment reads the value set above the view, not the default")
    }

    @Test("An app property beside other values in an enum view's payload has its update() run")
    func enumPayloadOfThreeValuesRunsUpdate() {
        let context = makeRenderContext(width: 30, height: 1)
        let counter = UpdateCounter()
        _ = line(PairedPropertiesScreen.one(EnabledReader(), Counting(counter: counter), 0), context: context)
        #expect(counter.updates >= 1, "update() ran before the body")
    }

    /// SwiftUI 6.5.4 on macOS 15 resets the case it leaves: back in it, its
    /// `@State` reads its default
    /// (`Tools/SwiftUIProbes/State keys in dynamic properties/skey.out`, E1).
    @Test("An enum view's case that comes back starts its @State at its defaults again")
    func enumViewReturningCase() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(Screen.one(TappedFull(tap: tap)), context: context) == "one 100")
        tap.kept?.wrappedValue = 7
        #expect(line(Screen.one(TappedFull(tap: tap)), context: context) == "one 7")
        #expect(line(Screen.two(Pair()), context: context) == "two 1 2")

        #expect(line(Screen.one(TappedFull(tap: tap)), context: context) == "one 100",
                "the case left for another starts again at its default")
    }

    /// Measured the same way on SwiftUI
    /// (`Tools/SwiftUIProbes/State keys in dynamic properties/skey.out`, E1b).
    @Test("An enum view's case starts at its own defaults when the case it replaced held the same property type")
    func enumViewCasesOfOneType() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(Twins.left(TappedFull(tap: tap)), context: context) == "left 100")
        tap.kept?.wrappedValue = 7
        #expect(line(Twins.left(TappedFull(tap: tap)), context: context) == "left 7")

        #expect(line(Twins.right(TappedFull(tap: tap)), context: context) == "right 100")
    }

    /// An enum property's cases reset as an enum view's do in SwiftUI, and
    /// the view's own `@State` is untouched
    /// (`Tools/SwiftUIProbes/State keys in dynamic properties/skey.out`, E2).
    @Test("An enum app property's case change starts its @State afresh and leaves the view's own @State alone")
    func enumPropertyChangingCase() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(PhaseView(tap: tap, phase: .one(TappedFull(tap: tap))), context: context) == "one 100 x 0")
        tap.kept?.wrappedValue = 7
        tap.x?.wrappedValue = 3
        #expect(line(PhaseView(tap: tap, phase: .one(TappedFull(tap: tap))), context: context) == "one 7 x 3")

        #expect(line(PhaseView(tap: tap, phase: .two(Pair())), context: context) == "two 1 2 x 3")
        #expect(line(PhaseView(tap: tap, phase: .one(TappedFull(tap: tap))), context: context) == "one 100 x 3")
    }

    /// Found in review: the reset reached only the `@State` bound on the
    /// frame the case came back, and an optional holding nothing then binds
    /// nothing, so the old box survived to be found a frame later.
    @Test("An enum view's case that comes back holding nil starts its @State at its default once it holds a value")
    func enumViewReturningCaseThroughNil() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(OptionalScreen.one(TappedFull(tap: tap)), context: context) == "one 100")
        tap.kept?.wrappedValue = 7
        #expect(line(OptionalScreen.one(TappedFull(tap: tap)), context: context) == "one 7")
        #expect(line(OptionalScreen.two, context: context) == "two")
        #expect(line(OptionalScreen.one(nil), context: context) == "one -")

        #expect(line(OptionalScreen.one(TappedFull(tap: tap)), context: context) == "one 100",
                "the case came back reset, whatever it held on the frame it did")
    }

    /// The same, for an existential holding another type on the frame the
    /// case comes back. Within one stay in the case, a type that comes back
    /// finds its state (decisions-SKEY B-SKEY-1).
    @Test("An enum view's case that comes back holding another type starts its @State at its default once it holds the old one")
    func enumViewReturningCaseThroughAnotherType() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(ExistentialScreen.one(TappedFull(tap: tap)), context: context) == "one 100")
        tap.kept?.wrappedValue = 7
        #expect(line(ExistentialScreen.one(Empty()), context: context) == "one -")
        #expect(line(ExistentialScreen.one(TappedFull(tap: tap)), context: context) == "one 7",
                "precondition: within one stay in the case, a type that comes back finds its state")
        #expect(line(ExistentialScreen.two, context: context) == "two")
        #expect(line(ExistentialScreen.one(Empty()), context: context) == "one -")

        #expect(line(ExistentialScreen.one(TappedFull(tap: tap)), context: context) == "one 100",
                "the case came back reset, whatever type it held on the frame it did")
    }

    @Test("An enum property's case inside an enum view's case is reset when the outer case comes back")
    func nestedEnumCaseReturning() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(NestedScreen.outer(.one(TappedFull(tap: tap))), context: context) == "one 100")
        tap.kept?.wrappedValue = 7
        #expect(line(NestedScreen.outer(.one(TappedFull(tap: tap))), context: context) == "one 7")
        #expect(line(NestedScreen.other, context: context) == "other")
        #expect(line(NestedScreen.outer(.one(TappedFull(tap: tap))), context: context) == "one 100",
                "the inner case, unchanged, still came back reset with the outer one")

        tap.kept?.wrappedValue = 8
        #expect(line(NestedScreen.other, context: context) == "other")
        #expect(line(NestedScreen.outer(.two(Pair())), context: context) == "two 1 2")
        #expect(line(NestedScreen.outer(.one(TappedFull(tap: tap))), context: context) == "one 100")
    }

    @Test("An enum view switching cases back and forth keeps no more state than one case holds")
    func enumViewSwitchingCasesKeepsNoLeftovers() throws {
        let context = makeRenderContext(width: 30, height: 1)
        let storage = try #require(context.stateStorage)
        let tap = StateTap()
        _ = line(Screen.one(TappedFull(tap: tap)), context: context)
        _ = line(Screen.two(Pair()), context: context)
        let settled = storage.count
        for _ in 0..<5 {
            _ = line(Screen.one(TappedFull(tap: tap)), context: context)
            _ = line(Screen.two(Pair()), context: context)
        }
        #expect(storage.count == settled, "what each case left is dropped, not kept beside the new case's")
    }

    /// Found in review: the record of the enum view's case also listed what
    /// the inner enum's case created, so each inner change listed the
    /// recreated state there again. `storage.count` cannot see it: the
    /// record is one value however many keys it lists.
    @Test("An enum property switching cases inside an enum view's unchanged case grows nothing the view keeps")
    func nestedEnumSwitchingCasesKeepsOuterRecordBounded() throws {
        let context = makeRenderContext(width: 30, height: 1)
        let storage = try #require(context.stateStorage)
        let tap = StateTap()
        _ = line(NestedScreen.other, context: context)
        let empty = storage.count
        _ = line(NestedScreen.outer(.one(TappedFull(tap: tap))), context: context)
        _ = line(NestedScreen.outer(.two(Pair())), context: context)
        let recordKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateStorage.StateKey.enumCaseIndex,
            scope: NestedScope.view)
        let listed = try #require(storage.enumCaseRecord(at: recordKey)).keys.count
        #expect(listed == 1, "the outer case lists only the inner enum's record")
        for _ in 0..<5 {
            _ = line(NestedScreen.outer(.one(TappedFull(tap: tap))), context: context)
            _ = line(NestedScreen.outer(.two(Pair())), context: context)
        }
        // Fetched again: a record replaced each frame would leave the first one's count unchanged.
        let after = try #require(storage.enumCaseRecord(at: recordKey))
        #expect(after.keys.count == listed, "the inner enum's changes are its own record's to list")

        _ = line(NestedScreen.other, context: context)
        #expect(storage.count == empty + 1, "the outer case's change dropped the inner enum's record and state")
    }

    @Test("An existential app property that changes type starts the new type's @State at its own default")
    func existentialPropertyOfAnotherType() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(KeptHolderView(tap: tap, p: Full()), context: context) == "x 0 kept 100")
        tap.x?.wrappedValue = 7
        tap.kept?.wrappedValue = 50
        #expect(line(KeptHolderView(tap: tap, p: Full()), context: context) == "x 7 kept 50")

        #expect(line(KeptHolderView(tap: tap, p: OtherFull()), context: context) == "x 7 kept 200",
                "the new type's @State does not take over the old type's value")
    }

    /// What SwiftUI does with `Optional` conforming to `DynamicProperty` —
    /// the closest it comes to TUIkit looking through an optional
    /// (decisions-DYNP A-DYNP-1): measured on macOS 15, the property's
    /// `@State` reads what it held before the optional went `nil`
    /// (`Tools/SwiftUIProbes/State keys in dynamic properties/skey-optconf.out`, E4).
    @Test("An optional app property that comes back finds the @State it left")
    func optionalPropertyReturning() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = StateTap()
        #expect(line(OptionalFullView(tap: tap, p: Full()), context: context) == "x 0 kept 100")
        tap.x?.wrappedValue = 7
        tap.kept?.wrappedValue = 50
        #expect(line(OptionalFullView(tap: tap, p: nil), context: context) == "x 7 kept -")

        #expect(line(OptionalFullView(tap: tap, p: Full()), context: context) == "x 7 kept 50")
    }

    @Test("A view's @FocusState keeps its id when an optional app property before it holds one too")
    func focusStateAfterOptionalProperty() {
        let storage = StateStorage()
        let identity = ViewIdentity(path: "FocusRoot")
        var without = OptionalFocusView(p: nil)
        prepareForBody(&without, identity: identity, storage: storage)
        var with = OptionalFocusView(p: FocusHolder())
        prepareForBody(&with, identity: identity, storage: storage)

        #expect(!without.ownID.isEmpty)
        #expect(with.ownID == without.ownID, "the view's own @FocusState keeps its id")
        let innerID = with.p?.innerID ?? ""
        #expect(!innerID.isEmpty && innerID != with.ownID, "the nested @FocusState has an id of its own")
    }
}
