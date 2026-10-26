//  🖥️ TUI — A Terminal UI framework for Swift
//  StackGlideMemoTests.swift
//
//  A stack's children gliding inside a memoized subtree move frame by frame,
//  exactly as they do in a subtree nothing memoizes: the glide is a function of
//  the clock, and a memo that kept its first frame would freeze it there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// A card whose detail grows and shrinks, memoized by its value: the row
/// below the detail glides inside the memoized view, the page's row below the
/// card outside it.
private struct GlidingCard: View, @MainActor Equatable {
    let expanded: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.expanded == rhs.expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("card")
            // A branch swap, not a transition: a transitioning view is drawn
            // afresh every frame anyway, and would hide a memo that froze the
            // glide.
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Text("DETAIL")
                    Text("DETAIL")
                    Text("DETAIL")
                    Text("DETAIL")
                }
            } else {
                Text("-")
            }
            Text("tail")
        }
    }
}

private struct GlidingPage: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("toggle") {
                withAnimation(.linear(duration: 1)) { expanded.toggle() }
            }
            GlidingCard(expanded: expanded).equatable()
            Text("below")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct GlidingApp: App {
    var body: some Scene {
        WindowGroup { GlidingPage() }
    }
}

@MainActor
@Suite("A glide inside a memoized subtree moves on every frame")
struct StackGlideMemoTests {

    /// The card is shown, then hidden, each inside a one-second
    /// `withAnimation`. Every frame of both is compared with an instance that
    /// clears its render cache each frame, and the rows are seen to move.
    @Test("Each frame of a glide is the frame an uncached app draws")
    func glideMatchesUncached() {
        let warm = HeadlessApp(GlidingApp(), width: 30, height: 14)
        let cold = HeadlessApp(GlidingApp(), width: 30, height: 14)
        cold.clearsRenderCacheEachFrame = true
        var tick: Int64 = 0
        // Each app presses and draws before the other presses: the change's
        // transaction waits in the process's one pending slot until a frame
        // consumes it.
        func frame(pressing: Bool = false) {
            let now = AnimationClock.nanoseconds(atTick: tick)
            for app in [warm, cold] {
                if pressing { #expect(app.send(KeyEvent(key: .enter)), "precondition: the button took the key") }
                app.frame(atNanos: now)
            }
            tick += 1
        }
        func row(of text: String, in app: HeadlessApp<GlidingApp>) -> Int? {
            app.screen.map(\.stripped).firstIndex { $0.contains(text) }
        }

        frame()
        frame()
        #expect(row(of: "tail", in: warm) == 3, "precondition: collapsed")
        var differing: [Int64] = []
        var tailRows: Set<Int> = []
        for step in 0..<140 {
            frame(pressing: step == 0 || step == 70)
            if warm.screen != cold.screen { differing.append(tick - 1) }
            if let tail = row(of: "tail", in: warm) { tailRows.insert(tail) }
        }
        #expect(
            differing.isEmpty,
            "the cached app drew something else at ticks \(differing):\n\(warm.screen.map(\.stripped))")
        #expect(tailRows.isSuperset(of: [3, 4, 5, 6]), "the tail did not glide through its rows: \(tailRows)")
        #expect(row(of: "tail", in: warm) == 3, "collapsed again")
        #expect(warm.renderCache.rowWork.served > 0, "nothing was ever served, so this proved nothing")
    }
}
