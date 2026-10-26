//  🖥️ TUI — A Terminal UI framework for Swift
//  Slider.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

// MARK: - Slider

/// A control for selecting a value from a bounded linear range of values.
///
/// A slider displays a visual track that the user can adjust using keyboard
/// controls. The track shows the current position within the range.
///
/// ## Rendering
///
/// The default track is a rail with a round knob at the value — distinct at a
/// glance from `ProgressView`'s solid block bar and `Gauge`'s shaded meter:
///
/// ```
/// ◀ ━━━━━━━━●──────── ▶ 50%    (the arrows breathe the accent while it holds the focus)
/// ```
///
/// The ``ControlSize`` sets the gap between each arrow and the track, as it
/// sets a bordered button's padding — none at `.small` and `.mini`
/// (`◀━━━━●────▶ 50%`), two cells at `.extraLarge` — and the track takes what
/// the gaps leave of the width the slider is given. The arrows stay at every
/// size: they are its buttons.
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | `→` or `+` | Increment by step |
/// | `←` or `-` | Decrement by step |
/// | `Home` | Jump to minimum |
/// | `End` | Jump to maximum |
///
/// ## Basic Example
///
/// ```swift
/// @State var volume: Double = 0.5
///
/// Slider(value: $volume)
/// ```
///
/// ## With Range and Step
///
/// ```swift
/// @State var brightness: Double = 50
///
/// Slider(value: $brightness, in: 0...100, step: 5)
/// ```
///
/// ## With a Description
///
/// The `label` (or string title) describes the slider's purpose, and is drawn
/// to the left of the track on the same line, shortening the track to fit — as
/// macOS SwiftUI draws it (measured by hosting real `Slider`s in an
/// `NSHostingView`; iOS hides it). With no label the track starts at column 0.
/// `.labelsHidden()` takes the label's cells away.
///
/// ```swift
/// Slider(value: $volume, in: 0...1) {
///     Text("Volume")
/// }
/// // Volume ◀ ━━━━━●──── ▶ 50%
/// ```
///
/// ## With Editing Callback
///
/// ```swift
/// Slider(value: $volume, in: 0...1) { isEditing in
///     print("Editing: \(isEditing)")
/// }
/// ```
public struct Slider<Label: View, ValueLabel: View>: View {
    /// The binding to the current value.
    let value: Binding<Double>

    /// The range of valid values.
    let bounds: ClosedRange<Double>

    /// The step size for increment/decrement.
    let step: Double

    /// The label view describing the slider's purpose, drawn to the left of
    /// the track.
    let label: Label?

    /// The views drawn at the low and high ends of the track — SwiftUI's
    /// `minimumValueLabel` and `maximumValueLabel` — or `nil` for none.
    let minimumValueLabel: ValueLabel?
    let maximumValueLabel: ValueLabel?

    /// The visual style of the track.
    var trackStyle: TrackStyle

    /// The unique focus identifier.
    var focusID: String?

    /// Whether the slider is disabled.
    var isDisabled: Bool

    /// Callback when editing begins or ends.
    let onEditingChanged: ((Bool) -> Void)?

    /// Where the fill starts, or `nil` for the low end — SwiftUI's
    /// `neutralValue:`.
    var neutralValue: Double?

    /// The values that may be selected, or `nil` for all of `bounds` —
    /// SwiftUI's `enabledBounds:`.
    var enabledBounds: ClosedRange<Double>?

    /// The marks drawn under the track.
    var ticks: [_SliderTickMark] = []

    /// The app's description of the value, drawn in place of the slider's own
    /// read-out — SwiftUI's `currentValueLabel:` — or `nil` for the read-out.
    var currentValueLabel: AnyView?

    /// Default track width when no explicit frame is set.
    private static var defaultTrackWidth: Int { 20 }

