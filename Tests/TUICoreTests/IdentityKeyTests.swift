//  🖥️ TUI — A Terminal UI framework for Swift
//  IdentityKeyTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUICore

@Suite("identityKey")
struct IdentityKeyTests {

    /// The fast paths must be invisible: the key an element gets is exactly the
    /// key `String(describing:)` produced before, or rows silently change
    /// identity and lose their `@State`, focus and scroll targeting.
    @Test("matches String(describing:) for the types it fast-paths")
    func matchesDescribingForFastPathedTypes() {
        #expect(identityKey(42) == String(describing: 42))
        #expect(identityKey(-7) == String(describing: -7))
        #expect(identityKey(0) == String(describing: 0))
        #expect(identityKey(Int.min) == String(describing: Int.min))
        #expect(identityKey("row") == String(describing: "row"))
        #expect(identityKey("") == String(describing: ""))
        #expect(identityKey("has spaces & (parens)") == String(describing: "has spaces & (parens)"))

        let uuid = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        #expect(identityKey(uuid) == String(describing: uuid))
    }

    /// A dynamic cast looks *through* `Optional` and `AnyHashable`, so a bare
    /// `id as? Int` would re-key every row with an optional id — `"5"` where it
    /// is `"Optional(5)#…"`. The metatype comparison in front of each cast is
    /// what prevents that, and this is the test that would catch its removal.
    @Test("optionals are not unwrapped by the fast path")
    func optionalIdsKeepTheirDescription() {
        let optional: Int? = 5
        #expect(identityKey(optional).hasPrefix("Optional(5)#"))
        #expect(identityKey(optional) != identityKey(5))

        let none: Int? = nil
        #expect(identityKey(none).hasPrefix("nil#"))

        let optionalString: String? = "row"
        #expect(identityKey(optionalString).hasPrefix("Optional(\"row\")#"))
    }

    /// An `AnyHashable` id is keyed as the value it wraps, so a scroll target
    /// (an `AnyHashable`) finds the row its value keyed.
    @Test("AnyHashable is keyed as the value it wraps")
    func erasedIdsKeyAsTheirValue() {
        #expect(identityKey(AnyHashable(5)) == "5")
        #expect(identityKey(AnyHashable("row")) == "row")
    }

    /// A type whose description names each value once is keyed by it alone;
    /// any other by its description and its hash value.
    @Test("one-to-one descriptions are the key; others gain the hash")
    func otherTypes() {
        enum Kind: String { case alpha, beta }
        struct Composite: Hashable {
            let section: Int
            let row: Int
        }

        #expect(identityKey(UInt8(200)) == "200")
        #expect(identityKey(Int64(-3)) == "-3")
        #expect(identityKey(true) == "true")
        #expect(identityKey(Character("x")) == "x")

        #expect(identityKey(Kind.alpha).hasPrefix("alpha#"))
        #expect(identityKey(Kind.alpha) != identityKey(Kind.beta))
        #expect(identityKey(Composite(section: 1, row: 2)).hasPrefix("Composite(section: 1, row: 2)#"))
        #expect(identityKey(3.5).hasPrefix("3.5#"))
        let half = 3.5
        #expect(identityKey(3.5) == identityKey(half), "a key is stable")
    }

    /// Distinct elements must land on distinct keys — the property `ForEach`
    /// row identity depends on.
    @Test("distinct ids give distinct keys")
    func distinctIdsAreDistinct() {
        let keys = (0..<500).map { identityKey($0) }
        #expect(Set(keys).count == keys.count)
    }
}
