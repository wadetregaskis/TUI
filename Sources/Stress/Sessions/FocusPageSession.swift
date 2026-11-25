//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusPageSession.swift
//
//  The `controls` pages that register focus at scale, played as sessions: a
//  scenario is benched without a focus manager (`Headless.makeContext`), so
//  `--bench --scenario controls` never files a control in a focus section and
//  cannot see what registering costs. A session runs in a `HeadlessApp`, focus
//  and all, so `--bench --scenario session/focus-buttons-200` can.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Which page a ``FocusPageSession`` plays.
enum FocusPage: String, CaseIterable {
    /// 200 buttons drawn in one focus section, served from the memo.
    case buttons200 = "buttons-200"
    /// The 200 buttons drawn again every step.
    case buttons200Live = "buttons-200-live"
    /// 40 fields bound by `.focused(_:equals:)` in nested scroll views.
    case fields = "fields"

    var summary: String {
        switch self {
        case .buttons200: "200 buttons in one focus section, the page's clock moving every step"
        case .buttons200Live: "200 buttons in one focus section, every one redrawn every step"
        case .fields: "40 fields bound by .focused(_:equals:) in a scroll view in a scroll view, one focused"
        }
    }
}

/// The page, with the clock the scenario's views read.
struct FocusPageHost: View {
    let kind: FocusPage
    let clock: StressClock

    var body: some View {
        Group {
            switch kind {
            case .buttons200: ButtonGrid(config: StressConfig(), count: 200)
            case .buttons200Live: ButtonGrid(config: StressConfig(), count: 200, live: true)
            case .fields: FocusedFields(config: StressConfig())
            }
        }
        .environment(clock)
    }
}

/// A clock moving every step under one of the `controls` pages that register
/// focus at scale; nothing else happens.
@MainActor
final class FocusPageSession: StressSession {
    private let kind: FocusPage
    private let clock = StressClock()

    init(_ kind: FocusPage) { self.kind = kind }

    var page: FocusPageHost { FocusPageHost(kind: kind, clock: clock) }

    func step(_ index: Int) -> SessionStep {
        clock.tick += 1
        return SessionStep(action: "tick")
    }

    static func descriptor(_ kind: FocusPage) -> SessionDescriptor {
        SessionDescriptor(
            id: "focus-\(kind.rawValue)",
            summary: kind.summary,
            exercises:
                "focus registration of every control drawn, every frame, served frames included: the "
                + "section's check for a duplicate id, and `.focused(_:equals:)`'s offered id",
            make: { _, width, height, cold in
                DrivenSession(FocusPageSession(kind), width: width, height: height, cold: cold)
            },
            size: (160, 50))
    }
}
