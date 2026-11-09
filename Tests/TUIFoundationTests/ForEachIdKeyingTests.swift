//  🖥️ TUI — A Terminal UI framework for Swift
//  ForEachIdKeyingTests.swift
//
//  `ForEach` keys each row by its id, and SwiftUI tells ids apart by their
//  `Hashable` value. TUI keyed rows by the id's DESCRIPTION, so two distinct
//  ids that print alike — two `Date`s within one second — shared one
//  identity: the second row read the first row's `@State`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("ForEach keys rows by the id's value")
struct ForEachIdKeyingTests {
    /// Shows the label its `@State` was first given, so a row that shares
    /// another's identity shows the other's label.
    private struct Row: View {
        @State private var shown: String
        init(label: String) { _shown = State(initialValue: label) }
        var body: some View { Text(shown) }
    }

    @Test("Two Dates in one second keep their own state")
    func datesWithOneDescriptionAreDistinctRows() {
        let early = Date(timeIntervalSinceReferenceDate: 0)
        let late = Date(timeIntervalSinceReferenceDate: 0.5)
        #expect(String(describing: early) == String(describing: late), "the premise: they print alike")

        let view = VStack {
            ForEach([early, late], id: \.self) { date in
                Row(label: "at \(date.timeIntervalSinceReferenceDate)")
            }
        }
        let lines = renderToBuffer(view, context: makeRenderContext(width: 20, height: 4))
            .lines.map(\.stripped).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        #expect(lines == ["at 0.0", "at 0.5"], "\(lines)")
    }

    @Test("identityKey tells apart ids that print alike")
    func keysOfAlikeIdsDiffer() {
        let early = Date(timeIntervalSinceReferenceDate: 0)
        let late = Date(timeIntervalSinceReferenceDate: 0.5)
        #expect(identityKey(early) != identityKey(late))
        #expect(identityKey(early) == identityKey(Date(timeIntervalSinceReferenceDate: 0)))
    }

    /// Scroll targeting (`scrollTo`, `ScrollPosition`, `ScrollAnchor`) keys a
    /// target from an `AnyHashable`'s base, a ForEach row from the id as its
    /// own type: the two have to agree, or a scroll request misses its row.
    @Test("An erased id keys like the id itself")
    func erasedIdsKeyAlike() {
        let date = Date(timeIntervalSinceReferenceDate: 0.5)
        #expect(identityKey(AnyHashable(date).base) == identityKey(date))
        #expect(identityKey(AnyHashable(date)) == identityKey(date))
        #expect(identityKey(AnyHashable(5).base) == identityKey(5))
        #expect(identityKey(AnyHashable("row").base) == identityKey("row"))
        enum Kind: Hashable { case alpha }
        #expect(identityKey(AnyHashable(Kind.alpha).base) == identityKey(Kind.alpha))
    }
}
