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

    /// Whether this is a `.stepperField` picker, whose stepper
    /// ``View/datePickerShowsStepper(_:)`` can draw.
    var isStepperField = false

    /// What Return and a click on the field also do — a `.compact` picker's
    /// calendar opening — or `nil`.
    var onActivate: (() -> Void)?

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
                isDisabled: isDisabled, isStepperField: isStepperField, onActivate: onActivate)
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
/// The field steps its selected component with Up and Down, and the wheel the
/// component under the pointer, which is the stepper's job. The stepper itself
/// — `▲▼` after the field, each a click target — is drawn only where
/// ``View/datePickerShowsStepper(_:)`` asks for it: it costs three columns.
public struct StepperFieldDatePickerStyle: BuiltInDatePickerStyle, Equatable {
    /// Creates a stepper field date picker style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _DatePickerField(configuration: configuration, isStepperField: true)
    }
}

/// A date picker style that displays the components in a compact, textual
/// format.
///
/// The field, which Return or a click opens the graphical calendar from, in a
/// popover under it — as macOS's compact picker opens its calendar overlay.
/// The calendar picks the day, the field's own keys still edit every
/// component, and Return or Escape closes the calendar again. A picker that
/// shows only the time has no calendar to open.
public struct CompactDatePickerStyle: BuiltInDatePickerStyle, Equatable {
    /// Creates a compact date picker style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _CompactDatePicker(configuration: configuration)
    }
}

/// A `.compact` date picker: the field, and the graphical calendar in a
/// popover that Return or a click on the field opens.
struct _CompactDatePicker: View {
    let configuration: DatePickerStyleConfiguration
    var focusID: String?
    var isDisabled = false

    /// Whether the calendar is open.
    @State private var showsCalendar = false

    var body: some View {
        let showsCalendar = $showsCalendar
        // Only a picker with a date to pick has a calendar to open.
        let opens = configuration.displayedComponents.contains(.date) && !isDisabled
        _DatePickerField(
            configuration: configuration, focusID: focusID, isDisabled: isDisabled,
            onActivate: opens ? { showsCalendar.wrappedValue = true } : nil)
            .popover(isPresented: showsCalendar) {
                // The keys go straight to the calendar as it opens, and its
                // Return closes it on the day it is on.
                _DatePickerCalendarCore(
                    selection: configuration.$selection, range: configuration.range, focusID: nil,
                    isDisabled: isDisabled, onReturn: { showsCalendar.wrappedValue = false },
                    takesFocusOnAppear: true)
            }
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
