//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListMinimumRowHeightTests.swift
//
//  `\.defaultMinListRowHeight` and `\.defaultMinListHeaderHeight`: a list's
//  rows (and its section headers) are at least that many lines tall, their
//  content centred in the lines they are given.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("List minimum row height")
struct ListMinimumRowHeightTests {
    private func lines(_ view: some View, height: Int = 14) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 20, height: height)).lines.map(\.stripped)
    }

    private func row(_ name: String, in lines: [String]) -> Int? {
        lines.firstIndex { $0.contains(name) }
    }

    @Test("Each row is at least the minimum, its content centred, in a looped list")
    func loopedRows() {
        let drawn = lines(
            List(["one", "two"], id: \.self) { Text($0) }
                .environment(\.defaultMinListRowHeight, 3))
        guard let one = row("one", in: drawn), let two = row("two", in: drawn) else {
            Issue.record("\(drawn)")
            return
        }
        #expect(two - one == 3, "three lines a row: \(drawn)")
        // One blank line above "one", inside the border.
        #expect(one == 2, "centred: \(drawn)")
    }

    @Test("Hand-written rows and a taller row: only the short ones grow")
    func staticRows() {
        let drawn = lines(
            List {
                Text("short")
                VStack(spacing: 0) {
                    Text("tall 1")
                    Text("tall 2")
                    Text("tall 3")
                    Text("tall 4")
                }
                Text("after")
            }
            .environment(\.defaultMinListRowHeight, 2))
        guard let short = row("short", in: drawn), let tall = row("tall 1", in: drawn),
            let after = row("after", in: drawn)
        else {
            Issue.record("\(drawn)")
            return
        }
        #expect(tall - short == 2, "the short row takes two lines: \(drawn)")
        #expect(after - tall == 4, "the tall row keeps its own four: \(drawn)")
    }

    @Test("Section headers grow to the header minimum, and are left alone without one")
    func headers() {
        func drawn(_ minimum: Int?) -> [String] {
            lines(
                List {
                    Section("Head") {
                        Text("row")
                    }
                }
                .environment(\.defaultMinListHeaderHeight, minimum))
        }
        let natural = drawn(nil)
        let tall = drawn(3)
        guard let head = row("Head", in: natural), let first = row("row", in: natural),
            let tallFirst = row("row", in: tall)
        else {
            Issue.record("\(natural) \(tall)")
            return
        }
        #expect(first - head == 1, "\(natural)")
        #expect(tallFirst - first == 2, "the header takes three lines: \(tall)")
    }

    @Test("The defaults: one line a row, and no header minimum")
    func defaults() {
        #expect(EnvironmentValues().defaultMinListRowHeight == 1)
        #expect(EnvironmentValues().defaultMinListHeaderHeight == nil)
    }
}
