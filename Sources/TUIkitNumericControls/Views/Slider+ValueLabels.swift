//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Slider+ValueLabels.swift
//
//  SwiftUI's slider initialisers that take a view for each end of the range,
//  drawn either side of the slider.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension Slider {
    /// Creates a slider to select a value from a given range, which displays
    /// the provided labels.
    ///
    /// The minimum value label is drawn before the track and the maximum one
    /// after it — after the value read-out, which TUIkit draws beside the
    /// track and SwiftUI does not.
    ///
    /// - Parameters:
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - label: A view describing the purpose of the slider.
    ///   - minimumValueLabel: A view describing `bounds.lowerBound`.
    ///   - maximumValueLabel: A view describing `bounds.upperBound`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, in: bounds, step: 0.01, label: label,
            minimumValueLabel: minimumValueLabel, maximumValueLabel: maximumValueLabel,
            onEditingChanged: onEditingChanged)
    }

    /// Creates a slider to select a value from a given range, subject to a
    /// step increment, which displays the provided labels.
    ///
    /// - Parameters:
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values.
    ///   - step: The distance between each valid value. Defaults to `1`.
    ///   - label: A view describing the purpose of the slider.
    ///   - minimumValueLabel: A view describing `bounds.lowerBound`.
    ///   - maximumValueLabel: A view describing `bounds.upperBound`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = V($0) }
        )
        self.bounds = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = Double(step)
        self.label = label()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        self.trackStyle = .knob
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
    }
}
