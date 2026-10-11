//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyTests.swift
//
//  An app's own property wrapper, built from `@State` and `@Environment` and
//  conformed to `DynamicProperty`, must behave as those properties would on
//  the view itself. Views are rebuilt for every frame, as an app's are: a
//  reused value carries its state with it and would pass unbound.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// A counter kept in the state of whatever view declares it.
@propertyWrapper
private struct Counter: DynamicProperty {
    @State private var count = 0

    var wrappedValue: Int {
        get { count }
        nonmutating set { count = newValue }
    }

    var projectedValue: Binding<Int> { $count }
}

private struct Accent: EnvironmentKey {
    static let defaultValue = "plain"
}

extension EnvironmentValues {
    fileprivate var accentName: String {
        get { self[Accent.self] }
        set { self[Accent.self] = newValue }
    }
}

/// Reads the environment where its view sits.
@propertyWrapper
private struct AccentName: DynamicProperty {
    @Environment(\.accentName) private var name

    var wrappedValue: String { name }
}

/// Counts its `update()` calls in an object it holds by reference. Not
/// main-actor isolated: `update()` is a requirement of a nonisolated protocol,
/// as SwiftUI's is.
private final class UpdateLog {
    var updates = 0
}

@propertyWrapper
private struct Updating: DynamicProperty {
    let log: UpdateLog

    var wrappedValue: Int { log.updates }

    func update() {
        log.updates += 1
    }
}

/// Caches what it reads in a stored value of its own, in `update()` — what
/// SwiftUI writes back into the view before `body` reads it.
@propertyWrapper
private struct Shouted: DynamicProperty {
    @Environment(\.accentName) private var name
    private var cached = ""

    var wrappedValue: String { cached }

    mutating func update() {
        cached = name.uppercased()
    }
}

/// An app property holding another, each caching in `update()`: the inner one
/// is updated and written back into the outer before the outer updates.
@propertyWrapper
private struct Framed: DynamicProperty {
    @Shouted private var inner: String
    private var framed = ""

    var wrappedValue: String { framed }

    mutating func update() {
        framed = "[\(inner)]"
    }
}

private struct ShoutedView: View {
    @Shouted private var accent: String
    @Framed private var framed: String

    var body: some View {
        Text(verbatim: "\(accent) \(framed)")
    }
}

/// A view that is an enum, its app property in the case's payload: the
/// binding walk's `Mirror` finds it there, so `update()` must run.
private enum UpdatingScreen: View {
    case main(Updating)

    var body: some View {
        switch self {
        case .main(let updating): Text(verbatim: "\(updating.wrappedValue)")
        }
    }
}

/// An app property holding another, in an optional field: both update.
private struct Holding: DynamicProperty {
    let inner: Updating
    let log: UpdateLog

    func update() {
        log.updates += 100
    }
}

private struct OptionalHoldingView: View {
    let holding: Holding?

    var body: some View {
        Text(verbatim: "\(holding?.log.updates ?? -1)")
    }
}

/// Fields the runtime's metadata describes at a layout other than the one
/// stored (`ValueHashPlan.swift`, "A metatype"). `Int.Type` has one value, so
/// the tuple stores only its `String`, at offset 0; the runtime's layout puts
/// the metatype there, a pointer, and the `String` after it. Loaded as the
/// runtime lays the tuple out, the `String`'s object word is `poison`, and
/// copying it retains an address where no object is.
private struct MetatypeFieldsView: View {
    @Updating private var updates: Int
    let pair: (Int.Type, String) = (Int.self, "a string too long to be stored inline")
    let poison = 0x10

    init(log: UpdateLog) {
        _updates = Updating(log: log)
    }

    var body: some View {
        Text(verbatim: "\(updates)")
    }
}
/// A view whose one dynamic property is TUIkit's own `@GestureState`.
private struct GestureStateView: View {
    @GestureState private var pressed = false

