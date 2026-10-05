//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Geometry.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Geometry

/// The coordinate-space users of design study A2, together, moving every
/// frame: what decides whether the geometry owners' corrections are a cost an
/// app pays, and which owner pays it.
///
/// Each row of a lazy list carries a `.background(GeometryReader…)` that draws
/// where the row is in the list's named space and in the scroll view's — the
/// scroll-offset idiom, row by row — and watches its scroll visibility. A
/// reader in the header asks `.global` under an offset that moves. The clock
/// drives the script: the list scrolls, a row is inserted above every tenth
/// tick, the header's offset moves, and the frame narrows and widens.
///
/// Under G1 (markers and a correction, no prediction) a reader whose space
/// moved is drawn from last frame's answer and then corrected: scrolling
/// corrects the scroll view's subtree every frame, an insertion the named
/// space's, the offset the root. `--bench geometry` prints the corrections
/// per frame by owner kind — the acceptance metric of the prediction rungs
/// (§10 steps 5–7), which exist to take those to zero.
enum GeometryScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "geometry",
        title: "Geometry",
        blurb: "Lazy rows reading their place in a named space and the scroll view's, while it scrolls.",
        stresses: "geometry markers · coordinate-space owners · correction re-renders · scroll visibility",
        make: { config in AnyView(GeometryView(config: config)) }
    )
}

private struct GeometryView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock
    @State private var shown = 0

    var body: some View {
        let tick = clock.tick
        // Newest first, so an insertion lands above every row already there.
        let count = config.sized(500) + tick / 10
        let newest = count - 1
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.geometry.heading", count, shown)).bold()
            GeometryReader { proxy in
                Text(Lf("stress.scenario.geometry.global", proxy.frame(in: .global).minX))
            }
            .frame(height: 1)
            .offset(x: tick % 3)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        GeometryRow(seed: config.seed, id: newest - index)
                            .background(alignment: .trailing) {
                                GeometryReader { proxy in
                                    let list = proxy.frame(in: .named("list")).minY
                                    let viewport = proxy.frame(in: .scrollView).minY
                                    Text("\(list)/\(viewport)").frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                            .onScrollVisibilityChange { visible in shown += visible ? 1 : -1 }
                    }
                }
                .coordinateSpace(.named("list"))
            }
            .scrollPosition(.constant(ScrollPosition(y: (tick * 3) % max(1, count))))
        }
        .frame(width: 100 - (tick / 5) % 10)
    }
}

/// One synthesised row (`Equatable`, as an app's rows are).
private struct GeometryRow: View, Equatable {
    let seed: UInt64
    let id: Int

    var body: some View {
        let h = mix(seed, id)
        Text("#\(id) \(Synth.slug(h))")
    }
}
