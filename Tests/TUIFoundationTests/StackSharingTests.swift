//  🖥️ TUI — A Terminal UI framework for Swift
//  StackSharingTests.swift
//
//  A row shares its width among children of one priority as SwiftUI's does,
//  and since 2026-10-15 a column its height (deviation L14, closed by the
//  owner's ruling of 2026-10-13: "follow SwiftUI's behaviour"): the least flexible first, each offered an equal
//  share of what is left, spacers what the others leave. Each case is one
//  SwiftUI measured on macOS 15 (`Tools/SwiftUIProbes/Layout priority/`,
//  `share.out` and `flex.out`), a character of its monospaced font standing
//  for a cell — where its text snaps a share to a narrower ellipsis, TUI's
//  whole cells give the share whole.
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
@Suite("A stack shares its length as SwiftUI's does")
struct StackSharingTests {
    private func row<V: View>(width: Int, spacing: Int = 0, @ViewBuilder _ content: () -> V) -> String {
        renderToBuffer(HStack(spacing: spacing) { content() }, context: makeRenderContext(width: width, height: 3))
            .lines.first?.stripped ?? ""
    }

    @Test("A short text keeps its length beside a long one, on either side (SwiftUI: long-short, short-long)")
    func shortKeepsItsLength() {
        // SwiftUI: 8 and 3, 3 and 8 (its ellipsis snaps the long one a cell short).
        let longFirst = row(width: 12) {
            Text("aaaaaaaaaa").lineLimit(1)
            Text("bbb").lineLimit(1)
        }
        #expect(longFirst == "aaaaaaaa…bbb", "\(longFirst)")
        let shortFirst = row(width: 12) {
            Text("aaa").lineLimit(1)
            Text("bbbbbbbbbb").lineLimit(1)
        }
        #expect(shortFirst == "aaabbbbbbbb…", "\(shortFirst)")
    }

    @Test("Children of one length share the row (SwiftUI: equal, three-equal)")
    func equalShare() {
        // SwiftUI: 6 and 5; 4, 3 and 4.
        let two = row(width: 12) {
            Text("aaaaaaaaaa").lineLimit(1)
            Text("bbbbbbbbbb").lineLimit(1)
        }
        #expect(two == "aaaaa…bbbbb…", "\(two)")
        let three = row(width: 12) {
            Text("aaaaaaaaaa").lineLimit(1)
            Text("bbbbbbbbbb").lineLimit(1)
            Text("cccccccccc").lineLimit(1)
        }
        #expect(three == "aaa…bbb…ccc…", "\(three)")
    }

    @Test("A child that fills shares with the others, and takes all a spacer does not keep (SwiftUI: t10|color|t10, flex-vs-spacer)")
    func fillingShares() {
        // SwiftUI gives a `Color` between two texts its equal share: 6, 8, 6.
        let between = row(width: 20) {
            Text("aaaaaaaaaa").lineLimit(1)
            Text("ff").frame(maxWidth: .infinity)
            Text("bbbbbbbbbb").lineLimit(1)
        }
        #expect(between.hasPrefix("aaaaaa…"), "\(between)")
        #expect(between.hasSuffix("bbbbbb…"), "\(between)")
        // And beside a spacer, everything but the spacer's minimum: a filling
        // frame used to split the row with it.
        let widths = distributeLinearSpace(
            naturalSizes: [2, 0], isFlexible: [true, true], available: 20, isSpacer: { $0 == 1 })
        #expect(widths == [20, 0])
    }

    @Test("A frame of a fixed width keeps it, as SwiftUI's rigid frame does")
    func frameIsRigid() {
        // Four children over 23 cells: the framed label is the widest, and
        // were it as flexible as its length it would be dealt last and cut
        // to its share.
        let drawn = row(width: 23, spacing: 1) {
            Text("label").frame(width: 8, alignment: .leading)
            Text("aaaaa").lineLimit(1)
            Text("bbbbb").lineLimit(1)
            Text("ccccc").lineLimit(1)
        }
        #expect(drawn.hasPrefix("label   "), "\(drawn)")
    }

    @Test("Where even the minimums do not fit, the children are placed in order, the leading ones whole")
    func minimumsThatDoNotFitPlaceInOrder() {
        // Two children that cannot shrink, in less than both: SwiftUI's stack
        // would overflow its frame; TUI's keeps the first whole and cuts the
        // second, never going blank.
        let widths = distributeLinearSpace(naturalSizes: [3, 3], isFlexible: [false, false], available: 4)
        #expect(widths == [3, 1])
        // Where they can shrink, they share.
        let shared = distributeLinearSpace(
            naturalSizes: [3, 3], isFlexible: [false, false], available: 4, minimumSize: { _ in 1 })
        #expect(shared == [2, 2])
    }

    @Test("A column shares its height as a row shares its width (SwiftUI: a stack shares either axis)")
    func columnShares() {
        let column = renderToBuffer(
            VStack(spacing: 0) {
                ScrollView { VStack(spacing: 0) { ForEach(0..<2, id: \.self) { Text("a\($0)") } } }
                ScrollView { VStack(spacing: 0) { ForEach(0..<18, id: \.self) { Text("b\($0)") } } }
            }
            .frame(height: 10, alignment: .top),
            context: makeRenderContext(width: 8, height: 10)
        ).lines.map(\.stripped)
        // Two scroll views of two rows' and eighteen rows' content, in ten: each
        // is dealt half, as SwiftUI deals them, where placed in order (as
        // columns were until 2026-10-15) the first kept its two and the second
        // took the eight left.
        #expect(column.count == 10)
        #expect(column[0].hasPrefix("a0") && column[1].hasPrefix("a1"), "\(column)")
        #expect(column[2...4].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(column)")
        #expect(column[5].hasPrefix("b0"), "\(column)")
    }

    @Test("A child offered less than its ideal takes what it answers, leaving the rest to those after it")
    func askedAtItsOffer() {
        // The first is offered 6 of its 10 and answers 2 — a `ViewThatFits`
        // falling back to a narrower candidate — so the second is offered the 4 left.
        let widths = distributeLinearSpace(
            naturalSizes: [10, 10], isFlexible: [false, false], available: 12,
            minimumSize: { _ in 0 }, sizeAt: { index, offer in index == 0 ? 2 : offer })
        #expect(widths == [2, 10])
    }

    @Test("A spacer left nothing keeps no gap: a bar's item as wide as the bar is drawn whole")
    func idleSpacerGivesBackItsGap() {
        // The toolbar's row: a `Spacer(minLength: 0)` before an item that fills
        // the bar. Reserving the spacer's gap cut the item a column short.
        let widths = distributeLinearSpace(
            naturalSizes: [0, 26], isFlexible: [true, false], available: 26, spacing: 1,
            isSpacer: { $0 == 0 }, minimumSize: { _ in 0 })
        #expect(widths == [0, 26])
    }
}
