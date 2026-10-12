//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyDiscoveryTests.swift
//
//  Where the property walk finds a view's dynamic properties: planned once
//  per type from the runtime's field metadata, by each field's DECLARED type
//  (`PropertyPlans`), as SwiftUI finds them, and checked by value only where
//  the declared type is open — an optional, an existential, an enum's case,
//  an object. Each test is a case where finding them from each value with
//  `Mirror`, as TUIkit did, diverged from SwiftUI in a way an app could see
//  (session notes DYNV/notes.md).
//
//  SwiftUI's behaviour was measured on macOS 15.8.1 (SwiftUI 6.5.4) with an
//  offscreen NSHostingView: session notes DYNP/optional/op.swift (op.out)
//  and DYNV/probe/dv.swift (dv.out).
//
//  Created by Wade Tregaskis
//  License: MIT

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

// MARK: - A custom Mirror

/// A view with a custom `Mirror`, as an app might write for its debug
/// description: it lists what the view shows, not its property wrappers.
private struct ReflectingCounter: View {
    let taps: Taps
    @State private var count = 0

    var body: some View {
        taps.bindings["count"] = $count
        return Text(verbatim: "count \(count)")
    }
}

extension ReflectingCounter: @MainActor CustomReflectable {
    var customMirror: Mirror {
        Mirror(self, children: ["count": count])
    }
}

// MARK: - An app property counting its updates

/// An app property whose `update()` counts in a stored value of its own.
private struct CountingValue: DynamicProperty {
    var count = 0

    mutating func update() {
        count += 1
    }
}

// MARK: - An existential first drawn holding nothing to do

/// An existential app property field, which can hold a property with
/// something to do, or one with nothing. Generic over a tag only so that two
/// tests of it are two view types, which the walk plans apart.
private struct ExistentialSlotView<Tag>: View {
    let p: any DynamicProperty

    var body: some View {
        Text(verbatim: "count \((p as? CountingValue)?.count ?? -1)")
    }
}

// MARK: - A plain class field first drawn holding a plain instance

/// A plain class, not a property.
private class PlainBase {}

/// A subclass of it that is an app property, counting its updates.
private final class CountingSubclass: PlainBase, DynamicProperty {
    var count = 0

    func update() {
        count += 1
    }
}

/// A field declared as the plain class. Generic over a tag for the reason
/// `ExistentialSlotView` is.
private struct BaseFieldView<Tag>: View {
    let object: PlainBase

    var body: some View {
        Text(verbatim: "count \((object as? CountingSubclass)?.count ?? -1)")
    }
}

// MARK: - Class properties that reach each other

/// Class app properties with a back-reference: a parent and child, each a
/// property, each reaching the other.
private final class Coordinator: DynamicProperty {
    weak var parent: Coordinator?
    var child: Coordinator?
}

private struct CoordinatorView: View {
    let coordinator: Coordinator

    var body: some View {
        Text(verbatim: "coordinator")
    }
}

/// The same, reaching each other through strong references only.
private final class StrongCoordinator: DynamicProperty {
    var other: StrongCoordinator?
    var updates = 0

    func update() {
        updates += 1
    }
}

private struct StrongCoordinatorView: View {
    let coordinator: StrongCoordinator

    var body: some View {
        Text(verbatim: "updates \(coordinator.updates)")
    }
}

// MARK: - A dead unowned reference body never reads

/// A plain class, not a property.
private final class Owner {}

/// Holds an object `unowned` that `body` never reads, as an event handler's
/// target might be held.
private struct UnownedOwnerView: View {
    @State private var x = 0
    unowned let owner: Owner

    var body: some View {
        Text(verbatim: "x \(x)")
    }
}

/// The same with no property wrapper at all.
private struct PlainUnownedView: View {
    unowned let owner: Owner

    var body: some View {
        Text(verbatim: "plain")
    }
}

/// A class app property counting its updates.
private final class CountingObject: DynamicProperty {
    var count = 0

    func update() {
        count += 1
    }
}

/// A dead `unowned` plain object, declared before a live `unowned` app
/// property.
private struct DeadBeforeLiveView: View {
    unowned let owner: Owner
    unowned let counter: CountingObject

