//  🖥️ TUI — A Terminal UI framework for Swift
//  DismissActionMemoTests.swift
//
//  `DismissAction` is equal to itself by identity (decisions B37), so a view
//  that writes one into its content's environment from a box it keeps does
//  not turn off the memos below it — and a dismissal confirmation, which
//  wraps its content's `\.dismiss`, leaves them on.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

/// How often the memoized view's `body` ran.
@MainActor
private final class BodyCount {
    var bodies = 0
}

/// Equal to every other, so `.equatable()` serves it whenever the memo may.
private struct Counted: View, Equatable {
    let count: BodyCount

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        count.bodies += 1
        return Text("counted")
    }
}

/// Writes a dismiss action for its content: from a box it keeps, or, with
/// `freshEachRender`, a new one every time.
private struct Writer: View {
    let count: BodyCount
    let freshEachRender: Bool
    @State private var box = DismissAction.Box()

    var body: some View {
        let action = freshEachRender ? DismissAction {} : DismissAction(box: box)
        return Counted(count: count).equatable().environment(\.dismiss, action)
    }
}

private struct WriterApp: App {
    let count: BodyCount
    let freshEachRender: Bool

    init() { self.init(count: BodyCount(), freshEachRender: false) }

    init(count: BodyCount, freshEachRender: Bool) {
        self.count = count
        self.freshEachRender = freshEachRender
    }

    var body: some Scene {
        WindowGroup { Writer(count: count, freshEachRender: freshEachRender) }
    }
}

/// The same memoized view under a dismissal confirmation.
private struct ConfirmingApp: App {
    let count: BodyCount

    init() { self.init(count: BodyCount()) }

    init(count: BodyCount) { self.count = count }

    var body: some Scene {
        WindowGroup {
            Counted(count: count).equatable()
                .dismissalConfirmationDialog("Discard changes?", shouldPresent: true) {
                    Button("Discard", role: .destructive) {}
                }
        }
    }
}

@MainActor
@Suite("DismissAction and the memos")
struct DismissActionMemoTests {
    private static let frame: Int64 = 16_666_667

    /// How many more times the memoized view's `body` ran over three frames
    /// after the first, which draws it (a first frame may walk it twice).
    private func laterBodies(of app: some App, count: BodyCount) -> Int {
        let headless = HeadlessApp(app, width: 30, height: 6)
        headless.frame(atNanos: 0)
        let first = count.bodies
        for index in 1...3 { headless.frame(atNanos: Int64(index) * Self.frame) }
        return count.bodies - first
    }

    @Test("An action is equal to itself, and to every other made from its box; two closures are not equal")
    func equality() {
        let box = DismissAction.Box()
        let fromBox = DismissAction(box: box)
        let fromBoxAgain = DismissAction(box: box)
        let topLevel = DismissAction()
        let topLevelAgain = DismissAction()
        let closure = DismissAction {}
        let otherClosure = DismissAction {}
        #expect(fromBox == fromBoxAgain)
        #expect(topLevel == topLevelAgain)
        #expect(closure != otherClosure)
        #expect(fromBox != topLevel)
    }

    @Test("An action written from a kept box leaves the memo below on; a new one each render does not")
    func aKeptBoxKeepsTheMemo() {
        let kept = BodyCount()
        #expect(laterBodies(of: WriterApp(count: kept, freshEachRender: false), count: kept) == 0)
        let fresh = BodyCount()
        #expect(laterBodies(of: WriterApp(count: fresh, freshEachRender: true), count: fresh) > 0)
    }

    @Test("A dismissal confirmation, which wraps its content's dismiss, leaves the memo below on")
    func theConfirmationKeepsTheMemo() {
        let count = BodyCount()
        #expect(laterBodies(of: ConfirmingApp(count: count), count: count) == 0)
    }

    /// The modifier is made on every frame, and a `@State`'s initial value
    /// with it: a box held in a `@State` of its own was allocated each frame
    /// and dropped. It lives in the kept `PendingDismissal` instead.
    @Test("A dismissal confirmation, made afresh every frame, makes no dismiss box of its own")
    func theConfirmationMakesNoBoxPerFrame() {
        let modifier = Text("draft").dismissalConfirmationDialog("Discard?", shouldPresent: true) {
            Button("Discard", role: .destructive) {}
        }
        let held = Mirror(reflecting: modifier).children.map { type(of: $0.value) }
        #expect(!held.contains { $0 == State<DismissAction.Box>.self }, "\(held)")
    }
}
