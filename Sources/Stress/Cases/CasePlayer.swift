//  🖥️ TUI — A Terminal UI framework for Swift
//  CasePlayer.swift
//
//  Plays one perf case against an app of its own and counts the work each
//  phase of its script did.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI
import TUICore

/// What one phase of a case did, summed over its steps.
///
/// Counts of work, not of time: the same build playing the same script does
/// the same work on any machine, loaded or not, so they can be compared
/// exactly (design, option 3).
struct CaseCounts: Equatable, Sendable {
    /// The steps the phase took, and the frames those drew.
    var steps = 0
    var frames = 0
    /// Row boxes a list made, drawn or not: `RenderCache.RowWork.listed`.
    var listed = 0
    /// Rows (or memoized subtrees) composed, and served from a memo instead:
    /// `RenderCache.RowWork.rendered` and `.served`.
    var built = 0
    var served = 0
    /// Composite bodies evaluated: `RenderCache.RowWork.bodies`.
    var bodies = 0
    /// Calls into a table column's value closures: `RowWork.cellValues`.
    var cells = 0
    /// Measure-memo misses.
    var misses = 0
    /// Bytes written to the terminal.
    var bytes = 0

    /// The counts by their column names, in the recorded file's order.
    static let names = ["steps", "frames", "listed", "built", "served", "bodies", "cells", "misses", "bytes"]

    var values: [Int] { [steps, frames, listed, built, served, bodies, cells, misses, bytes] }

    init() {}

    init?(values: [Int]) {
        guard values.count == Self.names.count else { return nil }
        (steps, frames, listed, built, served, bodies, cells) =
            (values[0], values[1], values[2], values[3], values[4], values[5], values[6])
        (misses, bytes) = (values[7], values[8])
    }
}

/// One case, played: the counts of each phase, in script order.
struct CasePlay: Sendable {
    /// Each phase's label (``CasePlayer/labels(of:)``) and counts.
    var phases: [(label: String, counts: CaseCounts)]
    /// The last frame, styling stripped, for `--show`.
    var lastScreen: [String] = []
}

/// Plays a case on a `HeadlessApp` of its size.
///
/// **Pinned.** Every frame and every input is drawn at 24-bit colour, under
/// `ColorDepth.withCurrent`, as `TestApp` draws; the locale and the language
/// are pinned for the process by `CountCheck.pinEnvironment()`. Bytes written
/// depend on all three, and `swift test` sets `NO_COLOR` when piped, so
/// without the pins a count would depend on how the gate was run.
///
/// **The clock.** It moves a sixtieth of a second before every frame, as a
/// running app's does, and `tick:<ms>` moves it further: so a frame that asks
/// for another, an animation running, draws the next instant of it rather
/// than the same one again.
@MainActor
final class CasePlayer {
    private let app: HeadlessApp
    private let rows: CaseRows
    private var nanos: Int64 = 0
    /// Where the pointer is, once a hover step has moved it there.
    private var pointer: (x: Int, y: Int)?

    /// The most frames one step draws: one, and more for as long as a frame
    /// asks for another, as `TestApp` draws them. Bounded, so a page that
    /// asks on every frame is counted rather than never let go.
    static let framesPerStep = 8

    /// A sixtieth of a second.
    static let frameNanos: Int64 = 16_666_667

    /// The seed every case's rows are synthesised from.
    static let seed: UInt64 = 0x5715_2025

    /// A player for `perfCase` with `count` rows, or `nil` for an adopted
    /// scenario `Stress` does not have.
    init?(_ perfCase: PerfCase, count: Int) {
        rows = CaseRows(
            count: count, seed: Self.seed, keepsDocument: perfCase.composition.hasEditor,
            keepsTree: perfCase.composition.hasOutline)
        guard let page = perfCase.page(rows: rows, count: count, seed: Self.seed) else { return nil }
        app = perfCase.app(page: page)
    }

