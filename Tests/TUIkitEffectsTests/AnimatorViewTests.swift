//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatorViewTests.swift
//
//  `PhaseAnimator` and `KeyframeAnimator`, and their modifiers (refusal review
//  O2, decisions A37), against what SwiftUI was measured doing
//  (`Tools/SwiftUIProbes/Animation curves, springs and keyframes/p9.out`):
//  a trigger runs through every phase and back to the first, each step
//  animated as the phase it enters says; a trigger-less one cycles, and stops
//  at the first phase after a cycle with nothing animated; keyframes rest at
//  their end and replay from the initial value, part-way from where they were.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// What a page's animator is driven by and what it reported. Observable, so a
/// trigger's change reaches the scene's body, as an app's model would. One per
/// app type, so every app of a type reports into it. (The tests are
/// synchronous from when every headless app shared one `AppState`, and tests
/// that awaited between frames took each other's pending animation
/// completions; each app has its own now — `AppIsolationTests`.)
@Observable
@MainActor
final class AnimatorTestModel {
    var trigger = 0
    var animatedInto: [Int] = []
    var keyframesFrom: [Int] = []
}

private struct PhaseApp: App {
    static let model = AnimatorTestModel()
    init() {}
    var body: some Scene {
        WindowGroup {
            PhaseAnimator([0, 1, 2], trigger: Self.model.trigger) { Text("P\($0)") } animation: { phase in
                Self.model.animatedInto.append(phase)
                return .linear(duration: 0.1)
            }
        }
    }
}

private struct CyclingApp: App {
    static let model = AnimatorTestModel()
    init() {}
    var body: some Scene {
        WindowGroup {
            PhaseAnimator([0, 1, 2]) { Text("P\($0)") } animation: { phase in
                Self.model.animatedInto.append(phase)
                return .linear(duration: 0.1)
            }
        }
    }
}

private struct UnanimatedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { PhaseAnimator([0, 1, 2]) { Text("P\($0)") } animation: { _ in nil } }
    }
}

/// The modifier form: the placeholder draws the view the modifier is on.
private struct PhaseModifierApp: App {
    static let model = AnimatorTestModel()
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("X").phaseAnimator([0, 1, 2], trigger: Self.model.trigger) { content, phase in
                HStack(spacing: 0) {
                    Text("P\(phase)")
                    content
                }
            } animation: { _ in .linear(duration: 0.1) }
        }
    }
}

private struct KeyframeApp: App {
    static let model = AnimatorTestModel()
    init() {}
    var body: some Scene {
        WindowGroup {
            KeyframeAnimator(initialValue: 0.0, trigger: Self.model.trigger) { value in
                Text("V\(Int(value.rounded()))")
            } keyframes: { start in
                // In a result builder, where a bare `_ =` is not a statement.
                // swiftlint:disable:next redundant_discardable_let
                let _ = Self.model.keyframesFrom.append(Int(start.rounded()))
                LinearKeyframe(10.0, duration: 0.3)
            }
        }
    }
}

private struct RepeatingApp: App {
    static var repeating = true
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("X").keyframeAnimator(initialValue: 3.0, repeating: Self.repeating) { content, value in
                HStack(spacing: 0) {
                    Text("V\(Int(value.rounded()))")
                    content
                }
            } keyframes: { _ in
                LinearKeyframe(7.0, duration: 0.1)
                LinearKeyframe(10.0, duration: 0.2)
            }
        }
    }
}

/// A second keyframe app, for the interrupted run: its own model.
private struct InterruptedKeyframeApp: App {
    static let model = AnimatorTestModel()
    init() {}
    var body: some Scene {
        WindowGroup {
            KeyframeAnimator(initialValue: 0.0, trigger: Self.model.trigger) { value in
                Text("V\(Int(value.rounded()))")
            } keyframes: { start in
                // In a result builder, where a bare `_ =` is not a statement.
                // swiftlint:disable:next redundant_discardable_let
                let _ = Self.model.keyframesFrom.append(Int(start.rounded()))
                LinearKeyframe(10.0, duration: 0.3)
            }
        }
    }
}

private struct NotRepeatingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            KeyframeAnimator(initialValue: 3.0, repeating: false) { value in Text("V\(Int(value.rounded()))") } keyframes: { _ in
                LinearKeyframe(7.0, duration: 0.1)
                LinearKeyframe(10.0, duration: 0.2)
            }
        }
    }
}

/// Drives an app a frame at a time on a clock of its own — the monotonic
/// instant and the wall date together.
@MainActor
private final class Driver<A: App> {
    let app: HeadlessApp<A>
    private var nanos: Int64 = 0
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init(_ app: A) {
        self.app = HeadlessApp(app, width: 30, height: 6)
    }

    /// The numbers after `prefix` drawn so far, each change once.
    private(set) var seen: [Int] = []

