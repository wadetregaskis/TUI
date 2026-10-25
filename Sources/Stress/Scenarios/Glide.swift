//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Glide.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Glide

/// A scroll view gliding over static rows, a line every frame: what an
/// animated `scrollTo` costs per frame (decisions B27-ANIMATING; the design
/// note's §5, "a glide frame costs what a one-line wheel step costs").
///
/// No scenario drew that on static content before: `scrollfollow` and
/// `scrolleager` change their content every tick, so a frame there pays for the
/// change as well as the move. Here nothing changes but the offset, so what a
/// frame pays is the move itself — the scroll view and its stack composited
/// again, the scrollbar redrawn, the glide stepped and its next frame asked
/// for — and the rows on screen at two offsets are served from their memos
/// wherever they memoise.
///
/// The bench has no run loop, so the scenario asks it for the loop's 60 Hz
/// frame clock (``DrivenScenario/runsAnimationClock``) and states an animated
/// transaction over its rows; every 32 frames it calls `scrollTo` thirty rows
/// on, through a reader's proxy, as an app's button would. A linear half-second
/// glide of thirty lines moves a line on each of its thirty frames, then lands.
///
/// A matrix of three: `scrollview` (the default, so the sweep runs it), the
/// same in a `List` (a row a frame), and `jump`, the `ScrollView` sent a line
/// on by an unanimated `scrollTo` every frame: the same motion made as jumps,
/// each of which drops the content's memos with its request, where a glide's
/// frames between its requests keep them.
enum GlideMatrix {
    static let scenarioID = "glide"

    @MainActor
    static let descriptor = Scenario(
        id: scenarioID,
        title: "Glide",
        blurb: "A ScrollView or a List gliding a line a frame over static rows, as an animated scrollTo does.",
        stresses: "a glide frame · the one-line step it costs · scroll view and stack composited again · row memos at a moved offset",
        make: { config in
            ScenarioVariants.resolve(config, in: scenarioID)?.make(config)
                ?? AnyView(Text(Lf("stress.scenario.glide.heading", "?", 0)))
        },
        drive: { config in ScenarioVariants.resolve(config, in: scenarioID)?.drive?(config) }
    )

    private static func driven(
        _ id: String, _ summary: String, _ kind: GlidingRows.Kind
    ) -> ScenarioVariant {
        let drive: @MainActor (StressConfig) -> DrivenScenario = { GlidingRows.driven(config: $0, kind: kind) }
        return ScenarioVariant(id: id, summary: summary, axis: "glide", make: { drive($0).view }, drive: drive)
    }

    @MainActor
    static let variants: [ScenarioVariant] = [
        driven("scrollview", "a ScrollView's LazyVStack gliding thirty lines in thirty frames, then on", .scrollView),
        driven("list", "a List gliding thirty rows in thirty frames, then on", .list),
        driven("jump", "the ScrollView sent a line on by an unanimated scrollTo every frame", .jump),
    ]
}

/// Where the scenario keeps the proxy its reader hands it, for the bench's
/// write to call.
@MainActor
private final class GlideProxy {
    var proxy: ScrollViewProxy?
}

/// The rows, under an animated transaction (none for `jump`).
private struct GlidingRows: View {
    enum Kind: String { case scrollView = "scrollview", list, jump }

    let count: Int
    let seed: UInt64
    let kind: Kind
    let box: GlideProxy

    /// Lines a glide travels, and the frames between two requests: a linear
    /// half-second glide of thirty lines moves a line on each of the thirty
    /// 1/60 s frames it lasts and lands on the next.
    private static let stride = 30
    private static let period = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.glide.heading", kind.rawValue, count)).bold()
            Divider()
            ScrollViewReader { proxy in
                let _ = box.proxy = proxy  // swiftlint:disable:this redundant_discardable_let
                content
            }
        }
        // A request made under it glides; the bench publishes no change's
        // transaction, so the scenario states the one its `scrollTo`s are made
        // under.
        .transaction { $0.animation = kind == .jump ? nil : .linear(duration: 0.5) }
    }

    @ViewBuilder
    private var content: some View {
        if kind == .list {
            List {
                ForEach(0..<count, id: \.self) { GlideRow(seed: seed, index: $0) }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { GlideRow(seed: seed, index: $0) }
                }
            }
        }
    }

    /// The rows, and the write that sends them on: thirty rows every 32
    /// frames, or a row every frame for `jump`.
    @MainActor
    static func driven(config: StressConfig, kind: Kind) -> DrivenScenario {
        let count = config.sized(10_000)
        let reach = max(1, count - stride)
        let box = GlideProxy()
        let view = AnyView(Self(count: count, seed: config.seed, kind: kind, box: box))
        var scenario = DrivenScenario(view: view) { tick in
            if kind == .jump {
                box.proxy?.scrollTo(tick % reach, anchor: .top)
            } else if tick.isMultiple(of: period) {
                box.proxy?.scrollTo((tick / period * stride) % reach, anchor: .top)
            }
        }
        scenario.runsAnimationClock = true
        return scenario
    }
}

/// One static log line (`Equatable`, so it value-memoises as an app's row
/// would, and a row on screen at two offsets is served the second time).
private struct GlideRow: View, Equatable {
    let seed: UInt64
    let index: Int

    var body: some View {
        let h = mix(seed, index)
        Text("#\(index) \(Synth.slug(h)) \(Synth.status(h))")
            .foregroundStyle(statusColor(h))
    }
}
