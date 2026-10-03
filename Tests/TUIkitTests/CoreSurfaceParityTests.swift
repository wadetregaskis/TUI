//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CoreSurfaceParityTests.swift
//
//  Small pieces of SwiftUI's core surface that SwiftUI source spells out and
//  TUIkit lacked: an optional `@State` with no initial value, an empty
//  `@ViewBuilder` closure, `AnyView(erasing:)`, `TupleView.value`, and so on.
//  Each test is the SwiftUI spelling plus what it must mean.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// An `@Observable` model with an identity, for `Bindable`.
@Observable
private final class Account: Identifiable {
    let id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// `@State` on an optional with no `= nil`: SwiftUI's `State.init()`.
private struct OptionalSelection: View {
    @State private var selection: Int?

    var body: some View {
        Text(selection.map(String.init) ?? "none")
    }
}

@MainActor
@Suite("Core SwiftUI surface")
struct CoreSurfaceParityTests {

    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 20, height: 3))
            .lines.map { $0.stripped }
    }

    /// The declaration alone does not reach `State.init()` — Swift
    /// default-initialises an optional wrapped property through
    /// `init(wrappedValue: nil)` — so the initialiser is also called by name,
    /// which is how generic code and macros reach it.
    @Test("An optional @State with no value starts nil")
    func optionalStateStartsNil() {
        #expect(State<Int?>().wrappedValue == nil)
        #expect(lines(OptionalSelection()).first == "none")
    }

    @Test("An empty @ViewBuilder closure builds an EmptyView")
    func emptyClosureIsEmptyView() {
        @ViewBuilder func nothing() -> some View {}
        #expect(type(of: nothing()) == EmptyView.self)
    }

    @Test("buildIf is buildOptional by its older name")
    func buildIfMatchesBuildOptional() {
        let present = ViewBuilder.buildIf(Text("x"))
        let absent = ViewBuilder.buildIf(Text?.none)
        #expect(present != nil && absent == nil)
    }

    @Test("AnyView(erasing:) draws what it erases")
    func anyViewErasing() {
        #expect(lines(AnyView(erasing: Text("erased"))) == lines(Text("erased")))
    }

    @Test("TupleView takes and gives back a tuple")
    func tupleViewValue() {
        let tuple = TupleView((Text("a"), Text("b")))
        let (first, second) = tuple.value
        #expect(first == Text("a") && second == Text("b"))
    }

    @Test("EquatableView exposes its content")
    func equatableViewContent() {
        #expect(EquatableView(content: Text("same")).content == Text("same"))
    }

    @Test("Binding and Bindable borrow their value's identity")
    func borrowedIdentity() {
        let account = Account(id: 7, name: "Ada")
        #expect(Bindable(account).id == 7)
        #expect(Binding.constant(account).id == 7)
        #expect(Bindable<Account>.ID.self == Int.self)
        #expect(Binding<Account>.ID.self == Int.self)
    }

    @Test("A UnitPoint made with no arguments is zero, and it round-trips")
    func unitPoint() throws {
        #expect(UnitPoint() == .zero)
        let point = UnitPoint(x: 0.25, y: 1)
        let decoded = try JSONDecoder().decode(
            UnitPoint.self, from: try JSONEncoder().encode(point))
        #expect(decoded == point)
    }
}
