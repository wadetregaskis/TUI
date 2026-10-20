//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PlaceBoundPropertyTests.swift
//
//  `@Namespace`, `@FocusState`, `@FocusedValue` and `@FocusedBinding` keep
//  what they are bound to behind a reference every copy shares, as `@State`
//  and `@Environment` did before DYNV bug 1's fix (StateSharedValueTests). So
//  one view value drawn at two places ended bound to the second place, and a
//  closure made in the first place's body read the second place's namespace
//  or focus store. SwiftUI gives each place its own namespace (measured,
//  `Tools/SwiftUIProbes/Dynamic property discovery/twoplaces.out`); each of
//  the four is now bound per place, as `@State` and `@Environment` are
//  (decisions DYNVFIX, B-DYNVFIX-5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What the bodies hand out, in the order they ran.
@MainActor
private final class PlaceTaps {
    /// Each body's namespace as it read it, and a closure that reads it later.
    var namespaces: [(read: Namespace.ID, later: () -> Namespace.ID)] = []
    /// Each body's focus-state binding.
    var focusBindings: [FocusState<Bool>.Binding] = []
}

/// A view with a namespace and a focus state of its own.
private struct Tally: View {
    let taps: PlaceTaps
    @Namespace private var namespace
    @FocusState private var isFocused: Bool

    var body: some View {
        let namespace = self.namespace
        taps.namespaces.append((namespace, { self.namespace }))
        taps.focusBindings.append($isFocused)
        return Text(verbatim: "x")
    }
}

/// One view value drawn twice.
private struct SameTallyTwice: View {
    let taps: PlaceTaps

    var body: some View {
        let tally = Tally(taps: taps)
        return VStack {
            tally
            tally
        }
    }
}

@MainActor
@Suite("@Namespace and @FocusState are bound per place")
struct PlaceBoundPropertyTests {
    @Test("One view value drawn twice has a namespace for each place, and a closure from each body reads its own")
    func namespacePerPlace() throws {
        let taps = PlaceTaps()
        _ = renderToBuffer(SameTallyTwice(taps: taps), context: makeRenderContext(width: 10, height: 2))
        // Each place's body runs to measure and to draw.
        try #require(!taps.namespaces.isEmpty)
        #expect(Set(taps.namespaces.map(\.read)).count == 2, "a namespace for each place, as SwiftUI's")
        for (index, body) in taps.namespaces.enumerated() {
            #expect(body.later() == body.read, "body \(index)'s closure reads the namespace its body read")
        }
    }

    @Test("One view value drawn twice has a focus store for each place")
    func focusStatePerPlace() throws {
        let taps = PlaceTaps()
        _ = renderToBuffer(SameTallyTwice(taps: taps), context: makeRenderContext(width: 10, height: 2))
        // Each place's body runs to measure and to draw. The focus a store
        // reads and moves is the manager's, under the store's key: what keeps
        // the places apart is a key for each.
        let keys = taps.focusBindings.map(\.store.storeID)
        #expect(Set(keys).count == 2, "a store keyed by each place: \(keys)")
    }

    /// The rule each follows: a reference bound at another place in this pass
    /// is a second place's, which takes one of its own; one bound elsewhere in
    /// an earlier pass — a value kept and moved — is rebound where it lies.
    @Test("A second place in one pass takes a reference of its own; a value moved in a later pass is rebound")
    func theRule() {
        var stamp = PlaceStamp<String>()
        #expect(!stamp.isSecondPlace("a", in: 1), "never bound")
        stamp.stamp("a", in: 1)
        #expect(!stamp.isSecondPlace("a", in: 1), "the same place again")
        #expect(stamp.isSecondPlace("b", in: 1), "another place, the same pass")
        #expect(!stamp.isSecondPlace("b", in: 2), "another place, a later pass: moved")
    }

    @Test("@FocusedValue and @FocusedBinding take a reader of their own at a second place in one pass")
    func focusedReadersPerPlace() {
        let context = makeRenderContext(width: 10, height: 2)
        let first = context.withChildIdentity(type: Text.self, index: 0).identity
        let second = context.withChildIdentity(type: Text.self, index: 1).identity
        var value = FocusedValue(\FocusedValues.placeProbeValue)
        let environment = context.environment
        withUnsafeMutablePointer(to: &value) { pointer in
            let address = UnsafeMutableRawPointer(pointer)
            #expect(!FocusedValue<Int>.resolveEnvironment(at: address, environment, place: first, pass: 7))
            #expect(FocusedValue<Int>.resolveEnvironment(at: address, environment, place: second, pass: 7))
            #expect(!FocusedValue<Int>.resolveEnvironment(at: address, environment, place: second, pass: 7))
        }
        var binding = FocusedBinding(\FocusedValues.placeProbeBinding)
        withUnsafeMutablePointer(to: &binding) { pointer in
            let address = UnsafeMutableRawPointer(pointer)
            #expect(!FocusedBinding<Int>.resolveEnvironment(at: address, environment, place: first, pass: 7))
            #expect(FocusedBinding<Int>.resolveEnvironment(at: address, environment, place: second, pass: 7))
            #expect(!FocusedBinding<Int>.resolveEnvironment(at: address, environment, place: first, pass: 8))
        }
    }
}

private struct PlaceProbeValueKey: FocusedValueKey {
    typealias Value = Int
}

private struct PlaceProbeBindingKey: FocusedValueKey {
    typealias Value = Binding<Int>
}

extension FocusedValues {
    fileprivate var placeProbeValue: Int? {
        get { self[PlaceProbeValueKey.self] }
        set { self[PlaceProbeValueKey.self] = newValue }
    }

    fileprivate var placeProbeBinding: Binding<Int>? {
        get { self[PlaceProbeBindingKey.self] }
        set { self[PlaceProbeBindingKey.self] = newValue }
    }
}