    var body: some View {
        Text(verbatim: pressed ? "pressed" : "idle")
    }
}
/// `OptionalHoldingView`, for a test that draws it first with nothing held.
private struct NilFirstHoldingView: View {
    let holding: Holding?

    var body: some View {
        Text(verbatim: "\(holding?.log.updates ?? -1)")
    }
}

/// A view that is an enum, first drawn in its case with no payload.
private enum BlankFirstScreen: View {
    case blank
    case main(Updating)

    var body: some View {
        switch self {
        case .blank: Text(verbatim: "blank")
        case .main(let updating): Text(verbatim: "\(updating.wrappedValue)")
        }
    }
}

/// An app property reading the environment, in an optional field first drawn
/// `nil`.
private struct NilFirstAccentView: View {
    let accent: AccentName?

    var body: some View {
        Text(verbatim: accent?.wrappedValue ?? "none")
    }
}
/// A modifier holding an app property in an optional field: its
/// `ModifiedContent` is first drawn with the field `nil`.
private struct OptionalAccentTag: ViewModifier {
    let accent: AccentName?

    func body(content: Content) -> some View {
        HStack(spacing: 1) {
            content
            Text(verbatim: accent?.wrappedValue ?? "none")
        }
    }
}

/// A modifier holding an app property in a plain field: nothing about its
/// `ModifiedContent` depends on the value.
private struct AccentTag: ViewModifier {
    let accent: AccentName

    func body(content: Content) -> some View {
        HStack(spacing: 1) {
            content
            Text(verbatim: accent.wrappedValue)
        }
    }
}

/// An app property holding another in an optional field.
private struct OptionalAccent: DynamicProperty {
    var accent: AccentName?
}

/// Holds an `OptionalAccent`, first drawn with nothing in it.
private struct NestedNilFirstAccentView: View {
    let outer: OptionalAccent

    var body: some View {
        Text(verbatim: outer.accent?.wrappedValue ?? "none")
    }
}

/// An app property that is an enum, first drawn in its case with no payload.
private enum AccentSwitch: DynamicProperty {
    case off
    case on(AccentName)
}

private struct SwitchedAccentView: View {
    let accent: AccentSwitch

    var body: some View {
        switch accent {
        case .off: Text(verbatim: "off")
        case .on(let name): Text(verbatim: name.wrappedValue)
        }
    }
}

/// An app property that is a class, counting its `update()` calls.
private final class UpdatingObject: DynamicProperty {
    var updates = 0

    func update() {
        updates += 1
    }
}

/// Holds one weakly and one unowned.
private struct WeakHoldingView: View {
    weak var weakly: UpdatingObject?
    unowned let unownedly: UpdatingObject

    var body: some View {
        Text(verbatim: "\(weakly?.updates ?? -1) \(unownedly.updates)")
    }
}

@MainActor
private final class BindingTap {
    var binding: Binding<Int>?
}

private struct CountingView: View {
    let tap: BindingTap
    @Counter private var count: Int

    var body: some View {
        tap.binding = $count
        return Text(verbatim: "count \(count)")
    }
}

private struct AccentView: View {
    @AccentName private var accent: String

    var body: some View {
        Text(verbatim: accent)
    }
}

private struct UpdatingView: View {
    @Updating private var updates: Int

    init(log: UpdateLog) {
        _updates = Updating(log: log)
    }

    var body: some View {
        Text(verbatim: "\(updates)")
    }
}

@MainActor
@Suite("DynamicProperty")
struct DynamicPropertyTests {

