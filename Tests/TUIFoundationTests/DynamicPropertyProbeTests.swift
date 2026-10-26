//  🖥️ TUI — A Terminal UI framework for Swift
//  DynamicPropertyProbeTests.swift
//
//  A view whose fields the property walk acts on only if their values say so
//  — an existential, or an optional of one — is probed where it lies before
//  any copy of it is made: if no field holds anything the walk acts on, its
//  body is evaluated on the view as it is, as a view holding no property's
//  is. Such a field's dynamic type is read where it lies, never by copying
//  the value out into an `Any`. A field declared as a plain class is one of
//  them: the object in it may be of a subclass that is a property, which is
//  walked as any class property is (decisions-DYNVFIX B-DYNVFIX-1).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

#if canImport(ObjectiveC)
    import ObjectiveC
#endif

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// An object whose retain count the bodies record: one more while a copy of
/// the view holding it lives.
private final class Token {}

/// What each body recorded.
@MainActor
private final class Counts {
    var retains: [String: UInt] = [:]
}

/// A protocol a view's existential field is declared as.
private protocol Shape {}

/// A shape that is no property, too big for an existential's inline
/// buffer.
private struct Square: Shape {
    var side = 1
    var corners = (0, 0, 0, 0)
}

/// Two more shapes that are no property, so a field finds three in turn.
private struct Disc: Shape {
    var radius = 1
}

private struct Wedge: Shape {
    var sides = (3, 4, 5)
}

/// Holds the token and nothing the walk acts on.
private struct PlainHolder: View {
    let token: Token
    let counts: Counts

    var body: some View {
        counts.retains["plain"] = _getRetainCount(token)
        return Text(verbatim: "plain")
    }
}

/// Holds the token and an existential that holds no property.
private struct ShapeHolder: View {
    let token: Token
    let shape: any Shape
    let counts: Counts

    var body: some View {
        counts.retains["shape"] = _getRetainCount(token)
        return Text(verbatim: "shape")
    }
}

// MARK: - A property subclass behind a plain class field

private struct ProbeAccent: EnvironmentKey {
    static let defaultValue = "plain"
}

extension EnvironmentValues {
    fileprivate var probeAccent: String {
        get { self[ProbeAccent.self] }
        set { self[ProbeAccent.self] = newValue }
    }
}

/// A plain class, not a property.
private class RowDelegate {
    func title() -> String { "plain" }
}

/// A subclass of it that is a property, reading the environment.
private final class AccentDelegate: RowDelegate, DynamicProperty {
    @Environment(\.probeAccent) private var accent

    override func title() -> String { accent }
}

/// An observable model.
@Observable
private final class ProbeModel {
    var name = "model"
}

/// A subclass that is a property, reading a model from the environment.
private final class ModelDelegate: RowDelegate, DynamicProperty {
    @Environment(ProbeModel.self) private var model

    override func title() -> String { model.name }
}

/// A field declared as the plain class.
private struct DelegateRow: View {
    let delegate: RowDelegate

    var body: some View {
        Text(verbatim: delegate.title())
    }
}

// MARK: - A property subclass held weak or unowned

/// A subclass that is a property, reading the environment and counting its
/// updates.
private final class CountingDelegate: RowDelegate, DynamicProperty {
    @Environment(\.probeAccent) private var accent
    private(set) var updates = 0

    func update() {
        updates += 1
    }

    override func title() -> String { "\(accent) \(updates)" }
}

/// The plain class held `weak`.
private struct WeakDelegateRow: View {
    weak var delegate: RowDelegate?

    var body: some View {
        Text(verbatim: delegate?.title() ?? "gone")
    }
}

/// A class-bound protocol the plain class conforms to.
private protocol Titled: AnyObject {
    func title() -> String
}

extension RowDelegate: Titled {}

/// The protocol held `weak`.
private struct WeakTitledRow: View {
    weak var titled: (any Titled)?

    var body: some View {
        Text(verbatim: titled?.title() ?? "gone")
    }
}

/// The protocol held `unowned`.
private struct UnownedTitledRow: View {
    unowned let titled: any Titled

    var body: some View {
        Text(verbatim: titled.title())
    }
}