    func frames(_ count: Int, prefix: Character) {
        for _ in 0..<count {
            nanos += 16_666_667
            app.frame(atNanos: nanos, date: base.addingTimeInterval(Double(nanos) / 1_000_000_000))
            let screen = app.screen.map(\.stripped).joined()
            if let match = screen.firstMatch(of: /[PV](\d+)/),
                screen[match.range].first == prefix, let number = Int(match.1), seen.last != number
            {
                seen.append(number)
            }
        }
    }
}

@MainActor
@Suite("Phase and keyframe animators")
struct AnimatorViewTests {
    @Test("A trigger runs through every phase and back to the first, each step animated as the phase it enters says")
    func triggerRunsThrough() {
        let model = PhaseApp.model
        let driver = Driver(PhaseApp())
        driver.frames(3, prefix: "P")
        #expect(driver.seen == [0] && model.animatedInto.isEmpty, "at rest at the first phase: \(driver.seen)")
        model.trigger += 1
        driver.frames(60, prefix: "P")
        #expect(driver.seen == [0, 1, 2, 0], "\(driver.seen)")
        #expect(model.animatedInto == [1, 2, 0], "\(model.animatedInto)")
        model.trigger += 1
        driver.frames(60, prefix: "P")
        #expect(driver.seen == [0, 1, 2, 0, 1, 2, 0], "and again: \(driver.seen)")
    }

    @Test("With no trigger it cycles from the first phase while it is drawn")
    func cycles() {
        let driver = Driver(CyclingApp())
        driver.frames(60, prefix: "P")
        #expect(Array(driver.seen.prefix(7)) == [0, 1, 2, 0, 1, 2, 0], "\(driver.seen)")
        #expect(Array(CyclingApp.model.animatedInto.prefix(4)) == [1, 2, 0, 1])
    }

    @Test("A cycle with no step animated stops at the first phase, rather than spinning")
    func unanimatedStops() {
        let driver = Driver(UnanimatedApp())
        driver.frames(40, prefix: "P")
        #expect(driver.seen == [0, 1, 2, 0], "\(driver.seen)")
    }

    @Test("The modifier's placeholder draws the view it is on, beside the phase")
    func modifierPlaceholder() {
        let model = PhaseModifierApp.model
        let driver = Driver(PhaseModifierApp())
        driver.frames(2, prefix: "P")
        #expect(driver.app.screen.contains { $0.stripped.contains("P0X") }, "\(driver.app.screen.map(\.stripped))")
        model.trigger += 1
        driver.frames(40, prefix: "P")
        #expect(driver.seen == [0, 1, 2, 0], "\(driver.seen)")
    }

    @Test("Keyframes rest at the initial value, play to the end on a trigger and rest there, and replay from the start")
    func keyframesOnATrigger() {
        let model = KeyframeApp.model
        let driver = Driver(KeyframeApp())
        driver.frames(3, prefix: "V")
        #expect(driver.seen == [0] && model.keyframesFrom.isEmpty, "\(driver.seen)")
        model.trigger += 1
        driver.frames(40, prefix: "V")
        #expect(driver.seen.first == 0 && driver.seen.last == 10, "played to the end: \(driver.seen)")
        #expect(driver.seen == driver.seen.sorted() && driver.seen.count > 4, "rising, frame by frame: \(driver.seen)")
        #expect(model.keyframesFrom == [0])
        let played = driver.seen.count
        model.trigger += 1
        driver.frames(40, prefix: "V")
        let replay = Array(driver.seen.dropFirst(played))
        #expect(replay.first.map { $0 < 5 } == true && replay.last == 10, "from the start again: \(replay)")
        #expect(model.keyframesFrom == [0, 0], "from the initial value, not the end: \(model.keyframesFrom)")
    }

    @Test("A trigger while keyframes play starts them again from the value reached")
    func keyframesInterrupted() {
        let app = InterruptedKeyframeApp.model
        let driver = Driver(InterruptedKeyframeApp())
        driver.frames(2, prefix: "V")
        app.trigger += 1
        driver.frames(8, prefix: "V")
        let reached = driver.seen.last ?? 0
        #expect(reached > 0 && reached < 10, "part-way: \(driver.seen)")
        app.trigger += 1
        driver.frames(40, prefix: "V")
        #expect(app.keyframesFrom.count == 2 && app.keyframesFrom[1] == reached, "\(app.keyframesFrom), reached \(reached)")
        #expect(driver.seen == driver.seen.sorted(), "never back to the start: \(driver.seen)")
    }

    @Test("Repeating keyframes play round and round; not repeating, they draw the start and never play")
    func repeatingOrNot() {
        let driver = Driver(RepeatingApp())
        driver.frames(45, prefix: "V")
        let ends = driver.seen.indices.filter { driver.seen[$0] == 10 }
        #expect(ends.count >= 2, "the end reached more than once: \(driver.seen)")
        #expect(ends.first.map { $0 + 1 < driver.seen.count && driver.seen[$0 + 1] < 10 } == true, "\(driver.seen)")
        #expect(driver.app.screen.contains { $0.stripped.contains("X") }, "the placeholder draws the view")

        let still = Driver(NotRepeatingApp())
        still.frames(30, prefix: "V")
        #expect(still.seen == [3], "\(still.seen)")
    }
}