    var body: some View {
        Text(verbatim: "count \(counter.count)")
    }
}

/// An `unowned` app property its custom `Mirror` leaves out.
private struct HiddenUnownedView: View {
    unowned let counter: CountingObject
    let name: String

    var body: some View {
        Text(verbatim: "\(name) \(counter.count)")
    }
}

extension HiddenUnownedView: @MainActor CustomReflectable {
    var customMirror: Mirror {
        Mirror(self, children: ["name": name])
    }
}

@MainActor
@Suite("DynamicProperty discovery")
struct DynamicPropertyDiscoveryTests {

    private func lines<V: View>(_ view: V, context: RenderContext) -> [String] {
        renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    /// `Mirror` lists what a `customMirror` chooses: here no `State`, so a
    /// walk that reflected the view never bound `count`, and it started again
    /// at 0 in every frame's new view value. The field metadata the walk now
    /// plans from is not the mirror. SwiftUI keeps it (dv.out, `mirror`:
    /// count=3 after the write).
    @Test("A view with a custom Mirror keeps its @State from frame to frame")
    func customMirrorKeepsState() {
        let context = makeRenderContext(width: 20, height: 1)
        let taps = Taps()
        #expect(lines(ReflectingCounter(taps: taps), context: context) == ["count 0"])
        taps.bindings["count"]?.wrappedValue = 3
        #expect(lines(ReflectingCounter(taps: taps), context: context) == ["count 3"])
    }

    /// The walks kept a view type as holding nothing when its first value
    /// held nothing, and an existential field was not counted (decisions-DYNP
    /// B-DYNP-2, "Not counted"): a `Binding` in the field on the first frame
    /// kept the type, and the property it held next was never updated (body
    /// read 0, where a type first drawn holding the property read 1). The
    /// plan now names the field, and each body reads what it holds. SwiftUI
    /// updates neither (op.out, case vii-a); what TUIkit does with a value
    /// must not depend on the first value drawn.
    @Test("What an existential property field's value gets does not depend on what the field held first")
    func existentialFirstEmpty() {
        enum FirstHoldsProperty {}
        enum FirstHoldsNothing {}
        let context = makeRenderContext(width: 20, height: 1)
        let fromTheStart = lines(ExistentialSlotView<FirstHoldsProperty>(p: CountingValue()), context: context)
        #expect(fromTheStart == ["count 1"])
        #expect(lines(ExistentialSlotView<FirstHoldsNothing>(p: Binding.constant(0)), context: context) == ["count -1"])
        let later = lines(ExistentialSlotView<FirstHoldsNothing>(p: CountingValue()), context: context)
        #expect(later == fromTheStart)
    }

    /// The same for a field declared as a plain class whose value is a
    /// subclass that is a property, B-DYNP-2's other "Not counted" case: a
    /// type first drawn holding a plain instance was kept as holding nothing,
    /// and the property it held next was never updated, where a type first
    /// drawn holding the property was. The declared type now decides, as in
    /// SwiftUI (session notes DYNV/probe/dv2-main.out, `subclass`: count=0;
    /// declared as the subclass, count=1): a plain class field is never
    /// looked into.
    @Test("What a plain class field's value gets does not depend on what the field held first")
    func classFieldFirstPlain() {
        enum FirstHoldsProperty {}
        enum FirstHoldsPlain {}
        let context = makeRenderContext(width: 20, height: 1)
        let fromTheStart = lines(BaseFieldView<FirstHoldsProperty>(object: CountingSubclass()), context: context)
        #expect(fromTheStart == ["count 0"], "the declared type is not a property")
        #expect(lines(BaseFieldView<FirstHoldsPlain>(object: PlainBase()), context: context) == ["count -1"])
        let later = lines(BaseFieldView<FirstHoldsPlain>(object: CountingSubclass()), context: context)
        #expect(later == fromTheStart)
    }

    /// Three walks descended into a class instance's stored values with no
    /// record of where they had been: the environment walk, the binding
    /// walk, and the write-back's walk of what it could not write in place.
    /// Each, run alone on this pair, went from the child back to its parent
    /// through the `weak` reference and round again until the stack ran out
    /// (SIGSEGV). SwiftUI never looks inside a class property, and drew the
    /// same pair (dv.out, `cycle`). An exit test, so a crash fails this test
    /// and not the run.
    @Test("Class properties that reach each other do not send the property walk round forever")
    func classPropertyCycle() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let root = Coordinator()
                let child = Coordinator()
                root.child = child
                child.parent = root
                let context = makeRenderContext(width: 20, height: 1)
                _ = renderToBuffer(CoordinatorView(coordinator: root), context: context)
                withExtendedLifetime((root, child)) {}
            }
        }
    }

    /// The same through strong references only, which nothing breaks: each
    /// object's own `update()` still runs once per body of the view that
    /// holds it.
    @Test("Class properties that reach each other strongly are each updated once per body")
    func strongClassPropertyCycle() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let first = StrongCoordinator()
                let second = StrongCoordinator()
                first.other = second
                second.other = first
                let context = makeRenderContext(width: 20, height: 1)
                let drawn = renderToBuffer(StrongCoordinatorView(coordinator: first), context: context)
                #expect(drawn.lines.first?.stripped.trimmingCharacters(in: .whitespaces) == "updates 1")
                first.other = nil
                second.other = nil
            }
        }
    }

    /// `Mirror` loaded every stored value of the view, `unowned` ones too,
    /// and loading one whose object has gone traps: "Fatal error: Attempted
    /// to read an unowned reference but object … was already deallocated"
    /// (SIGABRT). The walk loads a field held `unowned` only when its
    /// declared type is a property. Swift lets a program hold such a
    /// reference as long as it never reads it, and SwiftUI, which reads only
    /// fields whose type is a property, drew the view again after its object
    /// died (dv.out, `unowned`). An exit test, so a trap fails this test and
    /// not the run.
    @Test("A view holding an unowned object that has died, which body never reads, still draws")
    func unownedDeadFieldNeverRead() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                var owner: Owner? = Owner()
                let view = UnownedOwnerView(owner: owner!)
                owner = nil
                let context = makeRenderContext(width: 20, height: 1)
                _ = renderToBuffer(view, context: context)
            }
        }
    }

    /// Not only a view with a property: the environment walk reflected every
    /// view type on its first body, before it could keep the type as holding
    /// nothing, so a view with no property wrapper trapped the same way when
    /// its type was first drawn after its object died.
    @Test("A view with no property wrapper, holding an unowned object that has died, still draws on its type's first body")
    func unownedDeadFieldFirstBody() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                var owner: Owner? = Owner()
                let view = PlainUnownedView(owner: owner!)
                owner = nil
                let context = makeRenderContext(width: 20, height: 1)
                _ = renderToBuffer(view, context: context)
            }
        }
    }

    /// A dead `unowned` plain field before a live `unowned` app property:
    /// the property is loaded by itself, at its own index, and nothing else
    /// is read (session notes DYNV2/notes.md §2: a scan of `Mirror`'s
    /// children by name trapped on the dead one first, exit 134 in the
    /// probe).
    @Test("A dead unowned field before a live unowned app property: the view draws and the property is updated")
    func deadUnownedBeforeLiveProperty() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let counter = CountingObject()
                var owner: Owner? = Owner()
                let view = DeadBeforeLiveView(owner: owner!, counter: counter)
                owner = nil
                let context = makeRenderContext(width: 20, height: 1)
                let drawn = renderToBuffer(view, context: context)
                #expect(drawn.lines.first?.stripped.trimmingCharacters(in: .whitespaces) == "count 1")
                withExtendedLifetime(counter) {}
            }
        }
    }

    /// An `unowned` app property that a custom `Mirror` leaves out is still
    /// updated: the field metadata lists it whatever the mirror shows.
    @Test("An unowned app property a custom Mirror hides is still updated")
    func customMirrorHidesUnownedProperty() {
        let context = makeRenderContext(width: 20, height: 1)
        let counter = CountingObject()
        #expect(lines(HiddenUnownedView(counter: counter, name: "x"), context: context) == ["x 1"])
        #expect(lines(HiddenUnownedView(counter: counter, name: "x"), context: context) == ["x 2"])
        withExtendedLifetime(counter) {}
    }
}
