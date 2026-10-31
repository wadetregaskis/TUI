//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageRenderingControls+Colour.swift
//
//  The image demos' control pane: its sampling and colour sections, and the
//  controls the colour section's options carry.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

extension ImageRenderingControls {
    // MARK: - Sampling

    /// Supersampling is not a colour knob — it decides how many pixels each
    /// SAMPLE is averaged from, before anything has been mapped to a glyph or a
    /// colour at all. It sat under "Colour" as a dim caption, which read as one
    /// more of that section's rows rather than as a stage of its own.
    @ViewBuilder var sampling: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("component.imageControls.supersampling")
            // Applies to every non-shape renderer: each sample (cell tone,
            // half-cell pixel, braille dot) becomes an N x N area average.
            RadioButtonGroup(selection: $settings.supersampling, orientation: .horizontal) {
                RadioButtonItem(0, "component.imageControls.auto")
                RadioButtonItem(1, "1\u{D7}")
                RadioButtonItem(2, "2\u{D7}")
                RadioButtonItem(3, "3\u{D7}")
                RadioButtonItem(4, "4\u{D7}")
            }
            .disabled(
                !drawsGlyphs
                    || !ImageDemoHelpers.usesSupersampling(
                        settings.charset, shapeAware: settings.shapeAware))
        }
    }

    // MARK: - Colour

    @ViewBuilder var colour: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("component.imageControls.colour")
            RadioButtonGroup(selection: $settings.colour) {
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.trueColor, "component.imageControls.trueColour")
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.ansi256, "component.imageControls.colours256")
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.ansi16, "component.imageControls.colours16")
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.grayscale, "component.imageControls.greyscale")
                RadioButtonItem(ImageDemoSettings.ColourMode.mono, "component.imageControls.mono") {
                    // Mono's own knob: which two colours it draws in. The
                    // theme's by default; off, literal white on black, stated
                    // through `.foregroundStyle` / `.backgroundStyle`, with the
                    // same glyphs.
                    Toggle(
                        "component.imageControls.monoThemeColours",
                        isOn: $settings.monoThemeColours)
                }
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.themed, "component.imageControls.themed")
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.greys, "component.imageControls.greys"
                ) {
                    counted("component.imageControls.levels", value: $settings.greyLevels, in: 2...256)
                }
                // The three counted palettes, in order of how much they know
                // about the picture: nothing, its histogram, its error. A count
                // each — they are on screen together, so one shared count made
                // two sliders move when you dragged the third.
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.spread, "component.imageControls.spread"
                ) {
                    counted(
                        "component.imageControls.colours", value: $settings.spreadColours,
                        in: 2...256)
                }
                // The two ADAPTIVE ones also carry a target: which colours they
                // may choose from. Spread does not — it is already constrained
                // to the 256-colour repertoire by construction.
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.mostUsed, "component.imageControls.mostUsed"
                ) {
                    counted(
                        "component.imageControls.colours", value: $settings.mostUsedColours,
                        in: 2...256)
                    targeted($settings.mostUsedTarget)
                }
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.leastError, "component.imageControls.leastError"
                ) {
                    counted(
                        "component.imageControls.colours", value: $settings.leastErrorColours,
                        in: 2...256)
                    targeted($settings.leastErrorTarget)
                }
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.customPalette,
                    "component.imageControls.customPalette"
                ) {
                    // A named set rather than a count: the whole point is that
                    // someone chose these colours, so there is nothing to slide.
                    Picker("", selection: $settings.customPaletteIndex) {
                        ForEach(
                            Array(ImageDemoHelpers.customPalettes.enumerated()), id: \.offset
                        ) { index, entry in
                            Text(verbatim: entry.name).tag(index)
                        }
                    }
                    .labelsHidden()
                }
            }
            // Every mode, true colour too: a posterize reduces the picture to
            // N levels a channel before the mode draws it, which is what gives
            // Dithering below something to spread in true colour (the owner,
            // 2026-10-28).
            Toggle("component.imageControls.posterize", isOn: $settings.posterizes)
                .toggleContent {
                    counted("component.imageControls.levels", value: $settings.posterizationLevels, in: 2...16)
                }
            Toggle("component.imageControls.dithering", isOn: $settings.dithering)
        }
    }

    /// Which colours an adaptive palette may choose from.
    ///
    /// Worth a control rather than a constant because the DIFFERENCE is the
    /// point: on a 256-colour terminal, "Automatic" against "True colour" is
    /// depth-aware derivation against the depth-blind one it replaced — asking
    /// for five colours and getting four, and 256 colours collapsing to 51. The
    /// two poorer depths preview what a poorer terminal makes of the picture,
    /// on the terminal you actually have.
    private func targeted(_ target: Binding<ASCIIPalette.AdaptationTarget>) -> some View {
        HStack(spacing: 1) {
            Text("component.imageControls.target").dim()
            Picker("", selection: target) {
                ForEach(ASCIIPalette.AdaptationTarget.allCases, id: \.self) { option in
                    Text(Self.targetName(option)).tag(option)
                }
            }
            .labelsHidden()
        }
    }

    /// The picker's name for each target. The three depths borrow the colour
    /// section's own names for the same things, which is the point — "256
    /// colours" here and "256 colours" up there are the same 240 colours.
    private static func targetName(
        _ target: ASCIIPalette.AdaptationTarget
    ) -> LocalizedStringKey {
        switch target {
        case .automatic: "component.imageControls.targetAuto"
        case .depth(.truecolor): "component.imageControls.trueColour"
        case .depth(.palette256): "component.imageControls.colours256"
        case .depth(.basic16): "component.imageControls.colours16"
        case .depth(.noColor): "component.imageControls.mono"
        }
    }

    /// A "how many" row: a slider and the number it is at.
    ///
    /// Neither indented nor disabled here — it is an option's content, and the
    /// group does both on its behalf.
    private func counted(
        _ key: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 1) {
            Text(key).dim()
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            )
            // The slider's own `%`-of-range read-out would mislead beside the
            // count shown after it — 4 greys of 2...16 is not "14%" of
            // anything the reader is choosing.
            .sliderShowsValue(false)
            // The pane is a fixed width, so "as wide as it can be" is a width:
            // a 14-cell track gave two greys per cell of travel where the row
            // has room for one.
            .frame(maxWidth: .infinity)
            Text(verbatim: "\(value.wrappedValue)")
                .dim()
                // A field as wide as the widest count this range can reach,
                // because the slider beside it takes whatever width is left:
                // an unpadded read-out going 9 → 10 stole a column from the
                // track and walked the right arrow sideways under the cursor
                // that had just clicked it. Left-aligned so the digits stay
                // against the slider and the slack falls on the outside —
                // TUI's own value read-out pads the same way, and for the
                // same reason (see `_SliderCore.valueLabelText`).
                .frame(width: Self.valueFieldWidth(for: range), alignment: .topLeading)
        }
    }

    /// Columns to reserve for any value in `range`.
    ///
    /// The bounds are the only candidates: an integer's width grows with its
    /// magnitude, and a minus sign only ever appears on the low end.
    private static func valueFieldWidth(for range: ClosedRange<Int>) -> Int {
        max("\(range.lowerBound)".count, "\(range.upperBound)".count)
    }
}
