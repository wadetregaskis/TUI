//  🖥️ TUI — A Terminal UI framework for Swift
//  Gradients.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - Gradients

/// Every gradient path at once, on a page where a ramp is the point rather
/// than a garnish.
///
/// Nothing else in this harness paints one. Every `foregroundStyle` in the
/// other eighteen scenarios takes a `Color`, so `--selfcheck` — which is the
/// gate that runs on Linux and Windows as well as macOS — never rendered a
/// gradient at all, and `ab_bench.py` could only ever answer the "nothing when
/// unused" half of the performance question.
///
/// The five bands are five costs, and they are different costs:
///
/// - **A subtree ramp down a long list.** The expensive one, and the one the
///   design note gates on: every container that places a child hands the child
///   its origin, and a row that MOVES within the ramp has to re-ink even though
///   its own data has not changed — so this is also the case that keeps the
///   render memo honest.
/// - **Per-leaf ramps across a row.** A horizontal ramp at truecolor is one SGR
///   run per CELL, which is the emission half rather than the render half;
///   `ab_bench.py` cannot see it, so `emit_bench.py` is the tool for this band.
/// - **The four geometries, per cell.** `.linear` is affine and collapses to an
///   add and a multiply; `.radial` and `.elliptical` take a square root per
///   cell and `.angular` an `atan2`. Blocks rather than lines, because a
///   geometry's cost is per cell and a one-line block hides three of them.
/// - **Gradient backgrounds under text.** The compositing path, where the
///   overlay's cells are painted over a field the base states — the thing that
///   made `insertOverlay` quadratic once already.
/// - **Mesh gradients.** A grid mesh, placed by two divisions a cell, and a
///   warped one, placed by subdividing its patches — the two ways a mesh
///   reaches a cell, each evaluated as a smooth Hermite blend per cell.
///
/// Deterministic like every other scenario: the ramps are fixed, the row data
/// is `mix(seed, index)`, and the only clock read is the harness's own tick,
/// which drives the ramp's OFFSET so a benchmark cannot measure a page that
/// re-serves last frame's buffers.
enum GradientsScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "gradients",
        title: "Gradients",
        blurb: "A subtree ramp down a long list, per-leaf ramps, four geometries, ramped fills, meshes.",
        stresses:
            "ramp quantisation · per-cell geometry · origin propagation · re-ink on move · SGR runs · mesh patches",
        make: { config in AnyView(GradientsView(config: config)) }
    )
}

private struct GradientsView: View {
    let config: StressConfig

    /// The harness's frame counter, rotating the ramp's stops. A page whose
    /// ramp never moves is served from the memo after the first frame, which
    /// would measure the cache rather than the gradient.
    @Environment(StressClock.self) private var clock

    var body: some View {
        let rows = config.sized(400)
        let ramp = Self.ramp(rotatedBy: clock.tick)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.gradients.heading", rows)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Band 5, first so the screen a self-check renders shows it:
                    // meshes, on the grid and warped off it.
                    ForEach(0..<config.sized(4), id: \.self) { index in
                        MeshBand(ramp: ramp, index: index)
                    }

                    // Band 1: one ramp spanning every row below it.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<rows, id: \.self) { index in
                            GradientRow(seed: config.seed, index: index)
                        }
                    }
                    .foregroundStyle(
                        LinearGradient(gradient: ramp, startPoint: .top, endPoint: .bottom)
                    )
                    .gradientExtent(.subtree)

                    // Band 2: a ramp per leaf, across the row — one SGR run per
                    // cell at truecolor.
                    ForEach(0..<config.sized(60), id: \.self) { index in
                        Text(Synth.slug(mix(config.seed, index &+ 9_001)))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: ramp, startPoint: .leading, endPoint: .trailing))
                    }

                    // Band 3: the geometries whose per-cell answer is not affine.
                    ForEach(0..<config.sized(8), id: \.self) { index in
                        GeometryBand(ramp: ramp, index: index)
                    }

                    // Band 4: ramps as FILLS, under text — the compositing path.
                    ForEach(0..<config.sized(40), id: \.self) { index in
                        Text(Synth.slug(mix(config.seed, index &+ 17_001)))
                            .background(
                                LinearGradient(
                                    gradient: ramp, startPoint: .leading, endPoint: .trailing))
                    }
                }
            }
        }
    }

    /// Six stops, so `quantisedRamp` has 18–24 runs to repair rather than the
    /// 8–11 a two-stop ramp gives it — the case its monotonicity walk actually
    /// costs something on.
    ///
    /// Rotated by the tick so consecutive frames are genuinely different work,
    /// and rotated rather than randomised so a `--selfcheck` at a given frame
    /// is still reproducible.
    private static func ramp(rotatedBy tick: Int) -> Gradient {
        let colours: [Color] = [
            .rgb(220, 60, 90), .rgb(230, 140, 50), .rgb(220, 210, 70),
            .rgb(70, 190, 110), .rgb(60, 140, 210), .rgb(140, 90, 210),
        ]
        let offset = tick % colours.count
        return Gradient(colors: Array(colours[offset...] + colours[..<offset]))
    }
}

/// A row that carries no gradient of its own — its ink comes from where it
/// SITS in the ramp above it, which is the whole point of the first band.
///
/// `Equatable`, like `MegaRow`, so the memo would serve it unchanged if the
/// ramp let it: a row that has moved within the extent must re-ink anyway, and
/// that interaction is the one worth measuring.
private struct GradientRow: View, Equatable {
    let seed: UInt64
    let index: Int

    var body: some View {
        let hashed = mix(seed, index)
        HStack {
            Text("#\(index)")
            Text(Synth.slug(hashed))
            Spacer()
            Text(Synth.status(hashed))
        }
    }
}

/// One block per geometry, painted as the style itself so the ramp resolves
/// over the whole rectangle rather than once per row.
private struct GeometryBand: View {
    let ramp: Gradient
    let index: Int

    var body: some View {
        HStack(spacing: 1) {
            LinearGradient(gradient: ramp, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 18, height: 5)
            RadialGradient(gradient: ramp, center: .center, startRadius: 0, endRadius: 9)
                .frame(width: 18, height: 5)
            EllipticalGradient(gradient: ramp, center: .center)
                .frame(width: 18, height: 5)
            AngularGradient(gradient: ramp, center: .center, angle: .zero)
                .frame(width: 18, height: 5)
        }
    }
}

/// Two meshes in the ramp's colours: a grid, which each cell finds its place
/// in by two divisions, and the same mesh with its middle vertex moved, which
/// each cell finds by subdividing the patches.
private struct MeshBand: View {
    let ramp: Gradient
    let index: Int

    var body: some View {
        let colours = (0..<9).map { ramp.stops[($0 + index) % ramp.stops.count].color }
        let grid: [SIMD2<Float>] = [
            [0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.5, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1],
        ]
        var warped = grid
        warped[4] = [0.7, 0.3]
        return HStack(spacing: 1) {
            MeshGradient(width: 3, height: 3, points: grid, colors: colours)
                .frame(width: 18, height: 5)
            MeshGradient(width: 3, height: 3, points: warped, colors: colours, colorSpace: .perceptual)
                .frame(width: 18, height: 5)
        }
    }
}
