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
/// scroll-offset idiom, row by row — watches its scroll visibility, and fades
/// in and out at the viewport's edges (`scrollTransition`). A
/// reader in the header asks `.global` under an offset that moves. A marker
/// follows the selected row, drawn by a reader in an `overlayPreferenceValue`
/// layer from the row's anchor (probe L1's shape: exact with no correction).
/// The clock drives the script: the list scrolls, a row is inserted above
/// every tenth tick, the selection moves, the header's offset moves, and the
/// frame narrows and widens.
///
/// A reader is told where the containers above it will place it (the carried
/// origin, design study A2 G4), corrected by what its owner found last frame;
/// an owner draws its subtree again only when that prediction missed. Under
/// G1 (no prediction) scrolling corrected the scroll view's subtree and the
/// named space's every frame, an insertion the named space's, the offset the
/// root; with the stacks predicting (rung 1) the named space corrects
/// nothing, with the scroll view placing its content at minus its offset
/// (rung 2) nor does the scroll view, and with `.offset` moving the carried
/// origin (rung 3) nor does the root — past each reader's first frame, the
/// counter should read zero. `--bench geometry` prints the
/// corrections per frame by owner kind, the acceptance metric of the rungs
/// (§10 steps 5–7).
enum GeometryScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "geometry",
        title: "Geometry",
        blurb: "Lazy rows reading their place in a named space and the scroll view's, while it scrolls.",
        stresses: "geometry markers · coordinate-space owners · correction re-renders · scroll visibility · anchors",
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
        let top = (tick * 3) % max(1, count)
        // Always a row the viewport shows, so its anchor is drawn.
        let selected = min(count - 1, top + tick % 4)
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
                            .scrollTransition { content, phase in content.opacity(phase.isIdentity ? 1 : 0.6) }
                            .anchorPreference(key: GeometrySelectionKey.self, value: .bounds) {
                                index == selected ? $0 : nil
                            }
                    }
                }
                .coordinateSpace(.named("list"))
            }
            .scrollPosition(.constant(ScrollPosition(y: top)))
            .overlayPreferenceValue(GeometrySelectionKey.self, alignment: .topLeading) { anchor in
                GeometryReader { proxy in
                    if let anchor {
                        Text(verbatim: "▶").offset(x: 0, y: proxy[anchor].minY)
                    }
                }
            }
        }
        .frame(width: 100 - (tick / 5) % 10)
    }
}

/// The selected row's bounds, for the marker that follows it.
private struct GeometrySelectionKey: PreferenceKey {
    static var defaultValue: Anchor<CellRect>? { nil }
    static func reduce(value: inout Anchor<CellRect>?, nextValue: () -> Anchor<CellRect>?) {
        value = value ?? nextValue()
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
