//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomAnimationRenderTests.swift
//
//  A `CustomAnimation` driving a real change through the app's animator, as
//  a built-in curve does (decisions O3).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp

/// Linear over `duration` seconds — `.linear(duration:)` written as a custom
/// animation, so the two can be held to the same frames.
private struct CustomLinear: CustomAnimation {
    var duration: TimeInterval

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: time / duration)
    }
}

private struct CustomSlidingApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { CustomSlidingPage() }
    }
}

private struct CustomSlidingPage: View {
    @State private var isAcross = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("go") {
                withAnimation(Animation(CustomLinear(duration: 1))) { isAcross.toggle() }
            }
            Text("@").padding(.leading, isAcross ? 10 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
@Suite("CustomAnimation, drawn")
struct CustomAnimationRenderTests {
    @Test("A custom animation moves a view across its frames as the built-in curve it imitates does")
    func drivesAView() {
        let app = HeadlessApp(CustomSlidingApp(), width: 40, height: 10)
        app.frame(atNanos: 0)
        func column() -> Int? {
            for line in app.screen.map(\.stripped) {
                if let range = line.range(of: "@") {
                    return line.distance(from: line.startIndex, to: range.lowerBound)
                }
            }
            return nil
        }
        let start = column()
        #expect(start != nil, "precondition: the marker is drawn")
        guard let start else { return }

        #expect(app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        app.frame(atNanos: 16_666_667)
        #expect(column() == start, "the change did not start from where it was")
        app.frame(atNanos: 516_666_667)
        #expect(column() == start + 5, "not half-way across half-way through")
        app.frame(atNanos: 1_100_000_000)
        #expect(column() == start + 10)
    }
}