/// The plain class held `unowned`.
private struct UnownedDelegateRow: View {
    unowned let delegate: RowDelegate

    var body: some View {
        Text(verbatim: delegate.title())
    }
}

/// The plain class held `unowned`, as an optional.
private struct OptionalUnownedDelegateRow: View {
    unowned var delegate: RowDelegate?

    var body: some View {
        Text(verbatim: delegate?.title() ?? "none")
    }
}

/// The plain class held `unowned(unsafe)`.
private struct UnsafeDelegateRow: View {
    unowned(unsafe) let delegate: RowDelegate

    var body: some View {
        Text(verbatim: delegate.title())
    }
}

/// The plain class held `unowned` and never read, as an event handler's
/// target might be held.
private struct UnreadDelegateRow: View {
    unowned let delegate: RowDelegate

    var body: some View {
        Text(verbatim: "unread")
    }
}

/// The protocol held `unowned` and never read.
private struct UnreadTitledRow: View {
    unowned let titled: any Titled

    var body: some View {
        Text(verbatim: "unread")
    }
}

/// The plain class held `unowned`, beside the token.
private struct UnownedDelegateHolder: View {
    let token: Token
    unowned let delegate: RowDelegate
    let counts: Counts

    var body: some View {
        counts.retains["unowned"] = _getRetainCount(token)
        return Text(verbatim: "unowned")
    }
}

/// The plain class held `weak`, beside the token.
private struct WeakDelegateHolder: View {
    let token: Token
    weak var delegate: RowDelegate?
    let counts: Counts

    var body: some View {
        counts.retains["weak"] = _getRetainCount(token)
        return Text(verbatim: "weak")
    }
}

/// A class property holding the plain class `weak`: its contents are walked
/// as the view's are.
private final class DelegateOwner: DynamicProperty {
    weak var delegate: RowDelegate?

    init(_ delegate: RowDelegate) {
        self.delegate = delegate
    }
}

private struct DelegateOwnerRow: View {
    let owner: DelegateOwner

    var body: some View {
        Text(verbatim: owner.delegate?.title() ?? "gone")
    }
}

#if canImport(ObjectiveC)
    /// A plain class with an Objective-C ancestor.
    private class ObjCDelegate: NSObject {
        func title() -> String { "plain" }
    }

    /// A subclass of it that is a property, reading the environment.
    private final class ObjCAccentDelegate: ObjCDelegate, DynamicProperty {
        @Environment(\.probeAccent) private var accent

        override func title() -> String { accent }
    }

    private struct WeakObjCRow: View {
        weak var delegate: ObjCDelegate?

        var body: some View {
            Text(verbatim: delegate?.title() ?? "gone")
        }
    }

    private struct UnownedObjCRow: View {
        unowned let delegate: ObjCDelegate

        var body: some View {
            Text(verbatim: delegate.title())
        }
    }

    extension ObjCDelegate: Titled {}
#endif

@MainActor
@Suite("DynamicProperty probes")
struct DynamicPropertyProbeTests {

    /// Every body of a view holding an existential field copied the view
    /// before walking it, and copied the field's value out into an `Any` to
    /// read its type, where the walks it replaced had skipped the type after
    /// a first body that found nothing (decisions-DYNP B-DYNP-2's bug: what
    /// the field held later was never looked at). The field's type is now
    /// read where it lies, and one found holding nothing is noted, so a later
    /// body holding it again evaluates the view as it is: the token is
    /// retained no more often than a view holding no existential retains it.
    @Test("A view whose existential holds no property is evaluated as it is, with no copy of the view")
    func existentialHoldingNothingIsNotCopied() {
        let context = makeRenderContext(width: 20, height: 1)
        let token = Token()
        let counts = Counts()
        _ = renderToBuffer(PlainHolder(token: token, counts: counts), context: context)
        // The first body of the type finds `Square` unknown and walks it.
        _ = renderToBuffer(ShapeHolder(token: token, shape: Square(), counts: counts), context: context)
        _ = renderToBuffer(ShapeHolder(token: token, shape: Square(), counts: counts), context: context)
        #expect(counts.retains["shape"] == counts.retains["plain"])
    }