    private func line<V: View>(_ view: V, context: RenderContext) -> String {
        renderToBuffer(view, context: context).lines.first?.stripped
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    @Test("@State inside an app's property wrapper is kept from frame to frame")
    func nestedStateSurvives() {
        let context = makeRenderContext(width: 20, height: 1)
        let tap = BindingTap()
        #expect(line(CountingView(tap: tap), context: context) == "count 0")
        tap.binding?.wrappedValue = 4
        #expect(line(CountingView(tap: tap), context: context) == "count 4")
    }

    @Test("@Environment inside an app's property wrapper reads where its view sits")
    func nestedEnvironmentResolves() {
        let context = makeRenderContext(width: 20, height: 1)
        #expect(line(AccentView(), context: context) == "plain")
        #expect(line(AccentView().environment(\.accentName, "teal"), context: context) == "teal")
    }

    @Test("update() runs before every body, even with nothing inside to bind")
    func updateRunsBeforeBody() {
        let context = makeRenderContext(width: 20, height: 1)
        let log = UpdateLog()
        #expect(line(UpdatingView(log: log), context: context) == "1")
        #expect(line(UpdatingView(log: log), context: context) == "2",
                "a second frame runs it again: the type is not cached as having nothing to do")
    }

    /// Decisions B4: SwiftUI writes back what `update()` changes in the
    /// property's own stored values, and so does TUIkit now.
    @Test("What update() stores in the property is what body reads, through a property inside another too")
    func updateWritesBack() {
        let context = makeRenderContext(width: 30, height: 1)
        #expect(line(ShoutedView().environment(\.accentName, "teal"), context: context) == "TEAL [TEAL]")
        #expect(line(ShoutedView(), context: context) == "PLAIN [PLAIN]")
    }

    /// The review of B4: where a field cannot be written back, update() must
    /// still run, as it did before write-back.
    @Test("update() still runs for a property in a view that is an enum, and inside an optional field")
    func updateRunsWhereNothingIsWrittenBack() {
        let context = makeRenderContext(width: 20, height: 1)
        let log = UpdateLog()
        #expect(line(UpdatingScreen.main(Updating(log: log)), context: context) == "1")
        #expect(line(UpdatingScreen.main(Updating(log: log)), context: context) == "2")

        // Both the holder's update (+100) and the one it holds (+1).
        let shared = UpdateLog()
        let holding = Holding(inner: Updating(log: shared), log: shared)
        #expect(line(OptionalHoldingView(holding: holding), context: context) == "101")
        #expect(line(OptionalHoldingView(holding: nil), context: context) == "-1")
    }

