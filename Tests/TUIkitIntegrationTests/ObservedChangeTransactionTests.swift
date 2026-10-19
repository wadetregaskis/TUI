//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservedChangeTransactionTests.swift
//
//  An `@Observable` change made inside `withAnimation` animates even when an
//  earlier write in the same event — one made outside it — already fired the
//  observation of the body that reads both.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// What a slide reads: how far the mark is, and a count beside it.
@Observable
@MainActor
private final class ObservedSlideModel {
    var presses = 0
    var offset = 0
}

/// A mark the model places, and a key that moves it.
private struct ObservedSlidePage: View {
    let model: ObservedSlideModel
    let animatedFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("slide") {
                // The first write fires the body's observation. Made outside
                // `withAnimation`, it carries no transaction; the second, made
                // inside, then has no observation left to fire.
                if animatedFirst {
                    withAnimation(.linear(duration: 1)) { model.offset += 20 }
                    model.presses += 1
                } else {
                    model.presses += 1
                    withAnimation(.linear(duration: 1)) { model.offset += 20 }
                }
            }
            Text("\(model.presses) MARK").offset(x: model.offset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ObservedSlideApp: App {
    let model: ObservedSlideModel
    let animatedFirst: Bool

    init() { self.init(model: ObservedSlideModel(), animatedFirst: false) }

    init(model: ObservedSlideModel, animatedFirst: Bool) {
        self.model = model
        self.animatedFirst = animatedFirst
    }

    var body: some Scene {
        WindowGroup { ObservedSlidePage(model: model, animatedFirst: animatedFirst) }
    }
}

@MainActor
@Suite("An observed change made inside withAnimation animates, whichever write fired the observation")
struct ObservedChangeTransactionTests {
    /// The column the mark is drawn at.
    private func markColumn(_ app: HeadlessApp<ObservedSlideApp>) -> Int? {
        for line in app.screen.map(\.stripped) {
            if let range = line.range(of: "MARK") {
                return line.distance(from: line.startIndex, to: range.lowerBound)
            }
        }
        return nil
    }

    /// Half-way through a one-second slide, the mark is between where it was
    /// and where it is going — whether the animated write came first, and
    /// fired the observation with its transaction, or second, after an
    /// unanimated write had fired it. SwiftUI animates both orders
    /// (`Tools/SwiftUIProbes/Transactions of observed changes/txn.out`); the
    /// second used to snap, the transaction of a write no observation saw
    /// being recorded nowhere.
    @Test("The slide is under way half-way through", arguments: [false, true])
    func animatedWriteAnimates(animatedFirst: Bool) {
        let app = HeadlessApp(ObservedSlideApp(model: ObservedSlideModel(), animatedFirst: animatedFirst), width: 40, height: 6)
        var tick: Int64 = 0
        func frame() {
            app.frame(atNanos: AnimationClock.nanoseconds(atTick: tick))
            tick += 1
        }
        frame()
        frame()
        let start = markColumn(app)
        #expect(start != nil, "precondition: the mark is drawn")
        guard let start else { return }

        #expect(app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        for _ in 0..<31 { frame() }
        let halfWay = markColumn(app)
        #expect(
            halfWay.map { $0 > start && $0 < start + 20 } == true,
            "the slide is not under way half-way through: the mark is at \(halfWay.map(String.init) ?? "nowhere")")
        for _ in 0..<45 { frame() }
        #expect(markColumn(app) == start + 20, "the slide did not end where it was going")
    }
}
