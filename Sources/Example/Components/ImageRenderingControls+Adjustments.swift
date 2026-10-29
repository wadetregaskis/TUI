//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageRenderingControls+Adjustments.swift
//
//  The Images page's tone adjustments: exposure, black point, highlights and
//  contrast (`imageAdjustments(_:)`), the owner's explicit adjustments in place
//  of a hidden black level (2026-10-28, afternoon list #29).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

extension ImageRenderingControls {
    /// The picture's adjustments: before the tone curve, so they come before
    /// it here too, as the renderer applies them.
    var adjustments: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("component.imageControls.adjustments")
            adjustmentRow(
                "component.imageControls.exposure", value: $settings.adjustments.exposure, in: -2...2, step: 0.1,
                format: "%+.1f")
            adjustmentRow(
                "component.imageControls.blackPoint", value: $settings.adjustments.blackPoint, in: 0...0.5,
                step: 0.01, format: "%.2f")
            adjustmentRow(
                "component.imageControls.adjustHighlights", value: $settings.adjustments.highlights, in: -1...1,
                step: 0.05, format: "%+.2f")
            adjustmentRow(
                "component.imageControls.contrast", value: $settings.adjustments.contrast, in: -1...1, step: 0.05,
                format: "%+.2f")
            Button("component.imageControls.adjustmentsReset") { settings.adjustments = .none }
                .disabled(settings.adjustments.isIdentity)
        }
    }

    /// One adjustment: its name, a slider, and the value it is at.
    private func adjustmentRow(
        _ label: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
        format: String
    ) -> some View {
        HStack(spacing: 1) {
            Text(label).frame(width: 16, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .sliderShowsValue(false)
                .frame(maxWidth: .infinity)
            Text(String(format: format, value.wrappedValue)).dim()
        }
    }
}
