//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModifierChains.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Modifier Chains

/// Many rows, each buried under a long chain of modifiers
/// (`padding`→`border`→`foregroundStyle`→`frame`→`padding`→`border`…). Every
/// modifier is another wrapper node the render pipeline threads context and
/// buffers through, so this stresses the `ModifiedView` / environment-modifier
/// layering and per-node measure overhead independent of data size.
///
/// A matrix of two chains. `chains`, the first and so the default, is the
/// layout chain above, unchanged from before the scenario had variants: a
/// bench of `modifiers` with no `--variant` measures what it always did.
/// `color-effects` is the colour-effect chain — brightness, contrast,
/// saturation, hue rotation, grayscale, invert, multiply — over coloured rows,
/// each effect rewriting every SGR colour code of every line it covers. No
/// other scenario applies a colour effect, so without it a benchmark could not
/// see what that rewrite costs, nor what the module split's crossing into it
/// costs (the colour effects leave the base module, and each effect hands the
/// rewrite a closure per line).
enum ModifierChainsScenario {
    static let scenarioID = "modifiers"

    @MainActor
    static let descriptor = Scenario(
        id: scenarioID,
        title: "Modifier Chains",
        blurb: "N rows, each wrapped in a long modifier chain.",
        stresses: "ModifiedView/environment-modifier layering · per-node measure overhead",
        make: { config in
            ScenarioVariants.resolve(config, in: scenarioID)?.make(config)
                ?? AnyView(ModifierChainsView(config: config))
        }
    )

    @MainActor
    static let variants: [ScenarioVariant] = [
        ScenarioVariant(
            id: "chains", summary: "padding, border, foregroundStyle and frame, twice over, on every row",
            axis: "chain", make: { AnyView(ModifierChainsView(config: $0)) }),
        ScenarioVariant(
            id: "color-effects",
            summary: "all seven colour effects on every coloured row, their amounts moving with the tick",
            axis: "chain", make: { AnyView(ColorEffectChainsView(config: $0)) }),
    ]
}

private struct ModifierChainsView: View {
    let config: StressConfig

    var body: some View {
        let count = config.sized(400)
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.modifiers.heading", count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        let h = mix(config.seed, index)
                        Text(Synth.slug(h))
                            .foregroundStyle(.accentColor)
                            .padding(1)
                            .border()
                            .frame(maxWidth: .infinity, alignment: index.isMultiple(of: 2) ? .leading : .trailing)
                            .padding(1)
                            .border()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Rows of coloured text on a coloured ground, each under every colour effect
/// TUIkit has. The effects' amounts fold in the harness's tick, so no memo
/// serves a row: every frame pays every effect's rewrite of every line.
private struct ColorEffectChainsView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(400)
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.modifiers.heading", count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        let h = mix(config.seed, index)
                        let phase = Double((index &+ tick) % 20) / 20
                        Text(Synth.slug(h))
                            .foregroundStyle(Color.rgb(UInt8(truncatingIfNeeded: h), 160, 90))
                            .background(Color.rgb(30, UInt8(truncatingIfNeeded: h >> 8), 120))
                            .brightness(phase * 0.4 - 0.2)
                            .contrast(0.6 + phase)
                            .saturation(1.5 - phase)
                            .hueRotation(.degrees(Double((index &* 7 &+ tick) % 360)))
                            .grayscale(phase / 2)
                            .colorMultiply(index.isMultiple(of: 3) ? .rgb(255, 220, 180) : .white)
                            .modifier(InvertOnOddRows(invert: !index.isMultiple(of: 2)))
                    }
                }
            }
        }
    }
}

/// `.colorInvert()` on every other row, so the invert pass both runs and is
/// absent across the page.
private struct InvertOnOddRows: ViewModifier {
    let invert: Bool

    func body(content: Content) -> some View {
        if invert {
            content.colorInvert()
        } else {
            content
        }
    }
}
