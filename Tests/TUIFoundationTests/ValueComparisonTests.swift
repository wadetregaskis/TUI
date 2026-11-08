//  🖥️ TUI — A Terminal UI framework for Swift
//  ValueComparisonTests.swift
//
//  What a comparison made from a type says of two values: each rule in
//  `ValueComparison`'s list, and what it refuses for the walk it shares with the
//  value hash.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIView

@MainActor
@Suite("Comparing two values from their type alone")
struct ValueComparisonTests {
    private let plans = ValueHashPlans()

    private func same<T>(_ left: T, _ right: T, strict: Bool = false) -> Bool? {
        plans.comparison(for: T.self)?.equal(left, right, strict: strict, plans: plans)
    }

    private final class Object {}

    private struct Plain: Equatable {
        var number = 1
    }

    /// Not `Equatable`, so it goes by its fields, with padding between them.
    private struct Padded {
        var byte: UInt8 = 1
        var word = 2
    }

    @Test("`@State`, `@Environment`, `@FocusState` and `@Namespace` are skipped")
    func boundFields() {
        struct Holder {
            @State var state = 1
            @Environment(\.isEnabled) var enabled
            @FocusState var focus: Bool
            @Namespace var space
            var number: Int
        }
        #expect(same(Holder(number: 1), Holder(number: 1)) == true)
        #expect(same(Holder(state: 2, number: 1), Holder(state: 3, number: 1)) == true)
        #expect(same(Holder(number: 1), Holder(number: 2)) == false)
    }

    @Test("A field's own `==` decides, and an array or string compares by value")
    func equatables() {
        struct Holder {
            var list: [Int]
            var text: String
            var plain: Plain
        }
        let text = String(repeating: "long enough to be on the heap ", count: 4)
        #expect(same(Holder(list: [1, 2], text: text, plain: Plain()), Holder(list: [1, 2], text: text + "", plain: Plain())) == true)
        #expect(same(Holder(list: [1, 2], text: "", plain: Plain()), Holder(list: [1, 3], text: "", plain: Plain())) == false)
        #expect(same(Holder(list: [], text: "a", plain: Plain()), Holder(list: [], text: "b", plain: Plain())) == false)
    }

    @Test("A type's own `==` is its whole answer, whatever else it holds")
    func ownEquality() {
        struct Ignoring: Equatable {
            var key: Int
            var action: () -> Void
            static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
        }
        #expect(same(Ignoring(key: 1) {}, Ignoring(key: 1) {}, strict: true) == true)
        #expect(same(Ignoring(key: 1) {}, Ignoring(key: 2) {}) == false)
    }

    @Test("A closure and a `Binding` are ignored, unless strict, where they are changed")
    func opaque() {
        struct Closure {
            var number: Int
            var action: () -> Int
        }
        #expect(same(Closure(number: 1) { 1 }, Closure(number: 1) { 2 }) == true)
        #expect(same(Closure(number: 1) { 1 }, Closure(number: 2) { 1 }) == false)
        #expect(same(Closure(number: 1) { 1 }, Closure(number: 1) { 1 }, strict: true) == false)

        struct Bound {
            var binding: Binding<Int>
        }
        let binding = Binding.constant(1)
        #expect(same(Bound(binding: binding), Bound(binding: binding)) == true)
        #expect(same(Bound(binding: binding), Bound(binding: binding), strict: true) == false)
    }

    @Test("An optional compares its case, then its payload by its own comparison")
    func optionals() {
        struct Holder {
            var action: (() -> Void)?
        }
        #expect(same(Holder(action: nil), Holder(action: nil), strict: true) == true)
        #expect(same(Holder(action: nil), Holder {}) == false)
        #expect(same(Holder {}, Holder {}) == true)
        #expect(same(Holder {}, Holder {}, strict: true) == false)
    }

