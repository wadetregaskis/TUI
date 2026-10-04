//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _SliderCore+Ticks.swift
//
//  What a slider draws besides its row: the ticks and their labels under the
//  track, the fill from a neutral value, and the disabled ends outside its
//  enabled bounds.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension _SliderCore {
    /// Where `value` sits along the bounds, from 0 to 1.
    func fraction(of value: Double) -> Double {
        let range = bounds.upperBound - bounds.lowerBound
        guard range > 0 else { return 0 }
        return min(1, max(0, (value - bounds.lowerBound) / range))
    }

    /// Where the fill starts, along the bounds, or `nil` for the low end.
    var neutralFraction: Double? { neutralValue.map(fraction(of:)) }

    /// The stretch of the track that may be selected, or `nil` when all of it
    /// may.
    var enabledFractions: ClosedRange<Double>? {
        guard enabledBounds != nil else { return nil }
        let selectable = selectableBounds
        let stretch = fraction(of: selectable.lowerBound)...fraction(of: selectable.upperBound)
        return stretch == 0...1 ? nil : stretch
    }

    /// The track drawn as `inside` within `enabled` and as `outside` beyond it,
    /// cut at whole cells.
    static func splice(_ inside: ClaimingRow, outside: ClaimingRow, enabled: ClosedRange<Double>) -> ClaimingRow {
        let total = inside.cells
        let low = Int((enabled.lowerBound * Double(total)).rounded())
        let high = max(low, Int((enabled.upperBound * Double(total)).rounded()))
        var row = ClaimingRow()
        row.append(contentsOf: outside.slice(0..<low))
        row.append(contentsOf: inside.slice(low..<high))
        row.append(contentsOf: outside.slice(high..<total))
        return row
    }

    /// How many rows the ticks take under the track: one for the marks, and
    /// one for their labels if any has a label.
    var tickRowCount: Int {
        guard !ticks.isEmpty else { return 0 }
        return ticks.contains { $0.label != nil } ? 2 : 1
    }

    /// The column, within the track as drawn, a tick at `value` sits on — the
    /// head's own quantisation, so a tick and the head on its value line up.
    private func tickColumn(_ value: Double, drawnTrackWidth: Int) -> Int {
        Self.trackLeft + Int((fraction(of: value) * Double(max(0, drawnTrackWidth - 1))).rounded())
    }

    /// The rows under the track: a `╵` under each tick, and each label centred
    /// under its mark on the row below, where it fits without touching the one
    /// before it. A label that would collide is left out rather than overlap.
    func tickRows(drawnTrackWidth: Int, isDisabled: Bool, context: RenderContext) -> [String] {
        guard !ticks.isEmpty else { return [] }
        let palette = context.environment.palette
        var ink = palette.foregroundTertiary
        if isDisabled { ink = ink.opacity(ViewConstants.disabledForeground, over: palette.background) }
        let width = context.availableWidth

        var marks = ClaimingRow()
        for column in Set(ticks.map { tickColumn($0.value, drawnTrackWidth: drawnTrackWidth) }).sorted()
        where column >= marks.cells && column < width {
            marks.skip(cells: column - marks.cells)
            marks.append("╵", cells: 1, ink: ink)
        }
        guard tickRowCount == 2 else { return [marks.text] }

        var labels = ""
        var drawn = 0
        for (index, tick) in ticks.enumerated().sorted(by: { $0.element.value < $1.element.value }) {
            guard let label = tick.label else { continue }
            let labelContext = context.withChildIdentity(type: _SliderTickMark.self, index: index)
            let line = TUIkitView.renderToBuffer(label, context: labelContext).lines.first ?? ""
            let labelWidth = line.strippedLength
            let column = tickColumn(tick.value, drawnTrackWidth: drawnTrackWidth)
            let start = min(max(0, column - labelWidth / 2), width - labelWidth)
            guard labelWidth > 0, start >= drawn + (drawn > 0 ? 1 : 0) else { continue }
            labels += String(repeating: " ", count: start - drawn) + line
            drawn = start + labelWidth
        }
        return [marks.text, labels]
    }
}

// MARK: - Thumb visibility

private struct SliderThumbVisibilityKey: EnvironmentKey {
    static let defaultValue = Visibility.automatic
}

extension EnvironmentValues {
    /// Whether sliders draw their thumb — see ``View/sliderThumbVisibility(_:)``.
    var sliderThumbVisibility: Visibility {
        get { self[SliderThumbVisibilityKey.self] }
        set { self[SliderThumbVisibilityKey.self] = newValue }
    }
}

extension View {
    /// Sets the thumb visibility for sliders within this view — mirrors
    /// SwiftUI's `sliderThumbVisibility(_:)`.
    ///
    /// `.hidden` draws the track without its knob: the cell the knob sat on
    /// shows the fill's end, and a value the knob alone showed — the
    /// `.marker` track's — is no longer shown at all, as SwiftUI's hidden
    /// thumb leaves only the fill.
    ///
    /// - Parameter visibility: Whether sliders show their thumb.
    /// - Returns: A view whose sliders draw their thumb accordingly.
    public func sliderThumbVisibility(_ visibility: Visibility) -> some View {
        environment(\.sliderThumbVisibility, visibility)
    }
}
