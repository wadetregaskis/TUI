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

    @Test("TUIkit's own property wrappers are DynamicProperty, as SwiftUI's are")
    func frameworkWrappersConform() {
        let state: any DynamicProperty = State(wrappedValue: 1)
        let binding: any DynamicProperty = Binding.constant(1)
        #expect(state is State<Int> && binding is Binding<Int>)
    }
}