    @Test("A conditional compares its branch, then that branch's content")
    func conditionals() {
        typealias Branch = ConditionalView<Text, EmptyView>
        #expect(same(Branch.trueContent(Text("a")), Branch.trueContent(Text("a"))) == true)
        #expect(same(Branch.trueContent(Text("a")), Branch.trueContent(Text("b"))) == false)
        #expect(same(Branch.trueContent(Text("a")), Branch.falseContent(EmptyView())) == false)
    }

    @Test("A class compares by identity")
    func classes() {
        struct Holder {
            var object: Object
        }
        let object = Object()
        #expect(same(Holder(object: object), Holder(object: object)) == true)
        #expect(same(Holder(object: object), Holder(object: Object())) == false)
    }

    @Test("Bytes between fields are not read: padding says nothing")
    func padding() {
        var left = Padded()
        var right = Padded()
        // A value laid over memory whose padding byte differs.
        withUnsafeMutableBytes(of: &left) { unsafe $0[1] = 0xAA }
        withUnsafeMutableBytes(of: &right) { unsafe $0[1] = 0x55 }
        #expect(plans.comparison(for: Padded.self)?.equal(left, right, strict: true, plans: plans) == true)
        right.word = 3
        #expect(plans.comparison(for: Padded.self)?.equal(left, right, strict: false, plans: plans) == false)
    }

    @Test("Nesting: a struct in a tuple in a struct, each field by its rule")
    func nested() {
        struct Inner {
            var number: Int
            var action: () -> Void
        }
        struct Outer {
            var pair: (Inner, String)
        }
        #expect(same(Outer(pair: (Inner(number: 1) {}, "a")), Outer(pair: (Inner(number: 1) {}, "a"))) == true)
        #expect(same(Outer(pair: (Inner(number: 1) {}, "a")), Outer(pair: (Inner(number: 2) {}, "a"))) == false)
        #expect(same(Outer(pair: (Inner(number: 1) {}, "a")), Outer(pair: (Inner(number: 1) {}, "b"))) == false)
    }

    @Test("What has no comparison: an existential, a payload enum, another dynamic property")
    func refusals() {
        struct HoldsExistential {
            var value: any Sendable
        }
        enum Payload {
            case one(Int), two(String)
        }
        struct HoldsEnum {
            var value: Payload
        }
        struct Custom: DynamicProperty {
            var number = 0
        }
        struct Empty: DynamicProperty {}
        struct HoldsProperty {
            var value: Custom
        }
        struct HoldsEmptyProperty {
            var value: Empty
        }
        struct HoldsMetatype {
            var value: Int.Type?
        }
        #expect(plans.comparison(for: HoldsExistential.self) == nil)
        #expect(plans.comparison(for: HoldsEnum.self) == nil)
        #expect(plans.comparison(for: HoldsProperty.self) == nil)
        #expect(plans.comparison(for: HoldsEmptyProperty.self) == nil)
        #expect(plans.comparison(for: HoldsMetatype.self) == nil)
    }

    @Test("A struct whose metadata is gone has no comparison: it is the walk a hash takes")
    func strippedMetadata() {
        // What that walk refuses (a gap in a C struct, which may be a bitfield,
        // above all) is pinned by the plan's own tests.
        let stripped = unsafe ValueHashPlanBuilder(listFields: { _ in [] }, comparing: true)
        guard case .failure = unsafe stripped.items(for: Padded.self) else {
            Issue.record("a struct with no field metadata was given a comparison")
            return
        }
    }

    @Test("A view's fields, as an app's composite would hold them")
    func viewContent() {
        struct Row: View {
            let title: String
            let action: @MainActor @Sendable () -> Void
            var body: some View {
                VStack {
                    Text(verbatim: title)
                    Button(title, action: action)
                }
            }
        }
        #expect(plans.comparison(for: Row.self)?.holdsOpaque == true)
        #expect(same(Row(title: "a") {}, Row(title: "a") {}) == true)
        #expect(same(Row(title: "a") {}, Row(title: "b") {}) == false)
    }
}
