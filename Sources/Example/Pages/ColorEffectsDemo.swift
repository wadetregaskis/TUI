//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorEffectsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The colour effects: one strip of colour, and what each modifier makes of
/// it — brighter, flatter, greyer, turned round the colour wheel, inverted,
/// multiplied by a colour.
struct ColorEffectsDemo: View {
    private static let strip: [Color] = [.rgb(255, 80, 80), .rgb(255, 210, 80), .rgb(80, 200, 120), .rgb(80, 160, 255)]

    var body: some View {
        DemoSection("page.colors.section.effects") {
            VStack(alignment: .leading, spacing: 0) {
                row(".brightness(0.3)") { $0.brightness(0.3) }
                row(".contrast(0.4)") { $0.contrast(0.4) }
                row(".saturation(0.2)") { $0.saturation(0.2) }
                row(".grayscale(1)") { $0.grayscale(1) }
                row(".hueRotation(.degrees(120))") { $0.hueRotation(.degrees(120)) }
                row(".colorInvert()") { $0.colorInvert() }
                row(".colorMultiply(.rgb(80, 160, 255))") { $0.colorMultiply(.rgb(80, 160, 255)) }
            }
        }
    }

    /// The strip as it is, beside the strip under `effect`, named.
    private func row(_ name: String, _ effect: (AnyView) -> some View) -> some View {
        HStack(spacing: 2) {
            strip
            effect(AnyView(strip))
            Text(verbatim: name).foregroundStyle(.palette.foregroundSecondary)
        }
    }

    /// Twenty cells of the four colours, ramped.
    private var strip: some View {
        LinearGradient(colors: Self.strip, startPoint: .leading, endPoint: .trailing)
            .frame(width: 20, height: 1)
    }
}
