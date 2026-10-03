//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DatePickerStyle.swift
//
//  How a DatePicker draws — SwiftUI's open style protocol and its built-in
//  styles.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Configuration

/// The properties of a date picker.
public struct DatePickerStyleConfiguration {
    /// A type-erased label of a date picker.
    public struct Label: View {
        let content: AnyView

        public var body: some View { content }
    }

    /// A description of the date picker.
    public let label: Label

    /// The date value being displayed and selected.
    @Binding public var selection: Date

    /// The oldest selectable date, or `nil` for none.
    public var minimumDate: Date?

    /// The most recent selectable date, or `nil` for none.
    public var maximumDate: Date?

    /// The date components the user is able to view and edit.
    public var displayedComponents: DatePickerComponents

    /// The bounds as the picker's core takes them.
    var range: ClosedRange<Date>? {
        guard minimumDate != nil || maximumDate != nil else { return nil }
        return (minimumDate ?? .distantPast)...(maximumDate ?? .distantFuture)
    }
}

// MARK: - Protocol

/// A type that specifies the appearance and interaction of all date pickers
/// within a view hierarchy.
public protocol DatePickerStyle: Sendable {
    /// A view representing the appearance and interaction of a date picker.
    associatedtype Body: View

    /// Returns the appearance and interaction content for a date picker.
    ///
    /// - Parameter configuration: The properties of the date picker.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a date picker.
    typealias Configuration = DatePickerStyleConfiguration
}

extension DatePickerStyle {
    /// This style's body, type-erased — opening the existential the
    /// environment holds.
    @MainActor
    func makeAnyBody(configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// A built-in style the date picker draws itself, with its focus id and
/// disabled state, rather than through a body.
protocol BuiltInDatePickerStyle: DatePickerStyle {}

/// The label and the editable field — what every field-shaped built-in draws.
struct _DatePickerField: View {
    let configuration: DatePickerStyleConfiguration
    var focusID: String?
    var isDisabled = false

    var body: some View {
        // `_CollapsingLabel` rather than the label and a stack gap: it is the
        // same "label, one separating space, or nothing at all" unit `Picker`,
        // `Slider` and `Stepper` use, and it is where `.labelsHidden()` is
        // honoured. Spacing 0 because the unit carries its own space.
        HStack(spacing: 0) {
            _CollapsingLabel(label: configuration.label, controlDisabled: isDisabled)
            _DatePickerCore(
                selection: configuration.$selection, range: configuration.range,
                displayedComponents: configuration.displayedComponents, focusID: focusID,
                isDisabled: isDisabled)
        }
    }
}

// MARK: - Built-in styles

/// The default style for date pickers: the editable field.
public struct DefaultDatePickerStyle: BuiltInDatePickerStyle, Equatable {
    /// Creates the default date picker style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _DatePickerField(configuration: configuration)
    }
}

/// A date picker style that displays the components in an editable field.
///
/// Left and Right choose a component, Up and Down step it, and the mouse wheel
/// steps the component under the pointer.
public struct FieldDatePickerStyle: BuiltInDatePickerStyle, Equatable {
    /// Creates a field date picker style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _DatePickerField(configuration: configuration)
    }
}

/// A system style that displays the components in an editable field, with
/// adjoining stepper that can increment and decrement the selected component.
///
/// The field here steps its selected component with Up and Down and the wheel
/// over a component, which is the stepper's job; it draws no arrows beside it
/// (decisions B14).
public struct StepperFieldDatePickerStyle: BuiltInDatePickerStyle, Equatable {
    /// Creates a stepper field date picker style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _DatePickerField(configuration: configuration)
    }
}

/// A date picker style that displays the components in a compact, textual
/// format.
///
/// The field is that format already; it opens no calendar popover (decisions
/// B14).
public struct CompactDatePickerStyle: BuiltInDatePickerStyle, Equatable {
    /// Creates a compact date picker style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _DatePickerField(configuration: configuration)
    }
}

extension DatePickerStyle where Self == DefaultDatePickerStyle {
    /// The default style for date pickers.
    public static var automatic: DefaultDatePickerStyle { DefaultDatePickerStyle() }
}

extension DatePickerStyle where Self == FieldDatePickerStyle {
    /// A date picker style that displays the components in an editable field.
    public static var field: FieldDatePickerStyle { FieldDatePickerStyle() }
}

extension DatePickerStyle where Self == StepperFieldDatePickerStyle {
    /// A date picker style that displays the components in an editable field,
    /// with adjoining stepper.
    public static var stepperField: StepperFieldDatePickerStyle { StepperFieldDatePickerStyle() }
}

extension DatePickerStyle where Self == CompactDatePickerStyle {
    /// A date picker style that displays the components in a compact, textual
    /// format.
    public static var compact: CompactDatePickerStyle { CompactDatePickerStyle() }
}

// MARK: - Environment

private struct DatePickerStyleKey: EnvironmentKey {
    static let defaultValue: any DatePickerStyle = DefaultDatePickerStyle()
}

extension EnvironmentValues {
    /// The style date pickers in this environment draw with.
    var datePickerStyle: any DatePickerStyle {
        get { self[DatePickerStyleKey.self] }
        set { self[DatePickerStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for date pickers within this view.
    ///
    /// - Parameter style: The date picker style.
    /// - Returns: A view whose date pickers use `style`.
    public func datePickerStyle<S: DatePickerStyle>(_ style: S) -> some View {
        environment(\.datePickerStyle, style)
    }
}
