//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Picker.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - Picker Entry

/// A picker option whose tag has been resolved to the picker's concrete
/// selection-value type — or a divider between option groups, or the title a
/// `Section`'s header puts over its group.
enum _PickerEntry<SelectionValue: Hashable> {
    /// An option: the value selected when it is chosen, and its label view.
    case option(tag: SelectionValue, label: AnyView)

    /// A rule between option groups. Never selectable.
    case divider

    /// A `Section`'s header, over its options: drawn by a drop-down as a title
    /// that is no option, as a macOS menu picker draws it — an
    /// `NSMenuItem.sectionHeader` after the separator, measured
    /// (`Tools/SwiftUIProbes/Picker sections/pickersection.swift`). Never
    /// selectable, and drawn by no other style.
    case title(AnyView)

    /// The option's tag, or `nil` for a divider.
    var tag: SelectionValue? {
        if case .option(let tag, _) = self { return tag }
        return nil
    }

    /// The option's label, or `nil` for a divider.
    var label: AnyView? {
        if case .option(_, let label) = self { return label }
        return nil
    }
}

// MARK: - Picker

/// A control for selecting one value from a set of mutually exclusive
/// options.
///
/// Each option is a view tagged with the value it represents, using the
/// ``View/tag(_:includeOptional:)`` modifier. The tag type must match the picker's
/// `selection` binding. A `ForEach` row with no tag of its own is tagged with
/// its element's `id`.
///
/// Options are found wherever SwiftUI finds them: inside a view of your own, a
/// `Group`, an `AnyView` or an `if`, and with modifiers written after the tag.
/// Each `Section` is a group of options, set apart from the rest by a rule in
/// a drop-down, as a ``Divider`` among them is.
///
/// ```swift
/// @State private var theme: Theme = .light
///
/// Picker("Theme", selection: $theme) {
///     Text("Light").tag(Theme.light)
///     Text("Dark").tag(Theme.dark)
///     Text("System").tag(Theme.system)
/// }
/// ```
///
/// ## Styles
///
/// The presentation is controlled by ``View/pickerStyle(_:)``:
///
/// - ``MenuPickerStyle`` (and the default ``DefaultPickerStyle``) collapse
///   the picker to a pop-up button — the current value and a `▾` on a bordered
///   button's face, `( Apple ▾ )`, which follows the ``Appearance``, the
///   ``ControlSize`` and the ``ButtonBorderShape`` as a button's does — that
///   opens a drop-down list of options.
/// - ``InlinePickerStyle`` and ``RadioGroupPickerStyle`` present the options
///   inline as a radio-button group.
/// - ``SegmentedPickerStyle`` and ``PalettePickerStyle`` draw the options as
///   the segments of one control, `▐ S │ M │ L ▌`, which follows the
///   ``ControlSize`` as a button's face does on one row: `▐S│M│L▌` at
///   `.small`, `S│M│L` at `.mini`.
///
/// ## Keyboard
///
/// The picker is focusable with Tab. For a menu picker, Enter or Space opens
/// the drop-down (the arrow keys move focus between controls, matching
/// SwiftUI, rather than opening it); once open, the arrow keys move the
/// highlight, typing an option's first characters moves it to that option
/// (type select, as in a `List`), Enter or Space commits the highlighted
/// option, and Escape closes without changing the selection. For an inline picker, the arrow keys move
/// between options and Enter or Space selects. A segmented or palette picker is
/// one stop too: Left and Right move a cursor among the segments, wrapping at
/// the ends, and Enter or Space chooses the segment under it.
public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View {
    /// A binding to the selected value.
    let selection: Binding<SelectionValue>

    /// The picker's option content.
    let content: Content

    /// The picker's label, shown as a heading above the options.
    let label: Label

    /// The unique focus identifier, or `nil` to auto-generate one.
    var focusID: String?

    /// Whether the picker is disabled.
    var isDisabled: Bool

    /// What a menu-style picker shows as its current value, in place of the
    /// selected option's label — SwiftUI's `currentValueLabel:`. Other styles
    /// show every option, the current one marked, and have no use for it.
    var currentValueLabel: AnyView?

    /// `Picker(sources:)` over values that disagree: no option is marked.
    var isMixed = false

    /// `Picker(sources:)` over an empty collection: there is no selection to
    /// read at all, so the body draws the label and an empty, disabled control
    /// and builds nothing that would ask for one.
    var hasNoSources = false

    /// The active picker style, resolved from the environment.
    @Environment(\.pickerStyle) private var pickerStyle

    /// Whether a radio-group picker lays out in a row — see
    /// ``View/horizontalRadioGroupLayout()``.
    @Environment(\.horizontalRadioGroupLayout) private var horizontalLayout

    /// Creates a picker with a custom label.
    ///
    /// - Parameters:
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    ///   - label: A view builder for the picker's label.
    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.selection = selection
        self.content = content()
        self.label = label()
        self.focusID = nil
        self.isDisabled = false
        self.currentValueLabel = nil
    }

    public var body: some View {
        // The options are read where the picker is drawn, from its content's
        // members (`_PickerOptionsReader`): a body has no context to resolve
        // them in. The environment's style and layout are read here, in the
        // body, and handed to the build.
        let style = pickerStyle
        let horizontal = horizontalLayout
        // Tag the picker subtree so its label/option Text resolves
        // `.control(.picker)` style entries (`.pickerTextStyle { … }`).
        _PickerOptionsReader<SelectionValue, Content, _>(content: content) { entries, inPopUpMenu in
            pickerBody(entries: entries, style: style, horizontal: horizontal, inPopUpMenu: inPopUpMenu)
        }
        .environment(\.controlKind, .picker)
    }

    /// The label sits to the LEFT of the control, on the same line, and an
    /// empty label reserves nothing at all — SwiftUI parity, measured on macOS
    /// by hosting real `Picker`s in an `NSHostingView` and capturing the drawn
    /// AppKit controls:
    ///
    /// ```
    /// Picker("Theme", …)                    ->  "Theme  [ Dark ⌄ ]"
    /// Picker("", …)                         ->  "[ Dark ⌄ ]"
    /// Picker("Theme", …).pickerStyle(.radioGroup)
    ///                                       ->  "Theme  ( ) Light"
    ///                                          "       (•) Dark"
    /// ```
    ///
    /// Note the radio group: the label is TOP-aligned against the first option,
    /// not centred on the group — hence `alignment: .top`, which is also what a
    /// one-line menu picker needs.
    ///
    /// `_CollapsingLabel` is the same inline label Stepper and Slider use; it
    /// supplies the separating space and collapses when blank, which is why
    /// this is an `HStack(spacing: 0)`.
    ///
    /// Written in a pop-up menu (`inPopUpMenu`), a picker is no control but
    /// its options as the menu's rows, as SwiftUI's is (measured on macOS 15.8,
    /// `Tools/SwiftUIProbes/Menu items and alert buttons/pickers.out`): a
    /// submenu titled by its label, the selected option checked — or, as an
    /// `.inline` picker, its label as the title of a section of its options in
    /// the menu itself. A radio-group picker draws inline too; macOS has no
    /// menu form for one, and draws its label and options as disabled items.
    @ViewBuilder private func pickerBody(
        entries: [_PickerEntry<SelectionValue>], style: any PickerStyle, horizontal: Bool, inPopUpMenu: Bool
    ) -> some View {
        if inPopUpMenu {
            let rows = _PickerMenuRows(
                entries: hasNoSources ? [] : entries, selection: selection, isMixed: isMixed,
                isDisabled: isDisabled || hasNoSources)
            if Self.isMenuSection(style) {
                _PickerInlineMenuSection(label: label, rows: rows)
            } else {
                _MenuSubmenuRow(label: label, items: rows)
            }
        } else if hasNoSources {
            HStack(alignment: .top, spacing: 0) {
                _CollapsingLabel(label: label, controlDisabled: true)
                Text(verbatim: "—").foregroundStyle(.palette.foregroundTertiary)
            }
        } else if style.resolvesToSegments {
            HStack(alignment: .top, spacing: 0) {
                _CollapsingLabel(label: label, controlDisabled: isDisabled)
                _PickerSegmentsCore(
                    entries: entries, selection: selection, isPalette: style is PalettePickerStyle,
                    focusID: focusID, isDisabled: isDisabled, isMixed: isMixed)
            }
        } else if style.resolvesToMenu {
            HStack(alignment: .top, spacing: 0) {
                _CollapsingLabel(label: label, controlDisabled: isDisabled)
                _PickerMenuCore(
                    entries: entries,
                    selection: selection,
                    focusID: focusID,
                    isDisabled: isDisabled,
                    currentValueLabel: currentValueLabel,
                    isMixed: isMixed
                )
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                _CollapsingLabel(label: label, controlDisabled: isDisabled)
                radioGroup(entries: entries, horizontal: horizontal)
            }
        }
    }

    /// Whether a picker of `style` in a pop-up menu is its options inline, as
    /// a section of the menu — an `.inline` or a radio-group one — rather
    /// than a submenu. The one rule the drawing and the menu's separators
    /// (``drawsAsMenuSection(in:)``) both go by.
    static func isMenuSection(_ style: any PickerStyle) -> Bool {
        !(style.resolvesToMenu || style.resolvesToSegments)
    }

    /// Builds the radio-button group used for the inline / radio-group
    /// styles, reusing ``RadioButtonGroup`` rather than duplicating its
    /// focus and keyboard machinery. Dividers only make sense in a drop-down
    /// list, so they are skipped here.
    private func radioGroup(
        entries: [_PickerEntry<SelectionValue>], horizontal: Bool
    ) -> RadioButtonGroup<SelectionValue> {
        let items = entries.compactMap { entry -> RadioButtonItem<SelectionValue>? in
            guard case .option(let tag, let label) = entry else { return nil }
            return RadioButtonItem(tag) { label }
        }
        let group = RadioButtonGroup(
            selection: selection, orientation: horizontal ? .horizontal : .vertical, items: items)
        var identified = focusID.map { group.focusID($0) } ?? group
        identified.isMixed = isMixed
        return identified.disabled(isDisabled)
    }
}