    public var body: some View {
        // The label renders inline to the left of the track (SwiftUI parity):
        // "Volume ◀ ━━━●─── ▶ 50%". An empty/absent label collapses, so an
        // unlabelled slider still starts at column 0 with a full-length track.
        //
        // Composed as an HStack sibling rather than drawn inside `_SliderCore`
        // on purpose: the core's geometry — `trackLeft`, the arrow click zones,
        // the track-drag mapping — is all measured from its OWN buffer, and the
        // stack shifts its hit regions for us. Prepending the label inside the
        // core would leave `trackLeft` pointing into the label, so clicking the
        // label would auto-repeat a decrement. `controlKind` lets the label
        // resolve `.sliderTextStyle` like the value read-out does.
        //
        // The value labels go either side of the core for the same reason, a
        // cell apart from it. The maximum one follows the read-out rather than
        // sitting between the ▶ and it: the read-out is drawn by the core.
        // Top-aligned, so a slider with ticks — whose core is taller than its
        // row — keeps its labels on the track's row.
        HStack(alignment: .top, spacing: 0) {
            _CollapsingLabel(label: label, controlDisabled: isDisabled)
            // An `EmptyView` value label — what SwiftUI's newer initialisers
            // default to — takes no cell, padding included.
            if let minimumValueLabel, !(minimumValueLabel is EmptyView) {
                minimumValueLabel.padding(.trailing, 1)
            }
            let core = _SliderCore(
                value: value,
                bounds: bounds,
                step: step,
                trackStyle: trackStyle,
                focusID: focusID,
                isDisabled: isDisabled,
                onEditingChanged: onEditingChanged,
                neutralValue: neutralValue,
                enabledBounds: enabledBounds,
                ticks: ticks
            )
            // The app's description of the value stands where the read-out
            // would, and the read-out steps aside for it.
            if let currentValueLabel {
                core.environment(\.sliderShowsValue, false)
                currentValueLabel.padding(.leading, 1)
            } else {
                core
            }
            if let maximumValueLabel, !(maximumValueLabel is EmptyView) {
                maximumValueLabel.padding(.leading, 1)
            }
        }
        .environment(\.controlKind, .slider)
    }
}

// MARK: - Slider Initializers (No Label)

extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    /// Creates a slider to select a value from a given range.
    ///
    /// - Parameters:
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - step: The distance between each valid value. Defaults to `0.01`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        step: V.Stride = 0.01,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = V($0) }
        )
        self.bounds = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = Double(step)
        self.label = nil
        self.minimumValueLabel = nil
        self.maximumValueLabel = nil
        self.trackStyle = .knob
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
    }
}

// MARK: - Slider Initializers (String Title)

extension Slider where Label == Text, ValueLabel == EmptyView {
    /// Creates a slider with a title string.
    ///
    /// The title is drawn to the left of the track, as macOS SwiftUI draws it.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the slider's title.
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - step: The distance between each valid value. Defaults to `0.01`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: BinaryFloatingPoint>(
        _ titleKey: LocalizedStringKey,
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        step: V.Stride = 0.01,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, in: bounds, step: step, label: { Text(titleKey) }, onEditingChanged: onEditingChanged)
    }

    /// Creates a slider with a title displayed as written.
    ///
    /// - Parameters:
    ///   - title: The slider's title.
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - step: The distance between each valid value. Defaults to `0.01`.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    @_disfavoredOverload
    public init<S: StringProtocol, V: BinaryFloatingPoint>(
        _ title: S,
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        step: V.Stride = 0.01,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.init(
            value: value, in: bounds, step: step, label: { Text(String(title)) }, onEditingChanged: onEditingChanged)
    }
}

// MARK: - Slider Initializers (ViewBuilder Label)

extension Slider where ValueLabel == EmptyView {
    /// Creates a slider with a custom label.
    ///
    /// - Parameters:
    ///   - value: The selected value within `bounds`.
    ///   - bounds: The range of valid values. Defaults to `0...1`.
    ///   - step: The distance between each valid value. Defaults to `0.01`.
    ///   - label: A view describing the purpose of the slider.
    ///   - onEditingChanged: A callback for when editing begins and ends.
    public init<V: BinaryFloatingPoint>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        step: V.Stride = 0.01,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V.Stride: BinaryFloatingPoint {
        self.value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = V($0) }
        )
        self.bounds = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = Double(step)
        self.label = label()
        self.minimumValueLabel = nil
        self.maximumValueLabel = nil
        self.trackStyle = .knob
        self.focusID = nil
        self.isDisabled = false
        self.onEditingChanged = onEditingChanged
    }
}

// MARK: - Slider Modifiers

extension Slider {
    /// Sets the visual style of the slider track.
    ///
    /// ```swift
    /// Slider(value: $volume)
    ///     .trackStyle(.dot)
    /// ```
    ///
    /// - Parameter style: The track style.
    /// - Returns: A slider with the specified track style.
    public func trackStyle(_ style: TrackStyle) -> Slider {
        var copy = self
        copy.trackStyle = style
        return copy
    }

    /// Creates a disabled version of this slider.
    ///
    /// - Parameter disabled: Whether the slider is disabled.
    /// - Returns: A new slider with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Slider {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier for this slider.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A slider with the specified focus identifier.
    public func focusID(_ id: String) -> Slider {
        var copy = self
        copy.focusID = id
        return copy
    }
}

extension View {
    /// Styles the *value read-out* text of every slider in this view's subtree
    /// (a `.control(.slider)`-scoped style entry). The track and arrows are
    /// unaffected — their accent is the tint axis.
    ///
    /// ```swift
    /// Mixer().sliderTextStyle { $0.bold = true; $0.foreground = .palette.accent }
    /// ```
    public func sliderTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.slider), build)
    }
}
