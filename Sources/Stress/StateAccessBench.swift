//  🖥️ TUI — A Terminal UI framework for Swift
//  StateAccessBench.swift
//
//  `Stress --state-access`: what one read and one write of a `@State` cost,
//  on the main actor and off it, outside a render and inside a body. The
//  micro-benchmark of O-25-FIRSTREAD's A/B, kept so the two designs it
//  compares, and any after them, are timed by the same code.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// What the bench hands its view, and what the view hands back.
@MainActor
private final class StateAccessProbe {
    /// The view's `@State`, taken in its body.
    var state: State<Int>?
    /// How many times the next body reads the state, timed.
    var readsInBody = 0
    /// How long the last body's reads took.
    var bodyNanos: Int64 = 0
    /// What the reads added up to, printed so no read is optimised away.
    var sum = 0

    /// Reads `read` ``readsInBody`` times, timed.
    func readInBody(_ read: () -> Int) {
        guard readsInBody > 0 else { return }
        let start = ContinuousClock.now
        var total = 0
        for _ in 0..<readsInBody { total &+= read() }
        bodyNanos = (ContinuousClock.now - start).nanoseconds
        sum &+= total
    }
}

/// A view with one `@State`, which its body reads as many times as the probe
/// asks. `pass` changes every render, so every render evaluates the body.
private struct StateAccessView: View {
    let probe: StateAccessProbe
    let pass: Int
    @State private var count = 0

    var body: some View {
        // Statements a view builder takes: the state, handed out, and the reads.
        // swiftlint:disable:next redundant_discardable_let
        let _ = probe.state = _count
        // swiftlint:disable:next redundant_discardable_let
        let _ = probe.readInBody { count }
        Text("\(count) \(pass)")
    }
}

/// The `--state-access` mode.
enum StateAccessBench {
    /// Reads and writes on the main actor: this many each run.
    private static let mainOperations = 2_000_000
    /// Reads off the main actor: this many each run.
    private static let offMainReads = 2_000_000
    /// Writes off the main actor: this many each run. Fewer, as each may post
    /// work to the main actor, which drains it after the run.
    private static let offMainWrites = 200_000
    /// Runs of each measurement; the median is reported.
    private static let runs = 7

    /// Times each access and prints a line for each, in nanoseconds an access.
    @MainActor
    static func run() async -> Int32 {
        let probe = StateAccessProbe()
        var environment = EnvironmentValues()
        let storage = StateStorage()
        environment.stateStorage = storage
        environment.renderCache = RenderCache()
        let context = RenderContext(
            availableWidth: 40, availableHeight: 1, environment: environment,
            identity: ViewIdentity(rootType: StateAccessView.self))
        var pass = 0
        func render() {
            pass += 1
            storage.beginRenderPass()
            _ = storage.inRenderPass { renderToBuffer(StateAccessView(probe: probe, pass: pass), context: context) }
            storage.endRenderPass()
        }
        render()
        guard let state = probe.state else {
            print("state-access: the view handed out no state")
            return 1
        }

        var results: [(String, [Double])] = []

        // On the main actor, outside a render: an action's, a handler's.
        results.append(
            ("main-actor read, outside a render", measure(mainOperations) {
                var total = 0
                for _ in 0..<mainOperations { total &+= state.wrappedValue }
                probe.sum &+= total
            }))

        // In a body, during a render.
        var bodyRuns: [Double] = []
        probe.readsInBody = mainOperations
        for _ in 0..<runs {
            render()
            bodyRuns.append(Double(probe.bodyNanos) / Double(mainOperations))
        }
        probe.readsInBody = 0
        results.append(("read in body, during a render", bodyRuns))

        // On the main actor, outside a render: each write reports to the
        // render cache, as an app's does.
        results.append(
            ("main-actor write", measure(mainOperations) {
                for index in 0..<mainOperations { state.wrappedValue = index }
            }))
        render()

        // Off the main actor. The first read is outside the timing: before
        // O-25-FIRSTREAD it waited for the main actor, once.
        var offReads: [Double] = []
        for _ in 0..<runs {
            let nanos = await Task.detached { () -> (Int64, Int) in
                var total = state.wrappedValue
                let start = ContinuousClock.now
                for _ in 0..<offMainReads { total &+= state.wrappedValue }
                return ((ContinuousClock.now - start).nanoseconds, total)
            }.value
            probe.sum &+= nanos.1
            offReads.append(Double(nanos.0) / Double(offMainReads))
        }
        results.append(("off-main read", offReads))

        // Off the main actor, timed on the writing thread; whatever each write
        // left for the main actor is made after the run, untimed.
        var offWrites: [Double] = []
        for _ in 0..<runs {
            let nanos = await Task.detached { () -> Int64 in
                let start = ContinuousClock.now
                for index in 0..<offMainWrites { state.wrappedValue = index }
                return (ContinuousClock.now - start).nanoseconds
            }.value
            offWrites.append(Double(nanos) / Double(offMainWrites))
            var turns = 0
            while state.wrappedValue != offMainWrites - 1, turns < 1_000_000 {
                await Task.yield()
                turns += 1
            }
        }
        results.append(("off-main write (the writer's time)", offWrites))
        render()

        for (name, samples) in results {
            let sorted = samples.sorted()
            let median = sorted[sorted.count / 2]
            let low = sorted.first ?? 0
            let name = name.padding(toLength: 38, withPad: " ", startingAt: 0)
            print("\(name) median \(Self.nanoseconds(median)) ns  min \(Self.nanoseconds(low)) ns")
        }
        print("checksum \(probe.sum)")
        return 0
    }

    /// `value` to two decimals, right-aligned in seven columns, as `%7.2f`
    /// printed it. Not `String(format:)`: its C variadic arguments are unsafe
    /// under strict memory safety, which 6.4 warns about.
    private static func nanoseconds(_ value: Double) -> String {
        let text = value.formatted(
            .number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
        return String(repeating: " ", count: max(0, 7 - text.count)) + text
    }

    /// Runs `body`, which makes `operations` accesses, ``runs`` times, and
    /// returns the nanoseconds an access each took.
    @MainActor
    private static func measure(_ operations: Int, _ body: () -> Void) -> [Double] {
        (0..<runs).map { _ in
            let start = ContinuousClock.now
            body()
            return Double((ContinuousClock.now - start).nanoseconds) / Double(operations)
        }
    }
}

extension Duration {
    /// The duration in whole nanoseconds.
    fileprivate var nanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}
