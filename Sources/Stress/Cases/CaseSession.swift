//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseSession.swift
//
//  A perf case played as a `Stress` session, `case:<id>`: its script, looped,
//  against the page `--check-counts` counts. So every tool that plays sessions
//  plays the cases too: `--session case:<id> --verify` against a cache-cleared
//  twin, `--selfcheck`, and `--bench --scenario session/case:<id>`, which
//  `ab_bench.py`, `frame_parity.py` and `ab_counters.py` drive (design,
//  B-PERFCASE-3).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// One perf case's script, played step by step against its page.
///
/// **The script loops.** A session plays as many steps as it is asked (400 by
/// default, a bench's iterations), and a script is a few dozen, so after its
/// last step the script starts again after its `open`. A script of `open`
/// alone is idle frames.
///
/// **What differs from `--check-counts`.** A step is one frame here: the
/// runner draws one per step, where the counting player draws until a frame
/// asks for no other, and `type:ab` is a step per character. `tick:<ms>` is an
/// idle step, since the runner's clock moves a sixtieth a step. The counts a
/// session reports are the runner's and are not compared with the recorded
/// ones: what this adds is the cache-cleared twin (`--verify`) and the timing.
///
/// **Its size is the case's.** `--cols` and `--rows` are ignored
/// (``SessionDescriptor/size``); `--scale` multiplies its `n`.
@MainActor
final class CaseSession: StressSession {
    let page: AnyView
    private let perfCase: PerfCase
    private let rows: CaseRows
    /// The script after its `open`, a step each, `type:` a step per character.
    private let steps: [CaseStep]
    /// The screen's size as the script left it: a wheel turns, and a hover
    /// starts, at its middle. A resize the runner makes (`--resize-every`)
    /// is not seen.
    private var size: (width: Int, height: Int)
    private var pointer: (x: Int, y: Int)?

    init(_ perfCase: PerfCase, config: StressConfig) {
        let count = perfCase.count * max(1, config.scale)
        self.perfCase = perfCase
        rows = CaseRows(
            count: count, seed: CasePlayer.seed, keepsDocument: perfCase.composition.hasEditor,
            keepsTree: perfCase.composition.hasOutline, opensTree: perfCase.composition.opensTree)
        page = perfCase.page(rows: rows, count: count, seed: CasePlayer.seed)
            ?? AnyView(Text(verbatim: "Stress has no scenario \(perfCase.composition)"))
        size = (perfCase.size.width, perfCase.size.height)
        steps = Self.phaseSteps(of: perfCase).flatMap { $0 }
    }

    /// Each phase's steps as the session plays them: `open` none, since the
    /// runner draws the page as it opens before its first step.
    private static func phaseSteps(of perfCase: PerfCase) -> [[CaseStep]] {
        perfCase.phases.map { phase -> [CaseStep] in
            let one: [CaseStep]
            switch phase.step {
            case .open: one = []
            case .type(let text): one = text.map { .type(String($0)) }
            default: one = [phase.step]
            }
            return (0..<phase.repeats).flatMap { _ in one }
        }
    }

    /// How many steps reach the first step of the script's last phase, so
    /// every phase is played: what `--selfcheck` plays of a case, at least
    /// (``SessionDescriptor/stepsToEveryPhase``).
    static func stepsToEveryPhase(of perfCase: PerfCase) -> Int {
        let phases = phaseSteps(of: perfCase).filter { !$0.isEmpty }
        let beforeLast = phases.dropLast().reduce(0) { $0 + $1.count }
        return beforeLast + (phases.isEmpty ? 0 : 1)
    }

    func step(_ index: Int) -> SessionStep {
        guard !steps.isEmpty else { return SessionStep(action: "idle") }
        let step = steps[index % steps.count]
        let action: String
        switch step {
        case .type: action = "type"
        default: action = step.description
        }
        if let to = step.resized(from: size) {
            size = to
            return SessionStep(action: action, resize: size)
        }
        let input = step.input(size: size, pointer: &pointer)
        rows.write(step)
        return SessionStep(action: action, keys: input.keys, mouse: input.mouse)
    }

    /// 24-bit colour, as `--check-counts` draws every frame.
    var colorDepth: ColorDepth? { .truecolor }

    /// The app `--check-counts` plays the case in: no bars, its scene's
    /// setting, its locale and appearance pinned. At the case's size, whatever
    /// the runner asks: the runner is handed that size (``SessionDescriptor/size``).
    func makeApp(width: Int, height: Int) -> HeadlessApp? {
        perfCase.app(page: page)
    }

    // MARK: The registry

    /// The prefix of a case's session id.
    nonisolated static let idPrefix = "case:"

    /// A session for every case in the tables; none if the tables have
    /// mistakes, which `--cases` and `--check-counts` report.
    static var descriptors: [SessionDescriptor] {
        CaseTables.cases.map { perfCase in
            SessionDescriptor(
                id: idPrefix + perfCase.id,
                summary: "perf case \(perfCase.id), its script looped: \(perfCase.composition) "
                    + "in \(perfCase.container.rawValue), n \(perfCase.count), \(perfCase.size)",
                exercises: perfCase.phases.map(\.spelling).joined(separator: ";")
                    + "  [\(perfCase.tags.joined(separator: ","))]",
                make: { config, width, height, cold in
                    DrivenSession(CaseSession(perfCase, config: config), width: width, height: height, cold: cold)
                },
                size: (perfCase.size.width, perfCase.size.height),
                stepsToEveryPhase: stepsToEveryPhase(of: perfCase))
        }
    }
}