    /// The review of the write-back: a field whose type cannot hold a
    /// property is never loaded, because the runtime describes some at a
    /// layout other than the one stored and a load of one reads the bytes
    /// beside it. An exit test: loaded, the misread `String` is copied, which
    /// retains `poison` and crashes the process.
    #if _pointerBitWidth(_64)
        @Test("The write-back never loads a field that cannot hold a property, so a metatype's thin layout is never misread")
        func writeBackLoadsOnlyContainers() async {
            await #expect(processExitsWith: .success) {
                await MainActor.run {
                    let log = UpdateLog()
                    var view = MetatypeFieldsView(log: log)
                    updateDynamicProperties(of: &view)
                    #expect(log.updates == 1, "the app property beside the metatypes was updated")
                }
            }
        }
    #endif

    /// The review of the write-back: TUIkit's own `@GestureState` holds a
    /// `@State` the walk binds, but its `update()` does nothing, so a view
    /// holding it is not copied and listed on every body to run it.
    @Test("TUIkit's own @GestureState does not make its view run the app-property update")
    func gestureStateIsNotAnAppProperty() {
        let holdsAppProperty = bindStateProperties(
            of: GestureStateView(), identity: ViewIdentity(path: "Root/GestureState"), storage: StateStorage())
        #expect(!holdsAppProperty)
        let context = makeRenderContext(width: 20, height: 1)
        #expect(line(GestureStateView(), context: context) == "idle")
    }

    /// The review of the write-back: whether a type has anything to bind,
    /// resolve or update is kept per type, so it must not be decided from a
    /// value that holds nothing where another value of the type holds a
    /// property — a `nil` optional, an enum case with no payload. SwiftUI
    /// runs `update()` for the enum view's later payload (measured on macOS
    /// 15, session notes DYNP/probe/dp.swift, case 7).
    @Test("A type first drawn holding no property still updates, binds and resolves one it holds later")
    func firstValueDoesNotDecide() {
        let context = makeRenderContext(width: 20, height: 1)
        #expect(line(NilFirstHoldingView(holding: nil), context: context) == "-1")
        let shared = UpdateLog()
        let holding = Holding(inner: Updating(log: shared), log: shared)
        #expect(line(NilFirstHoldingView(holding: holding), context: context) == "101")

        #expect(line(BlankFirstScreen.blank, context: context) == "blank")
        #expect(line(BlankFirstScreen.main(Updating(log: UpdateLog())), context: context) == "1")

        #expect(line(NilFirstAccentView(accent: nil), context: context) == "none")
        #expect(
            line(NilFirstAccentView(accent: AccentName()).environment(\.accentName, "teal"), context: context)
                == "teal")
    }

    /// The second review of the per-type caches: the walks descend into a
    /// property or a modifier, which can hold nothing on one draw and a
    /// property on the next as a view can, so the type holding it must not be
    /// kept as having no environment from its first draw either.
    @Test("A property one level down, first drawn absent, has its environment resolved once it is there")
    func firstValueDoesNotDecideOneLevelDown() {
        let context = makeRenderContext(width: 20, height: 1)
        let text = Text(verbatim: "a")
        #expect(line(text.modifier(OptionalAccentTag(accent: nil)), context: context) == "a none")
        #expect(
            line(text.modifier(OptionalAccentTag(accent: AccentName())).environment(\.accentName, "teal"), context: context)
                == "a teal")

        #expect(line(NestedNilFirstAccentView(outer: OptionalAccent()), context: context) == "none")
        #expect(
            line(
                NestedNilFirstAccentView(outer: OptionalAccent(accent: AccentName())).environment(\.accentName, "teal"),
                context: context) == "teal")

        #expect(line(SwitchedAccentView(accent: .off), context: context) == "off")
        #expect(
            line(SwitchedAccentView(accent: .on(AccentName())).environment(\.accentName, "teal"), context: context)
                == "teal")
    }

    /// What keeps the caches worth having: a `ModifiedContent` whose modifier
    /// holds no optional property, enum or class is still kept per type, so it
    /// is not walked on every frame.
    @Test("A modifier with nothing that varies by value leaves its ModifiedContent cacheable")
    func plainModifierStaysCacheable() {
        #expect(!NestedProperties.walkDependsOnValue(ModifiedContent<Text, AccentTag>.self))
        #expect(!NestedProperties.walkDependsOnValue(ModifiedContent<Text, EmptyModifier>.self))
        #expect(NestedProperties.walkDependsOnValue(ModifiedContent<Text, OptionalAccentTag>.self))
    }

    /// What SwiftUI does, measured on macOS 15 (session notes
    /// DYNP/probe/dp.swift, cases 4 and 4b): an `unowned` property's type is
    /// the property's own, and its `update()` runs; a `weak` one's is an
    /// optional, and its `update()` does not.
    @Test("An unowned app property is updated and a weak one is not, as in SwiftUI")
    func unownedUpdatesWeakDoesNot() {
        let context = makeRenderContext(width: 20, height: 1)
        let weakObject = UpdatingObject()
        let unownedObject = UpdatingObject()
        #expect(line(WeakHoldingView(weakly: weakObject, unownedly: unownedObject), context: context) == "0 1")
        #expect(line(WeakHoldingView(weakly: weakObject, unownedly: unownedObject), context: context) == "0 2")
    }

    @Test("TUIkit's own property wrappers are DynamicProperty, as SwiftUI's are")
    func frameworkWrappersConform() {
        let state: any DynamicProperty = State(wrappedValue: 1)
        let binding: any DynamicProperty = Binding.constant(1)
        #expect(state is State<Int> && binding is Binding<Int>)
    }
}
