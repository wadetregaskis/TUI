//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowEligibilityTests.swift
//
//  Which memoized rows can be re-checked by their value when a parent writes
//  (Option C, C4p3): an `Equatable` view the type walk accepts.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkitCore
@testable import TUIkitView

@Observable
private final class RowModel {
    var title = ""
}

/// Row values of the shapes Option C's reviews named. Not views: eligibility is
/// a question about a type, and these keep the fixtures free of rendering.
private struct PlainRow: Equatable {
    let title: String
    let count: Int
}

private struct NotEquatableRow {
    let title: String
}

private struct BindingRow: Equatable {
    @Binding var done: Bool
    let title: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }
}

private struct NestedBindingRow: Equatable {
    struct Inner { var flag: Binding<Bool>? }
    let inner: Inner
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

private struct ExistentialRow: Equatable {
    let payload: any Sendable
    let title: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }
}

private struct ModelRow: Equatable {
    let model: RowModel
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model }
}

private struct BindableRow: Equatable {
    @Bindable var model: RowModel
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model }
}

private struct ActionRow: Equatable {
    let title: String
    let action: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }
}

@MainActor
@Suite("Which rows can be re-checked by their value")
struct RowEligibilityTests {

    @Test("An Equatable row of plain values can be re-checked")
    func plain() {
        #expect(RevalidationState().eligibility(ofRowsOf: PlainRow.self) == .eligible)
    }

    @Test("A row that is not Equatable cannot: there is no == to re-check it by")
    func notEquatable() {
        #expect(RevalidationState().eligibility(ofRowsOf: NotEquatableRow.self) == .notEquatable)
    }

    @Test("A Binding is refused, held directly or inside a field")
    func bindings() {
        let state = RevalidationState()
        guard case .refused(.readsItsSource)? = Optional(state.eligibility(ofRowsOf: BindingRow.self)) else {
            Issue.record("a row holding a Binding was accepted: \(state.eligibility(ofRowsOf: BindingRow.self))")
            return
        }
        guard case .refused(.readsItsSource)? = Optional(state.eligibility(ofRowsOf: NestedBindingRow.self)) else {
            Issue.record("a Binding in an optional field was accepted")
            return
        }
    }

    @Test("An existential is refused: a hand-written == over it cannot see all of it")
    func existential() {
        guard case .refused(.existential)? = Optional(RevalidationState().eligibility(ofRowsOf: ExistentialRow.self))
        else {
            Issue.record("a row holding an existential was accepted")
            return
        }
    }

    @Test("A model held by reference, or through Bindable, is accepted: its reads are observed where they are made")
    func models() {
        let state = RevalidationState()
        #expect(state.eligibility(ofRowsOf: ModelRow.self) == .eligible)
        #expect(state.eligibility(ofRowsOf: BindableRow.self) == .eligible)
    }

    @Test("A closure is accepted: an action is the app's == to cover, as SwiftUI's is")
    func closure() {
        #expect(RevalidationState().eligibility(ofRowsOf: ActionRow.self) == .eligible)
    }

    @Test("Each type is decided once")
    func decidedOnce() {
        let state = RevalidationState()
        _ = state.eligibility(ofRowsOf: PlainRow.self)
        let walks = state.typeWalk.walks
        _ = state.eligibility(ofRowsOf: PlainRow.self)
        #expect(state.typeWalk.walks == walks)
    }
}
