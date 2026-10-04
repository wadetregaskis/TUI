//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Slider+Ticks.swift
//
//  SwiftUI's slider initialisers with a neutral value, enabled bounds, a
//  current-value label and ticks.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Slider {
    /// Creates a slider to select a value from a given range, which displays
    /// the provided labels — mirrors SwiftUI's
    /// `init(value:in:neutralValue:enabledBounds:label:currentValueLabel:minimumValueLabel:maximumValueLabel:onEditingChanged:)`.
    ///
    /// - Parameters:
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of values. Defaults to `0...1`.
    ///   - neutralValue: Where the fill starts, or `nil` for the low end.
    ///   - enabledBounds: The values that may be selected, or `nil` for all of
    ///     `bounds`. The track beyond them is drawn disabled.
    ///   - label: A view describing the purpose of the slider.
    ///   - currentValueLabel: A view describing `value`, drawn in place of the
    ///     slider's own read-out.
    ///   - minimumValueLabel: A view describing `bounds.lowerBound`.
    ///   - maximumValueLabel: A view describing `bounds.upperBound`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    @_disfavoredOverload
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        neutralValue: V? = nil,
        enabledBounds: ClosedRange<V>? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> some View = { EmptyView() },
        @ViewBuilder minimumValueLabel: () -> ValueLabel = { EmptyView() },
        @ViewBuilder maximumValueLabel: () -> ValueLabel = { EmptyView() },
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, in: bounds, step: 0.01, label: label,
            minimumValueLabel: minimumValueLabel, maximumValueLabel: maximumValueLabel,
            onEditingChanged: onEditingChanged)
        configure(
            neutralValue: neutralValue, enabledBounds: enabledBounds,
            currentValueLabel: currentValueLabel(), ticks: [SliderTick<V>]())
    }

    /// Creates a slider to select a value from a given range, which displays
    /// the provided labels and ticks — mirrors SwiftUI's
    /// `init(value:in:neutralValue:enabledBounds:label:currentValueLabel:minimumValueLabel:maximumValueLabel:ticks:onEditingChanged:)`.
    ///
    /// - Parameters:
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of values. Defaults to `0...1`.
    ///   - neutralValue: Where the fill starts, or `nil` for the low end.
    ///   - enabledBounds: The values that may be selected, or `nil` for all of
    ///     `bounds`.
    ///   - label: A view describing the purpose of the slider.
    ///   - currentValueLabel: A view describing `value`, drawn in place of the
    ///     slider's own read-out.
    ///   - minimumValueLabel: A view describing `bounds.lowerBound`.
    ///   - maximumValueLabel: A view describing `bounds.upperBound`.
    ///   - ticks: The ticks drawn under the track, each a mark with its label
    ///     under it.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    @_disfavoredOverload
    public init<V>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        neutralValue: V? = nil,
        enabledBounds: ClosedRange<V>? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> some View = { EmptyView() },
        @ViewBuilder minimumValueLabel: () -> ValueLabel = { EmptyView() },
        @ViewBuilder maximumValueLabel: () -> ValueLabel = { EmptyView() },
        @SliderTickBuilder<V> ticks: () -> some SliderTickContent<V>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, in: bounds, step: 0.01, label: label,
            minimumValueLabel: minimumValueLabel, maximumValueLabel: maximumValueLabel,
            onEditingChanged: onEditingChanged)
        configure(
            neutralValue: neutralValue, enabledBounds: enabledBounds,
            currentValueLabel: currentValueLabel(), ticks: ticks().body)
    }

    /// Creates a slider to select a value from a given range, subject to a
    /// step increment, which displays the provided labels and a tick for each
    /// step that `tick` gives one — mirrors SwiftUI's
    /// `init(value:in:step:neutralValue:enabledBounds:label:currentValueLabel:minimumValueLabel:maximumValueLabel:tick:onEditingChanged:)`.
    ///
    /// - Parameters:
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of values.
    ///   - step: The distance between each valid value. Defaults to `1`.
    ///   - neutralValue: Where the fill starts, or `nil` for the low end.
    ///   - enabledBounds: The values that may be selected, or `nil` for all of
    ///     `bounds`.
    ///   - label: A view describing the purpose of the slider.
    ///   - currentValueLabel: A view describing `value`, drawn in place of the
    ///     slider's own read-out.
    ///   - minimumValueLabel: A view describing `bounds.lowerBound`.
    ///   - maximumValueLabel: A view describing `bounds.upperBound`.
    ///   - tick: The tick for each step's value, or `nil` for none there.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    @_disfavoredOverload
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        neutralValue: V? = nil,
        enabledBounds: ClosedRange<V>? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> some View = { EmptyView() },
        @ViewBuilder minimumValueLabel: () -> ValueLabel = { EmptyView() },
        @ViewBuilder maximumValueLabel: () -> ValueLabel = { EmptyView() },
        tick: (V) -> SliderTick<V>? = { _ in nil },
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, in: bounds, step: step, label: label,
            minimumValueLabel: minimumValueLabel, maximumValueLabel: maximumValueLabel,
            onEditingChanged: onEditingChanged)
        // One tick per step, as SwiftUI asks `tick` for each; a bound that is
        // not a whole number of steps from the low end gets no step of its own.
        var steps: [SliderTick<V>] = []
        if step > 0 {
            var position = bounds.lowerBound
            while position <= bounds.upperBound, steps.count <= 10_000 {
                if let mark = tick(position) { steps.append(mark) }
                position = position.advanced(by: step)
            }
        }
        configure(
            neutralValue: neutralValue, enabledBounds: enabledBounds,
            currentValueLabel: currentValueLabel(), ticks: steps)
    }

    /// Records the settings the newer initialisers add, in the slider's own
    /// `Double` units.
    private mutating func configure<V: BinaryFloatingPoint>(
        neutralValue: V?, enabledBounds: ClosedRange<V>?, currentValueLabel: some View,
        ticks: some Collection<SliderTick<V>>
    ) {
        // Statements rather than `map` closures, which would capture `V`'s
        // metatype in the main actor's isolation.
        if let neutralValue { self.neutralValue = Double(neutralValue) }
        if let enabledBounds {
            self.enabledBounds = Double(enabledBounds.lowerBound)...Double(enabledBounds.upperBound)
        }
        var marks: [_SliderTickMark] = []
        for tick in ticks { marks.append(_SliderTickMark(tick)) }
        self.ticks = marks
        self.currentValueLabel = currentValueLabel is EmptyView ? nil : AnyView(currentValueLabel)
    }
}