    /// The types a field was found holding nothing in were kept two to a
    /// plan, and a plan is kept per declared type, so every `any Shape`
    /// field shares one: with three shapes in turn, each body found its
    /// type evicted, and the view was copied and walked again (review of
    /// 4388af345). A type found holding nothing anywhere is known to hold
    /// nothing everywhere.
    @Test("A view whose existential holds one of three types holding no property is evaluated as it is")
    func existentialHoldingOneOfThreeIsNotCopied() {
        let context = makeRenderContext(width: 20, height: 1)
        let token = Token()
        let counts = Counts()
        _ = renderToBuffer(PlainHolder(token: token, counts: counts), context: context)
        for shape: any Shape in [Square(), Disc(), Wedge()] {
            _ = renderToBuffer(ShapeHolder(token: token, shape: shape, counts: counts), context: context)
        }
        _ = renderToBuffer(ShapeHolder(token: token, shape: Square(), counts: counts), context: context)
        #expect(counts.retains["shape"] == counts.retains["plain"])
    }

    /// The plan read only the declared type of a field, as SwiftUI does: a
    /// property subclass behind a plain class field was given nothing, so
    /// its `@Environment` read its default. TUI reached it from the value
    /// before the plans (when the type's first value held it), and keeps the
    /// reach: the object's class is read each body.
    @Test("A property subclass behind a field declared as a plain class reads its view's environment")
    func subclassBehindPlainFieldIsResolved() {
        let context = makeRenderContext(width: 20, height: 1)
        let row = DelegateRow(delegate: AccentDelegate()).environment(\.probeAccent, "red")
        #expect(renderToBuffer(row, context: context).lines.first?.stripped.trimmingCharacters(in: .whitespaces) == "red")
        let plain = DelegateRow(delegate: RowDelegate())
        #expect(renderToBuffer(plain, context: context).lines.first?.stripped.trimmingCharacters(in: .whitespaces) == "plain")
    }