    /// Plays every phase of `perfCase` and counts each.
    func play(_ perfCase: PerfCase) -> CasePlay {
        let labels = Self.labels(of: perfCase)
        var played: [(label: String, counts: CaseCounts)] = []
        for (phase, label) in zip(perfCase.phases, labels) {
            let before = reading()
            for _ in 0..<phase.repeats { take(phase.step) }
            var counts = reading().since(before)
            counts.steps = phase.repeats
            played.append((label, counts))
        }
        return CasePlay(phases: played, lastScreen: app.screen.map(\.stripped))
    }

    /// Each phase's label: its step as the table spells it, and `#2`, `#3`, …
    /// after a step a script has taken before, so every label is the case's
    /// own.
    nonisolated static func labels(of perfCase: PerfCase) -> [String] {
        var seen: [String: Int] = [:]
        return perfCase.phases.map { phase in
            let step = phase.step.description
            seen[step, default: 0] += 1
            return seen[step] == 1 ? step : "\(step)#\(seen[step] ?? 0)"
        }
    }

    // MARK: Steps

    private func take(_ step: CaseStep) {
        switch step {
        case .type:
            // A character, then its frames, then the next.
            for key in step.input(size: app.size, pointer: &pointer).keys {
                pinned { _ = app.send(key) }
                drawFrames()
            }
            return
        case .resize(let size):
            app.resize(width: size.width, height: size.height)
        case .tick(let milliseconds):
            nanos += Int64(milliseconds) * 1_000_000
        default:
            // `open` and `idle` send and write nothing: the frames drawn
            // after every step are what they ask for.
            let input = step.input(size: app.size, pointer: &pointer)
            if !input.keys.isEmpty || !input.mouse.isEmpty {
                pinned {
                    for key in input.keys { _ = app.send(key) }
                    for event in input.mouse { _ = app.send(event) }
                }
            }
            rows.write(step)
        }
        drawFrames()
    }

    /// The frames a step causes: one, and more while a frame asks for another.
    private func drawFrames() {
        for _ in 0..<Self.framesPerStep {
            _ = app.takeFrameRequest()
            let asked = app.framesAsked
            nanos += Self.frameNanos
            pinned { app.frame(atNanos: nanos, date: DrivenSession.date(atNanos: nanos)) }
            if !app.takeFrameRequest(), app.framesAsked == asked { break }
        }
    }

    /// `body` at 24-bit colour, as every frame and input of a case is.
    private func pinned(_ body: () -> Void) {
        ColorDepth.withCurrent(.truecolor, operation: body)
    }

    // MARK: Counts

    /// Every count so far, cumulative.
    private func reading() -> CaseCounts {
        var counts = CaseCounts()
        let work = app.renderCache.rowWork
        counts.frames = app.framesDrawn
        counts.listed = work.listed
        counts.built = work.rendered
        counts.served = work.served
        counts.bodies = work.bodies
        counts.cells = work.cellValues
        counts.misses = app.renderCache.measureMemoTotals.misses
        counts.bytes = app.bytesWritten
        return counts
    }
}

extension CaseCounts {
    /// These cumulative counts less `earlier`'s.
    fileprivate func since(_ earlier: Self) -> Self {
        Self(values: zip(values, earlier.values).map { $0 - $1 }) ?? Self()
    }
}

/// The app a case's page is the whole of: no bars, nothing around the page.
///
/// `App` requires `init()`, for `@main`; a host is never launched, only handed
/// to a `HeadlessApp` with its page, as `SessionHost` is.
///
/// Its scene states whether the focus follows the pointer, as the case's
/// `follows(…)` says: a headless app reads no `TUI_FOCUS_FOLLOWS_POINTER`, so
/// the scene is the only place it can be turned on.
struct CaseHost: App {
    let page: AnyView?
    let followsPointer: Bool

    init(page: AnyView, followsPointer: Bool) {
        self.page = page
        self.followsPointer = followsPointer
    }

    init() {
        page = nil
        followsPointer = false
    }

    var body: some Scene {
        WindowGroup {
            if let page { page }
        }
        .focusFollowsPointer(followsPointer)
    }
}