// MARK: - In a Menu

/// An `.inline` (or radio-group) picker in a pop-up menu is a section of the
/// menu, which places its separators as it places a `Section`'s
/// (``MenuSectionDrawing``): asked in the context the picker is drawn in, so
/// the style and the menu it reads are the ones its body will.
extension Picker: MenuSectionDrawing {
    package func drawsAsMenuSection(in context: RenderContext) -> Bool {
        context.environment.isInPopUpMenu && Self.isMenuSection(context.environment.pickerStyle)
    }
}

// MARK: - Convenience Initializer

extension Picker where Label == Text {
    /// Creates a picker with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the picker's label.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content, label: { Text(titleKey) })
    }

    /// Creates a picker with a text label, displayed as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    ///
    /// - Parameters:
    ///   - title: The picker's label text.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:includeOptional:)``.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content, label: { Text(title) })
    }
}

// MARK: - Picker Convenience Modifiers

extension Picker {
    /// Creates a disabled version of this picker.
    ///
    /// - Parameter disabled: Whether the picker is disabled.
    /// - Returns: A new picker with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Picker {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier for this picker.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A picker with the specified focus identifier.
    public func focusID(_ id: String) -> Picker {
        var copy = self
        copy.focusID = id
        return copy
    }
}

extension View {
    /// Styles the *label and option* text of every picker in this view's subtree
    /// (a `.control(.picker)`-scoped style entry).
    ///
    /// ```swift
    /// SettingsForm().pickerTextStyle { $0.foreground = .palette.accent }
    /// ```
    public func pickerTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.picker), build)
    }
}

// MARK: - Environment without reflection

extension Picker: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _pickerStyle.resolveEnvironment(environment)
        _horizontalLayout.resolveEnvironment(environment)
    }
}