    /// The same for an `@Environment(Model.self)`, which, never resolved,
    /// traps when read. An exit test, so the trap fails this test and not
    /// the run.
    @Test("A property subclass behind a plain class field reading an observable model from the environment draws")
    func subclassBehindPlainFieldReadsModel() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let context = makeRenderContext(width: 20, height: 1)
                let row = DelegateRow(delegate: ModelDelegate()).environment(ProbeModel())
                let drawn = renderToBuffer(row, context: context)
                #expect(drawn.lines.first?.stripped.trimmingCharacters(in: .whitespaces) == "model")
            }
        }
    }

    private func line<V: View>(_ view: V, context: RenderContext) -> String? {
        renderToBuffer(view, context: context).lines.first?.stripped.trimmingCharacters(in: .whitespaces)
    }

    /// A field held `weak` or `unowned` whose declared type was a plain
    /// class was never read: the field metadata says only "not strong", and
    /// a dead `unowned` one traps when loaded (DYNV bug 9). So a property
    /// subclass there read its `@Environment`'s default, where the walk
    /// before the plans reached it. The field's ownership is read from its
    /// mangled type name: a `weak` one is loaded, and an `unowned` one's
    /// object class read where it lies. As for a field declared as a property
    /// class, a `weak` one is not updated and an `unowned` one is.
    @Test("A property subclass held weak or unowned in a field declared as a plain class reads its view's environment")
    func subclassHeldWeakOrUnownedIsResolved() {
        // A context, and so a state storage, per holder: the object's
        // contents belong to the first view drawn that reaches it.
        let delegate = CountingDelegate()
        let weak = WeakDelegateRow(delegate: delegate).environment(\.probeAccent, "red")
        #expect(line(weak, context: makeRenderContext(width: 20, height: 1)) == "red 0")
        let unownedContext = makeRenderContext(width: 20, height: 1)
        let unowned = UnownedDelegateRow(delegate: delegate).environment(\.probeAccent, "blue")
        #expect(line(unowned, context: unownedContext) == "blue 1")
        #expect(line(unowned, context: unownedContext) == "blue 2")
        let optional = OptionalUnownedDelegateRow(delegate: delegate).environment(\.probeAccent, "green")
        #expect(line(optional, context: makeRenderContext(width: 20, height: 1)) == "green 2")
        withExtendedLifetime(delegate) {}
    }

    /// The review's case (2026-10-12): an `@Environment(Model.self)` in a
    /// property subclass held `weak` traps when read unresolved. An exit
    /// test, so the trap fails this test and not the run.
    @Test("A property subclass held weak behind a plain class field reading an observable model draws")
    func subclassHeldWeakReadsModel() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let context = makeRenderContext(width: 20, height: 1)
                let delegate = ModelDelegate()
                let row = WeakDelegateRow(delegate: delegate).environment(ProbeModel())
                #expect(renderToBuffer(row, context: context).lines.first?.stripped.trimmingCharacters(in: .whitespaces) == "model")
                withExtendedLifetime(delegate) {}
            }
        }
    }

    /// A class-bound existential held `weak` is loaded the same way: its
    /// object's class says whether it is a property.
    @Test("A property held weak in a class-bound existential field reads its view's environment")
    func propertyHeldWeakInExistentialIsResolved() {
        let delegate = AccentDelegate()
        let row = WeakTitledRow(titled: delegate).environment(\.probeAccent, "red")
        #expect(line(row, context: makeRenderContext(width: 20, height: 1)) == "red")
        withExtendedLifetime(delegate) {}
    }

    /// A class-bound existential held `unowned` was never reached, on any
    /// platform, though the walk before the plans reached it: where
    /// Objective-C interoperates, it is kept as an Objective-C weak
    /// reference whenever its object could be an Objective-C one (review of
    /// 6c8fe3d2b, 2026-10-12). A reference to a native object is the
    /// object's address, which says so: its class is read there, as a plain
    /// class's held `unowned` is.
    @Test("A property held unowned in a class-bound existential field reads its view's environment")
    func propertyHeldUnownedInExistentialIsResolved() {
        let delegate = AccentDelegate()
        let row = UnownedTitledRow(titled: delegate).environment(\.probeAccent, "red")
        #expect(line(row, context: makeRenderContext(width: 20, height: 1)) == "red")
        withExtendedLifetime(delegate) {}
    }

    /// The review's case: an `@Environment(Model.self)` in it traps when
    /// read unresolved. An exit test.
    @Test("A property held unowned in a class-bound existential field reading an observable model draws")
    func propertyHeldUnownedInExistentialReadsModel() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let context = makeRenderContext(width: 20, height: 1)
                let delegate = ModelDelegate()
                let row = UnownedTitledRow(titled: delegate).environment(ProbeModel())
                #expect(renderToBuffer(row, context: context).lines.first?.stripped.trimmingCharacters(in: .whitespaces) == "model")
                withExtendedLifetime(delegate) {}
            }
        }
    }

    /// A dead object held `unowned` in a class-bound existential, of a class
    /// that is not a property, is never loaded: its class is read where the
    /// reference lies. An exit test.
    @Test("A view holding a dead plain object unowned in a class-bound existential, which body never reads, still draws")
    func deadPlainObjectHeldUnownedInExistentialIsNeverLoaded() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let context = makeRenderContext(width: 20, height: 1)
                var delegate: RowDelegate? = RowDelegate()
                let view = UnreadTitledRow(titled: delegate!)
                delegate = nil
                _ = renderToBuffer(view, context: context)
                _ = renderToBuffer(view, context: context)
            }
        }
    }

    /// A class property's own `weak` field is reached the same way.
    @Test("A property subclass held weak by a class property reads the holding view's environment")
    func subclassHeldWeakInsideAnObjectIsResolved() {
        let context = makeRenderContext(width: 20, height: 1)
        let delegate = AccentDelegate()
        #expect(line(DelegateOwnerRow(owner: DelegateOwner(delegate)).environment(\.probeAccent, "red"), context: context) == "red")
        withExtendedLifetime(delegate) {}
    }

    /// `unowned(unsafe)` keeps nothing of its object alive, its memory
    /// included, so nothing of it is ever read: a property there is not
    /// reached.
    @Test("A property subclass held unowned(unsafe) is never loaded")
    func subclassHeldUnownedUnsafeIsNotLoaded() {
        let context = makeRenderContext(width: 20, height: 1)
        let delegate = CountingDelegate()
        #expect(line(UnsafeDelegateRow(delegate: delegate).environment(\.probeAccent, "red"), context: context) == "plain 0")
        withExtendedLifetime(delegate) {}
    }

    /// A dead object held `unowned` in a field declared as a class that is
    /// not final: its class is read where it lies, which the unowned count
    /// keeps, and an object of a class that is not a property is never
    /// loaded, so it does not trap (DYNV bug 9). An exit test.
    @Test("A view holding a dead plain object unowned, which body never reads, still draws")
    func deadPlainObjectHeldUnownedIsNeverLoaded() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let context = makeRenderContext(width: 20, height: 1)
                var delegate: RowDelegate? = RowDelegate()
                let view = UnreadDelegateRow(delegate: delegate!)
                delegate = nil
                _ = renderToBuffer(view, context: context)
                _ = renderToBuffer(view, context: context)
                var weakDelegate: RowDelegate? = AccentDelegate()
                let weakView = WeakDelegateRow(delegate: weakDelegate)
                weakDelegate = nil
                #expect(renderToBuffer(weakView, context: context).lines.first?.stripped.trimmingCharacters(in: .whitespaces) == "gone")
            }
        }
    }

    /// A view holding a plain object `unowned` is probed where it lies, as
    /// one holding it strongly is: evaluated with no copy of the view.
    @Test("A view holding a plain object unowned is evaluated as it is, with no copy of the view")
    func plainObjectHeldUnownedIsNotCopied() {
        let context = makeRenderContext(width: 20, height: 1)
        let token = Token()
        let counts = Counts()
        let delegate = RowDelegate()
        _ = renderToBuffer(PlainHolder(token: token, counts: counts), context: context)
        _ = renderToBuffer(UnownedDelegateHolder(token: token, delegate: delegate, counts: counts), context: context)
        #expect(counts.retains["unowned"] == counts.retains["plain"])
        withExtendedLifetime(delegate) {}
    }

    /// A view holding a plain object `weak` was copied, and the field loaded
    /// through the runtime's reflection, which copied the view again, on
    /// every body (review of 6c8fe3d2b, 2026-10-12). The field is loaded
    /// where it lies, as Swift loads a weak reference, before any copy is
    /// made: a view holding an object of the declared class is evaluated as
    /// it is.
    @Test("A view holding a plain object weak is evaluated as it is, with no copy of the view")
    func plainObjectHeldWeakIsNotCopied() {
        let context = makeRenderContext(width: 20, height: 1)
        let token = Token()
        let counts = Counts()
        let delegate = RowDelegate()
        _ = renderToBuffer(PlainHolder(token: token, counts: counts), context: context)
        _ = renderToBuffer(WeakDelegateHolder(token: token, delegate: delegate, counts: counts), context: context)
        #expect(counts.retains["weak"] == counts.retains["plain"])
        withExtendedLifetime(delegate) {}
    }

    #if canImport(ObjectiveC)
        /// Where Objective-C interoperates, an `unowned` reference to an
        /// object with an Objective-C ancestor is kept as one of its weak
        /// references, which only the runtime reads, and the runtime traps
        /// on a dead one: such a field is never loaded. A `weak` one is.
        @Test("A property subclass of an Objective-C class is reached held weak, and not held unowned")
        func objectiveCSubclassHeldWeakNotUnowned() {
            let delegate = ObjCAccentDelegate()
            let weak = WeakObjCRow(delegate: delegate).environment(\.probeAccent, "red")
            #expect(line(weak, context: makeRenderContext(width: 20, height: 1)) == "red")
            let unowned = UnownedObjCRow(delegate: delegate).environment(\.probeAccent, "blue")
            #expect(line(unowned, context: makeRenderContext(width: 20, height: 1)) == "red")
            // In a class-bound existential, the reference says its object is
            // an Objective-C one, and its class is not read.
            let existential = UnownedTitledRow(titled: delegate).environment(\.probeAccent, "green")
            #expect(line(existential, context: makeRenderContext(width: 20, height: 1)) == "red")
            withExtendedLifetime(delegate) {}
        }
    #endif
}
