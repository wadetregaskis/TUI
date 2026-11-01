//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarBesideAnimationTests.swift
//
//  The menu bar holds still while the page animates. A `PhaseAnimator`'s each
//  step is a `withAnimation`, and the pass that shows it carries that
//  animation in its transaction — the whole pass, the menu bar's walk
//  included. The bar drew every title at ONE identity, so a stack's glide
//  (`ChildGlide`) kept there was every title's: each title animated from the
//  one drawn before it, and the last title's trailing cell, five columns in,
//  drew a blank over the fifth column of each title for the frames the glide
//  ran (the owner, 2026-10-28, #38: the `E` of "TUI Example" and the `o` of
//  "Window" on the Example's Animation page).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
import TUITesting

/// A dot cycling between three places for as long as it is drawn — each step
/// a `withAnimation` of its own — under a menu bar whose titles each have a
/// letter in their fifth column: "Example" and "Windows" after the last
/// title's `" Help "`, whose trailing cell is there.
private struct CyclingUnderMenuBar: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            PhaseAnimator([0, 8, 16, 8]) { position in
                Text("●").offset(x: position)
            } animation: { _ in
                .easeInOut(duration: 0.4)
            }
            .frame(width: 18, alignment: .leading)
        }
        .commandsRemoved()
        .commands {
            CommandMenu("Example") { Button("One") {} }
            CommandMenu("Windows") { Button("Two") {} }
            CommandMenu("Help") { Button("Three") {} }
        }
    }
}

@MainActor
@Suite("The menu bar beside an animation", .serialized)
struct MenuBarBesideAnimationTests {
    @Test("A page's repeating animation never changes a cell of the menu bar's titles")
    func titlesHoldStill() throws {
        let app = TestApp(CyclingUnderMenuBar(), width: 60, height: 8)
        app.frame(atNanos: 0)
        let first = app.screen.styledLines[0].stripped
        #expect(first.contains(" Example  Windows  Help "), "\(first)")
        // Two seconds of 60 Hz frames: four steps and more of the cycle, each
        // a pass carrying its animation.
        var rows: [String] = [first]
        for step in 1...120 {
            app.frame(atNanos: Int64(step) * 16_666_667)
            let row = app.screen.styledLines[0].stripped
            if row != rows.last { rows.append(row) }
        }
        #expect(rows.count == 1, "the titles changed: \(rows)")
    }
}
