//  🖥️ TUI — A Terminal UI framework for Swift
//  RadioButton.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

// MARK: - Radio Button Orientation

/// Defines the layout direction of a radio button group.
public enum RadioButtonOrientation: Sendable {
    /// Items stacked vertically (default).
    case vertical

    /// Items arranged horizontally.
    case horizontal
}

// MARK: - Radio Button Item

/// A single option in a radio button group: a value, a label, and — optionally
/// — the controls that configure *that* option.
///
/// ```swift
/// RadioButtonGroup(selection: $colour) {
///     RadioButtonItem(.trueColor, "True colour")
///     RadioButtonItem(.greys, "Greys") {
///         Slider(value: $levels, in: 2...16, step: 1) { Text("Levels: \(levels)") }
///     }
/// }
/// ```
///
/// ```
///   ◯ True colour
///   ● Greys
///     Levels: 4  ├──●─────────┤
/// ```
///
/// ## What the content is for
///
/// An option that takes a parameter — how many greys, which two colours, how
/// wide — has nowhere sensible to put it but under the option it belongs to.
/// Putting it beside the group instead leaves the reader to work out which
/// option it configures, and putting each parameterised option in a group of
/// its own (the other way to draw this) costs the arrow keys that walk the
/// options.
///
/// The content is indented to start under the label, so it reads as part of the
/// option rather than as the next one.
///
/// ## Only the selected option's content is live
///
/// A group disables every unselected option's content, exactly as it would be
/// disabled by ``View/disabled(_:)`` — greyed, and not a focus stop. That is
/// what makes the keyboard convention unambiguous: whatever is reachable below
/// the group belongs to the option that is actually chosen. See
/// ``RadioButtonGroup`` for the keys.
public struct RadioButtonItem<Value: Hashable> {
    /// The value associated with this option.
    let value: Value

    /// The label view builder.
    let labelBuilder: @MainActor () -> AnyView

    /// Builds the option's own controls, shown under it — `nil` for an option
    /// that takes no parameters. Called only while the group renders, like any
    /// other view builder.
    let contentBuilder: (@MainActor () -> AnyView)?

    /// Whether this option alone cannot be chosen (``disabled(_:)``).
    private(set) var isDisabled = false

    /// This option, drawn greyed and not to be chosen, where the rest of its
    /// group can be — as a SwiftUI picker's option is by `.disabled(_:)` on
    /// its view. The arrows pass over it, and a click or Return on it chooses
    /// nothing; it stays chosen if it already was.
    ///
    /// - Parameter disabled: Whether the option is disabled.
    /// - Returns: The option, disabled or not.
    public func disabled(_ disabled: Bool = true) -> Self {
        var copy = self
        copy.isDisabled = isDisabled || disabled
        return copy
    }

    /// Creates a radio button item with a view label.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - label: A view builder closure that returns the label.
    @MainActor
    public init<Label: View>(
        _ value: Value,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.value = value
        self.labelBuilder = { AnyView(label()) }
        self.contentBuilder = nil
    }

    /// Creates a radio button item with a view label and controls of its own.
    ///
    /// Parameter order follows `DisclosureGroup(content:label:)`, which this is
    /// the option-list shape of.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - content: The controls that configure this option, shown under it.
    ///   - label: A view builder closure that returns the label.
    @MainActor
    public init<Content: View, Label: View>(
        _ value: Value,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.value = value
        self.labelBuilder = { AnyView(label()) }
        self.contentBuilder = { AnyView(content()) }
    }

    /// Creates a radio button item with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - labelKey: The key for the label text.
    @MainActor
    public init(
        _ value: Value,
        _ labelKey: LocalizedStringKey
    ) {
        self.init(value, labelKey.localized)
    }

    /// Creates a radio button item with a localized label and controls of its
    /// own, shown under it.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - labelKey: The key for the label text.
    ///   - content: The controls that configure this option.
    @MainActor
    public init<Content: View>(
        _ value: Value,
        _ labelKey: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(value, labelKey.localized, content: content)
    }

    /// Creates a radio button item with a string label, displayed as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``. Only the label is a key: `value` is what the
    /// option stands for, not text anyone reads.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - label: The label text.
    @MainActor
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ value: Value,
        _ label: S
    ) {
        self.value = value
        // Flattened to a `String` here rather than inside the closure. The
        // builder escapes — it is called later, while the group renders — so
        // what it captures is stored, and storing a `String` is what this held
        // before and what `Text` is built from anyway. Nothing generic outlives
        // the call.
        let text = String(label)
        self.labelBuilder = { AnyView(Text(text)) }
        self.contentBuilder = nil
    }

    /// Creates a radio button item with a string label, displayed as written,
    /// and controls of its own shown under it.
    ///
    /// Generic over `StringProtocol` for the same reason as the label-only
    /// overload above — see ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - value: The value for this option.
    ///   - label: The label text.
    ///   - content: The controls that configure this option.
    @MainActor
    @_disfavoredOverload
    public init<Content: View, S: StringProtocol>(
        _ value: Value,
        _ label: S,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.value = value
        let text = String(label)  // see the label-only overload above
        self.labelBuilder = { AnyView(Text(text)) }
        self.contentBuilder = { AnyView(content()) }
    }
}

// MARK: - Radio Button Group Builder

/// A result builder that constructs arrays of radio button items for use in ``RadioButtonGroup``.
///
/// `RadioButtonGroupBuilder` enables the declarative syntax for defining multiple
/// options within a ``RadioButtonGroup``. You don't use this type directly; instead,
/// the `@RadioButtonGroupBuilder` attribute is applied to the trailing closure of
/// ``RadioButtonGroup/init(selection:orientation:isDisabled:builder:)``.
///
/// ## Overview
///
/// When you write:
///
/// ```swift
/// RadioButtonGroup(selection: $choice) {
///     RadioButtonItem(.option1, "First Option")
///     RadioButtonItem(.option2, "Second Option")
///     RadioButtonItem(.option3, "Third Option")
/// }
/// ```
///
/// The `@RadioButtonGroupBuilder` attribute transforms this closure into an array
/// of ``RadioButtonItem`` instances that the group can render and manage.
///
/// ## Supported Control Flow
///
/// The builder supports:
/// - Multiple item expressions
/// - `if`/`else` conditionals
/// - `if let` optional binding
/// - `for`...`in` loops
///
/// They mix freely, and the items come out in the order they are written:
///
/// ```swift
/// RadioButtonGroup(selection: $format) {
///     RadioButtonItem("plain", "Plain text")
///     if showsRichText {
///         RadioButtonItem("rich", "Rich text")
///     } else {
///         RadioButtonItem("html", "Web page")
///     }
///     if let recent = recentFormat {
///         RadioButtonItem(recent, "Last used")
///     }
///     for name in customFormats {
///         RadioButtonItem(name, name)
///     }
/// }
/// ```
///
/// Every statement contributes a list of items — one item for an item, none or
/// some for an `if` or a loop — and the block joins the lists, as
/// `StatusBarItemBuilder` does. TUI's own API: SwiftUI has no radio group of
/// this shape (its radio buttons are `Picker` with `.pickerStyle(.radioGroup)`,
/// on macOS), so there is no SwiftUI builder for it to match.
@resultBuilder
public enum RadioButtonGroupBuilder<Value: Hashable> {
    /// Joins the items of each statement in the block, in written order.
    ///
    /// The builder's entry point: every `RadioButtonGroup { … }` produces one
    /// call to this. Each argument is one statement's items: a single item
    /// (``buildExpression(_:)``), or what an `if` or a loop produced. Taking
    /// the items themselves, as this once did, left an `if` or a `for` —
    /// whose result is a list — with nowhere to go, so neither compiled.
    public static func buildBlock(_ components: [RadioButtonItem<Value>]...) -> [RadioButtonItem<Value>] {
        components.flatMap { $0 }
    }

    /// Makes an item written in the block a list of one, so it joins the
    /// lists an `if` or a loop makes.
    public static func buildExpression(_ item: RadioButtonItem<Value>) -> [RadioButtonItem<Value>] {
        [item]
    }

    /// Supplies the empty list for an `if` with no `else` that did not run.
    ///
    /// What makes `if showAdvanced { RadioButtonItem(…) }` legal: the absent
    /// branch contributes no items rather than failing to type-check.
    public static func buildOptional(_ items: [RadioButtonItem<Value>]?) -> [RadioButtonItem<Value>] {
        items ?? []
    }

    /// Takes the `if` branch of an `if`/`else`.
    ///
    /// Paired with ``buildEither(second:)``; both arms of a conditional
    /// already produce the same type here, so neither erases anything.
    public static func buildEither(first items: [RadioButtonItem<Value>]) -> [RadioButtonItem<Value>] {
        items
    }

    /// Takes the `else` branch of an `if`/`else`. See ``buildEither(first:)``.
    public static func buildEither(second items: [RadioButtonItem<Value>]) -> [RadioButtonItem<Value>] {
        items
    }

    /// Flattens the per-iteration groups a `for`…`in` loop produces into one
    /// list, so a loop over a data array reads as the items it generates.
    public static func buildArray(_ itemGroups: [[RadioButtonItem<Value>]]) -> [RadioButtonItem<Value>] {
        itemGroups.flatMap { $0 }
    }
}

// MARK: - Radio Button Group

/// An interactive radio button group for single-selection from multiple options.
///
/// Radio buttons can be arranged vertically or horizontally. Each option is focusable
/// and supports keyboard navigation with arrow keys. Selection can be changed with Enter or Space.
///
/// ## Rendering
///
/// Vertical layout:
/// ```
/// ◯ Option 1
/// ● Option 2  (selected)
/// ◯ Option 3
/// ```
///
/// Horizontal layout:
/// ```
/// ◯ Option 1  ● Option 2  ◯ Option 3
/// ```
///
/// # Basic Example
///
/// ```swift
/// @State var selection: String = "option1"
///
/// RadioButtonGroup(selection: $selection) {
///     RadioButtonItem("option1") { Text("First Choice") }
///     RadioButtonItem("option2") { Text("Second Choice") }
///     RadioButtonItem("option3") { Text("Third Choice") }
/// }
/// ```
///
/// ## Options that carry their own controls
///
/// An option that takes a parameter can carry the control for it — see
/// ``RadioButtonItem``. The control is drawn under its option, indented to the
/// label, and it is live only while that option is the selection:
///
/// ```
///   ◯ True colour
///   ● Greys
///     Levels: 4  ├──●─────────┤     ← live
///   ◯ Sampled
///     Colours: 8 ├────●───────┤     ← drawn, disabled
/// ```
///
/// Every option's content is DRAWN whether or not it is selected, so the rows
/// an option occupies do not move as the selection does — a list that
/// rearranged itself while you arrowed down it would be unusable. What changes
/// is whether the content is enabled.
///
/// ## From the keyboard
///
/// The same shape as ``DisclosureGroup`` and ``OutlineGroup``, which is what a
/// group of options with things inside them is: **along** the group's axis to
/// move between siblings, **Right** to go in, **Left** to come back out.
///
/// - The group is ONE Tab stop, however many options it has. **Up** and
///   **Down** walk a vertical group, **Left** and **Right** a horizontal one;
///   **Home**, **End** and **Page** jump to its ends, and Shift accelerates the
///   on-axis arrow. **Return** or **Space** selects the option under the
///   cursor.
/// - **Right** (on a vertical group) steps out of the options and into the
///   selected option's controls, because those are the only controls in the
///   group that are enabled — an unselected option's are not focus stops at
///   all, so there is never a question of which option you have stepped into.
///   **Tab** does the same thing.
/// - **Left** comes back to the options — as ordinary focus movement, so a
///   control that wants Left for itself (a `Slider`, a `TextField`) keeps it
///   and **Shift-Tab** is the way back out of that one.
/// - The cross-axis arrow still leaves a group whose options carry nothing, as
///   it always has: there is nothing in that direction to step into, so the key
///   goes back to being focus movement. See
///   ``View/radioButtonGroupEdgeBehavior(_:)`` for what the ON-axis arrow does
///   at the first and last option.
nonisolated public struct RadioButtonGroup<Value: Hashable>: View {
    /// The binding to the selected value.
    let selection: Binding<Value>

    /// The items in the group.
    let items: [RadioButtonItem<Value>]

    /// The layout orientation.
    let orientation: RadioButtonOrientation

    /// The unique focus identifier for the group.
    /// Auto-generated if not provided, but must be stable across renders.
    var focusID: String?

    /// Whether the group is disabled.
    var isDisabled: Bool

    /// Whether the selection stands for values that disagree, so no option is
    /// marked — set by `Picker(sources:)`.
    var isMixed = false

    /// Creates a radio button group with items and a selection binding.
    ///
    /// - Parameters:
    ///   - selection: A binding to the selected value.
    ///   - orientation: The layout orientation (default: `.vertical`).
    ///   - isDisabled: Whether the group is disabled (default: false).
    ///   - builder: A builder closure that returns radio button items.
    public init(
        selection: Binding<Value>,
        orientation: RadioButtonOrientation = .vertical,
        isDisabled: Bool = false,
        @RadioButtonGroupBuilder<Value> builder: () -> [RadioButtonItem<Value>]
    ) {
        self.selection = selection
        self.items = builder()
        self.orientation = orientation
        self.focusID = nil
        self.isDisabled = isDisabled
    }

    /// Creates a radio button group from a pre-built array of items.
    ///
    /// - Parameters:
    ///   - selection: A binding to the selected value.
    ///   - orientation: The layout direction (default: .vertical).
    ///   - isDisabled: Whether the group is disabled (default: false).
    ///   - items: The radio button items to display.
    public init(
        selection: Binding<Value>,
        orientation: RadioButtonOrientation = .vertical,
        isDisabled: Bool = false,
        items: [RadioButtonItem<Value>]
    ) {
        self.selection = selection
        self.items = items
        self.orientation = orientation
        self.focusID = nil
        self.isDisabled = isDisabled
    }

    @MainActor public var body: some View {
        _RadioButtonGroupCore(
            selection: selection,
            items: items,
            orientation: orientation,
            focusID: focusID,
            isDisabled: isDisabled,
            isMixed: isMixed
        )
    }
}

// MARK: - Internal Core View

/// StateStorage property indices for ``_RadioButtonGroupCore``.
/// Lifted out of the generic struct because Swift does not
/// allow static stored properties in generic types.
private enum RadioButtonGroupStateIndex {
    static let handler = 0
    static let focusID = 1
    /// The index of the currently hovered item, or `-1` for
    /// none. A single shared StateBox covers the whole group
    /// because at most one item can be hovered at a time.
    static let hoveredIndex = 2
    /// The group's undo (``ControlValueUndo``).
    static let undo = 3
}

/// Internal view that handles the actual rendering of RadioButtonGroup.
private struct _RadioButtonGroupCore<Value: Hashable>: View, Renderable, Layoutable {
    let selection: Binding<Value>
    let items: [RadioButtonItem<Value>]
    let orientation: RadioButtonOrientation
    let focusID: String?
    let isDisabled: Bool
    /// The selection stands for values that disagree (`Picker(sources:)`), so
    /// no option is marked selected.
    var isMixed = false

    private typealias StateIndex = RadioButtonGroupStateIndex

    var body: Never {
        fatalError("_RadioButtonGroupCore renders via Renderable")
    }

    /// A radio group is fixed: its options lay out at their natural size (it does
    /// not fill), so a single render is its exact, fixed measure.
    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    /// Keeps the persisted handler in sync with the CURRENT render's values —
    /// every field the view declares, or the handler keeps the creation
    /// render's (a stale `orientation` kept the old arrow-axis mapping after
    /// a responsive layout flipped the group).
    private func syncHandler(
        _ handler: RadioButtonGroupHandler,
        selection: Binding<AnyHashable>,
        itemValues: [AnyHashable],
        isDisabled: Bool,
        context: RenderContext
    ) {
        handler.selection = selection
        handler.adopt(itemValues: itemValues)
        handler.disabledIndices = Set(items.indices.filter { items[$0].isDisabled })
        handler.orientation = orientation
        handler.canBeFocused = !isDisabled
        handler.edgeBehavior = context.environment.radioButtonGroupEdgeBehavior
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        handler.selectionFollowsCursor = context.environment.selectionFollowsCursor
        handler.followSelection()
    }

    /// `selection`, its value type erased, as the group's handler holds it.
    private static func erased(_ selection: Binding<Value>) -> Binding<AnyHashable> {
        Binding<AnyHashable>(
            get: { AnyHashable(selection.wrappedValue) },
            set: { newValue in
                if let typedValue = newValue.base as? Value {
                    selection.wrappedValue = typedValue
                }
            }
        )
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.stateStorage!

        // Create type-erased selection binding and item values. A choice a
        // person makes is a step in the app's undo manager.
        let selection = context.undoable(self.selection, propertyIndex: StateIndex.undo)
        let erasedSelection = Self.erased(selection)
        let itemValues = items.map { AnyHashable($0.value) }

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "radio-group",
            propertyIndex: StateIndex.focusID
        )

        // Get or create persistent handler from state storage.
        // The handler maintains focusedIndex across renders, enabling Tab navigation.
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<RadioButtonGroupHandler> = stateStorage.storage(
            for: handlerKey,
            default: RadioButtonGroupHandler(
                focusID: persistedFocusID,
                selection: erasedSelection,
                itemValues: itemValues,
                orientation: orientation,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value

        syncHandler(
            handler, selection: erasedSelection, itemValues: itemValues,
            isDisabled: isDisabled, context: context)

        FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. The group
        // keeps the focus and the arrows keep moving between items.
        let groupHasFocus = context.indicatesFocus(
            FocusRegistration.isFocused(context: context, focusID: persistedFocusID))

        // Hover state for the group — at most one item is
        // hovered at a time, so a single StateBox<Int> holds
        // its index (or `-1` for none). The per-item mouse
        // handlers flip it on .entered / .exited; the
        // renderer reads it per row below. Disabled groups
        // never show hover (mouse handlers below skip
        // registration entirely).
        let hoveredIndexKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.hoveredIndex)
        let hoveredIndexBox: StateBox<Int> = stateStorage.storage(
            for: hoveredIndexKey, default: -1)
        let hoveredIndex = isDisabled ? -1 : hoveredIndexBox.value

        // Render items based on orientation
        let rendered: RenderedItems
        switch orientation {
        case .vertical:
            rendered = renderVerticalWithRegions(
                context: context, handler: handler, groupHasFocus: groupHasFocus,
                hoveredIndex: hoveredIndex, palette: palette)
        case .horizontal:
            rendered = renderHorizontalWithRegions(
                context: context, handler: handler, groupHasFocus: groupHasFocus,
                hoveredIndex: hoveredIndex, palette: palette)
        }
        let itemRegions = rendered.regions

        // The items' own buffer, payload and all: an item's content may carry
        // hit regions, animated runs and overlays of its own, and a bare
        // `FrameBuffer(lines:)` here would silently drop every one of them.
        var buffer = rendered.buffer

        // Mouse: a left-button release on an item row selects that item
        // and grants the group focus. Each item gets its own hit-test
        // region so the dispatcher can identify which item was clicked.
        // The same per-item region drives the hover state — .entered
        // / .exited synthesised by the dispatcher flip the shared
        // hoveredIndexBox to that item's index (or back to -1).
        if !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            // Ask the dispatcher to enable motion reporting this
            // frame so the hover state machine sees .moved
            // events.
            mouseDispatcher.requestFeature(.motion, in: context)

            let focusManager = context.environment.focusManager
            let captureFocusID = persistedFocusID
            let captureItems = items
            // Already the undoable binding, from above.
            let captureSelection = selection
            let captureHoveredIndexBox = hoveredIndexBox
            // The options' own regions carry no focus id: the group's
            // goes on inert regions behind them (below the loop).
            for (index, region) in itemRegions.enumerated() {
                let mouseHandlerID = mouseDispatcher.register(in: context) { event in
                    switch event.phase {
                    case .entered:
                        captureHoveredIndexBox.value = index
                        return true
                    case .exited:
                        // Only clear if this is the index we
                        // claimed — protects against a fast
                        // cursor movement where .entered on the
                        // next item arrives before .exited on
                        // the previous item.
                        if captureHoveredIndexBox.value == index {
                            captureHoveredIndexBox.value = -1
                        }
                        return true
                    case .pressed where event.button == .left:
                        return true
                    case .released where event.button == .left:
                        // A disabled option takes no click (``RadioButtonItem/disabled(_:)``).
                        guard !captureItems[index].isDisabled else { return true }
                        focusManager?.focus(id: captureFocusID)
                        handler.focusedIndex = index
                        captureSelection.wrappedValue = captureItems[index].value
                        return true
                    default:
                        return false
                    }
                }
                // A click: a release off it chooses nothing (decisions B89).
                mouseDispatcher.fileClickRecognizer(.plain, for: mouseHandlerID, in: context)
                buffer.hitTestRegions.append(
                    HitTestRegion(
                        offsetX: region.x, offsetY: region.y, width: region.width, height: region.height,
                        handlerID: mouseHandlerID))
            }
            Self.publishFocusRegions(
                to: &buffer, itemRegions: itemRegions, handler: handler, focusID: captureFocusID,
                dispatcher: mouseDispatcher, context: context)
        }

        return buffer
    }

    /// Behind the options, inert regions carrying the group's focus id, one per
    /// option, the cursor's first: the first region carrying it is what a
    /// reveal within the group and the terminal's text cursor go to, so a
    /// scroll view's snap-to-focus anchors on the option the keys are on; the
    /// union is the group a reveal of it just arrived at shows; and the focus
    /// following the pointer finds the group under any option, not only the
    /// cursor's. Passive: a press goes to the option in front.
    ///
    /// While the focus follows the pointer, the cursor follows it too, as a
    /// list's cursor row does: a move onto another cell of an option, with the
    /// group holding the focus after it, puts the cursor on that option
    /// (``RadioButtonGroupHandler/followPointer(toOption:drawing:)``). Each
    /// option's region is then a handler of its own, which names its option,
    /// since the move comes in the region's own columns; otherwise one serves
    /// them all.
    @MainActor
    private static func publishFocusRegions(
        to buffer: inout FrameBuffer, itemRegions: [OptionRegion], handler: RadioButtonGroupHandler,
        focusID: String, dispatcher: MouseEventDispatcher, context: RenderContext
    ) {
        let cursor = handler.focusedIndex
        let follows = context.environment.focusFollowsPointer == true
        let shared = follows ? nil : dispatcher.registerPassive(in: context) { _ in false }
        let drawing = HandlerDrawing(context)
        let order =
            itemRegions.indices.contains(cursor)
            ? [cursor] + itemRegions.indices.filter { $0 != cursor } : Array(itemRegions.indices)
        buffer.hitTestRegions.insert(
            contentsOf: order.map { index in
                let region = itemRegions[index]
                let inert = shared ?? dispatcher.registerPassive(in: context) { _ in false }
                if shared == nil {
                    dispatcher.filePointerFocusFollower(for: inert, in: context) { [handler] _ in
                        handler.followPointer(toOption: index, drawing: drawing)
                    }
                }
                return HitTestRegion(
                    offsetX: region.x, offsetY: region.y, width: region.width, height: region.height, handlerID: inert,
                    focusID: focusID)
            },
            at: 0)
    }

    /// The items as one buffer, and where each option's own row sits within it.
    ///
    /// The buffer rather than a list of lines, because an item's content brings
    /// hit regions, animated runs, overlays and opacity regions of its own, and
    /// a bare `FrameBuffer(lines:)` would drop all four.
    ///
    /// The regions are the group's click targets, and they cover the OPTION
    /// rows only, every line of a label that takes several: the rows below an
    /// option belong to its content, which answers the pointer itself.
    private struct RenderedItems {
        let buffer: FrameBuffer
        let regions: [OptionRegion]
    }

    /// Where one option's rows sit within the items' buffer: its indicator and
    /// every line of its label, not its content.
    private typealias OptionRegion = (x: Int, y: Int, width: Int, height: Int)

    private func renderVerticalWithRegions(
        context: RenderContext,
        handler: RadioButtonGroupHandler,
        groupHasFocus: Bool,
        hoveredIndex: Int,
        palette: Palette
    ) -> RenderedItems {
        var buffer = FrameBuffer(lines: [])
        var regions: [OptionRegion] = []
        for (index, item) in items.enumerated() {
            let rendered = renderItem(
                item: item,
                isFocused: handler.focusedIndex == index && groupHasFocus,
                isSelected: !isMixed && selection.wrappedValue == item.value,
                isHovered: hoveredIndex == index,
                context: context,
                palette: palette
            )
            // Each item starts where the last one ended — which is one row on
            // for a plain option, and more when it carries content.
            regions.append(
                (x: 0, y: buffer.lines.count, width: rendered.optionWidth, height: rendered.optionHeight))
            buffer.appendVertically(rendered.buffer)
        }
        return RenderedItems(buffer: buffer, regions: regions)
    }

    private func renderHorizontalWithRegions(
        context: RenderContext,
        handler: RadioButtonGroupHandler,
        groupHasFocus: Bool,
        hoveredIndex: Int,
        palette: Palette
    ) -> RenderedItems {
        let spacingWidth = 2
        var buffer = FrameBuffer(lines: [])
        var regions: [OptionRegion] = []
        for (index, item) in items.enumerated() {
            let rendered = renderItem(
                item: item,
                isFocused: handler.focusedIndex == index && groupHasFocus,
                isSelected: !isMixed && selection.wrappedValue == item.value,
                isHovered: hoveredIndex == index,
                context: context,
                palette: palette
            )
            // The same predicate `appendHorizontally` uses: a gap is charged
            // only between two occupied column ranges, so the first item starts
            // at column 0 whatever it rendered.
            let originX = buffer.width > 0 ? buffer.width + spacingWidth : 0
            regions.append((x: originX, y: 0, width: rendered.optionWidth, height: rendered.optionHeight))
            buffer.appendHorizontally(rendered.buffer, spacing: spacingWidth)
        }
        return RenderedItems(buffer: buffer, regions: regions)
    }

    /// One item, drawn: the option row, and under it whatever that option
    /// carries.
    private struct RenderedItem {
        let buffer: FrameBuffer
        /// The option's own width, its widest label line's — see ``RenderedItems``.
        let optionWidth: Int
        /// The option's own rows: one for each line of its label.
        let optionHeight: Int
    }

    /// Renders one item: its indicator and label on the first row, the label's
    /// further lines under it, and its content — if it has any — indented
    /// underneath.
    ///
    /// The indent is the indicator plus the space after it, so the content
    /// starts under the LABEL rather than under the bullet: an option and the
    /// controls that configure it read as one thing.
    private func renderItem(
        item: RadioButtonItem<Value>,
        isFocused: Bool,
        isSelected: Bool,
        isHovered: Bool,
        context: RenderContext,
        palette: Palette
    ) -> RenderedItem {
        // Combine own + cascaded disabled (renderToBuffer's shadowing local does
        // not reach this helper), and the option's own.
        let isDisabled = self.isDisabled || !context.environment.isEnabled || item.isDisabled
        // Radio indicator: ● if selected OR focused; otherwise ◯ when enabled, or
        // ◌ (dotted circle) when disabled — a disabled, unselected option reads
        // as "not pickable". (A disabled control never holds focus, so a disabled
        // item is ● only when it is the current selection.)
        //
        // Without colour a ● that only means focus would be one more selected option,
        // since only the breath told them apart. The ● stays with the selection there,
        // and the focus reverses the label below — and so under Differentiate Without
        // Colour, where the breath is not to be relied on (`statesWithoutColor`),
        // and where the focus holds still (`focusHoldsStill`): a still breath sits
        // at its bright end, the accent a selected option's ● rests in, so the two
        // ●s were the same.
        //
        // Where text is spelled in ASCII, the indicators are their ASCII forms,
        // `(*)` and `( )`: folded at output, `●` was an `o` and `◯` a blank, so
        // nothing said the options were radio buttons until one was picked.
        let focusWithoutBreath = isFocused && (context.statesWithoutColor || context.focusHoldsStill)
        let ascii = context.textSpelling.isASCII
        let indicator: String
        if isSelected || (isFocused && !focusWithoutBreath) {
            indicator = ascii ? TerminalSymbols.ASCII.radioSelected : TerminalSymbols.radioSelected
        } else if isDisabled {
            indicator = ascii ? TerminalSymbols.ASCII.radioDisabledUnselected : TerminalSymbols.radioDisabledUnselected
        } else {
            indicator = ascii ? TerminalSymbols.ASCII.radioUnselected : TerminalSymbols.radioUnselected
        }

        // Determine indicator color based on state. Priority
        // order: disabled > focused > selected > hovered >
        // default. Hover thus only changes the look of an
        // unselected, unfocused item — focus and selection are
        // both more emphatic affordances and shouldn't
        // compete.
        let indicatorColor: Color
        // Set only on the focused branch: it is the one state in which the
        // indicator moves, and at most one item in a group is ever focused.
        var indicatorRun: AnimatedCellRun?
        if isDisabled {
            indicatorColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        } else if isFocused {
            // Focused: pulsing accent (whether selected or not) — taken as a
            // whole cycle rather than a phase, so the bullet can be handed to
            // the run loop to breathe on its own. Asking for the live phase
            // instead would keep the clock ticking and re-render this entire
            // page ten times a second to repaint one cell.
            // Both ends from `accentPulse()`. Written as a `dim` from there and a
            // bright of `palette.accent`, the two disagreed about a translucent
            // accent: the dim end spent its alpha against the page and the bright
            // end carried it, so half the pulse was a debug trap (§21).
            let (dimAccent, brightAccent) = palette.accentPulse()
            let cycle = context.environment.selectionEmphasis.cycle(true)
            indicatorColor = cycle.colorNow(dim: dimAccent, bright: brightAccent)
            if !context.isMeasuring {
                indicatorRun = cycle.run(
                    indicator, dim: dimAccent, bright: brightAccent, offsetX: 0, offsetY: 0)
            }
        } else if isSelected {
            // Selected but not focused: solid accent
            indicatorColor = palette.accent
        } else if isHovered {
            // Hovered (and neither focused nor selected): the resting colour
            // LIFTED, not a tint of its own. It used to be the accent at
            // `focusBorderDim`, and on a 256-colour terminal that landed on the
            // same cube entry as the dim resting colour — measured on Green,
            // hovering an unselected item changed `#005f00` to `#005f00`, which
            // is to say it did nothing at all.
            indicatorColor = palette.hoveredForeground(
                palette.foregroundTertiary.opacity(
                    ViewConstants.disabledForeground, over: palette.background))
        } else {
            // Unselected, unfocused, unhovered: dimmed.
            indicatorColor = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        }

        let styledIndicator = ANSIRenderer.colorize(
            indicator, foreground: indicatorColor.opaqueSpelling)

        // Every item renders at its OWN identity, one step off the group's, and
        // its label and content at one step further apiece. Without that the
        // items would share the group's storage slots with each other AND with
        // the group's own handler at index 0 — two sliders under two options
        // would be one slider. Keyed by the option's value, as `ForEach` keys a
        // row by its id, so an option's state goes with it when the options
        // are reordered or one is put in before it; by its place, it stayed
        // at the place, under whichever option came to be there.
        var itemContext = context.withChildIdentity(
            erasedType: RadioButtonItem<Value>.self, key: identityKey(item.value))
        // A disabled option's label and content are drawn as a disabled
        // control's are.
        if item.isDisabled { itemContext = itemContext.settingNotedEnvironment(\.isEnabled, to: false) }

        // Render label, tagged so its Text resolves `.control(.radioButton)`
        // style entries — but only when not already inside another control (e.g.
        // a Picker's radio-group style, which keeps its `.picker` identity). A
        // list's or a table's claim is no control's: it names the text of the
        // rows, and a radio group in a row is a control of its own.
        var labelContext = itemContext.withChildIdentity(erasedType: AnyView.self, index: 0)
        let claimed = labelContext.environment.controlKind
        if claimed == nil || claimed == .list || claimed == .table {
            labelContext.environment.controlKind = .radioButton
        }
        // A disabled option's label is drawn in the grey every disabled
        // control's label is, as a `Toggle`'s is. It was drawn as an enabled
        // one's: the item's own `.disabled()` set `isEnabled`, which a `Text`
        // does not read, and the group's flag set nothing at all, so only the
        // `◌` said the option could not be chosen (the owner's item 22,
        // 2026-11-10). The grey is the environment's foreground, so a label
        // with a colour of its own keeps it.
        if isDisabled {
            labelContext = labelContext.settingNotedEnvironment(
                \.foregroundStyle,
                to: labelContext.environment.foregroundStyle.keepingShadows(
                    on: .color(
                        palette.foregroundTertiary.opacity(
                            ViewConstants.disabledForeground, over: palette.background))), paint: true)
        } else if isHovered {
            // The whole row is the click target, so the whole row answers the
            // pointer — indicator and label together, the way a `Toggle` does.
            let base =
                labelContext.environment.foregroundStyle?.representative
                ?? labelContext.environment.styleCascade
                    .resolve(for: [.all, .text, .control(.radioButton)]).foreground
                ?? palette.foreground
            labelContext = labelContext.settingNotedEnvironment(
                \.foregroundStyle,
                to: labelContext.environment.foregroundStyle.keepingShadows(on: .color(palette.hoveredForeground(base))), paint: true)
        }
        let labelView = observingBodyClosure(of: Self.self, context: labelContext) { item.labelBuilder() }
        let labelBuffer = labelView.renderToBuffer(context: labelContext)

        // The indicator is one cell wide by construction — all three glyphs are
        // — or three in ASCII, and the space after it makes one more.
        let indentWidth = indicator.strippedLength + 1
        let indent = String.spaces(indentWidth)
        var lines = labelBuffer.lines.enumerated().map { row, line in
            row == 0 ? styledIndicator + " " + line : indent + line
        }
        if lines.isEmpty { lines = [styledIndicator + " "] }

        var buffer = FrameBuffer(lines: lines)
        // A label is usually a `Text`, but it is a VIEW, and a view that
        // rendered a button or an animated run has to keep it.
        buffer.overlays = labelBuffer.shiftedOverlays(byX: indentWidth, y: 0)
        buffer.hitTestRegions = labelBuffer.shiftedHitTestRegions(byX: indentWidth, y: 0)
        buffer.animatedCells = labelBuffer.shiftedAnimatedCells(byX: indentWidth, y: 0)
        buffer.opacityRegions = labelBuffer.shiftedOpacityRegions(byX: indentWidth, y: 0)
        if let indicatorRun {
            buffer.animatedCells.append(indicatorRun)
        } else if let claim = OpacityRegion.claim(
            width: indicator.strippedLength, height: 1, ink: indicatorColor)
        {
            // The indicator glyph's own alpha — reachable through a theme whose
            // `accent` or `foregroundTertiary` role is faded. Not while it pulses:
            // the run repaints this cell from its own frames, and the claim would
            // resolve every phase at the alpha of the one drawn now.
            buffer.opacityRegions.append(claim)
        }
        // Every line of the label is the option: a click on its second line
        // chooses it, and the focus reverses them all.
        let optionWidth = lines.reduce(0) { max($0, $1.strippedLength) }
        buffer = buffer
            .reversedWithoutBreath(
                if: isFocused && !isDisabled, rows: 0..<lines.count,
                columns: optionWidth > indentWidth ? indentWidth..<optionWidth : nil, context: context)
            .fadedWithoutColor(if: isDisabled, context: context)

        if let contentBuilder = item.contentBuilder {
            // Disabled unless this option is the chosen one — so an unselected
            // option's controls are neither editable nor focus stops, and
            // whatever the keyboard reaches below the group belongs to the
            // option that is actually selected. See ``RadioButtonItem``.
            let contentChildContext = itemContext.withChildIdentity(erasedType: AnyView.self, index: 1)
            let contentView = observingBodyClosure(of: Self.self, context: contentChildContext) { contentBuilder() }
                .padding(.leading, indentWidth)
                .disabled(isDisabled || !isSelected)
            buffer.appendVertically(
                TUIView.renderToBuffer(
                    contentView,
                    context: contentChildContext))
        }

        return RenderedItem(buffer: buffer, optionWidth: optionWidth, optionHeight: lines.count)
    }
}

// MARK: - Radio Button Group Convenience Modifiers

extension RadioButtonGroup {
    /// Creates a disabled version of this radio button group.
    ///
    /// - Parameter disabled: Whether the group is disabled.
    /// - Returns: A new group with the disabled state.
    public func disabled(_ disabled: Bool = true) -> RadioButtonGroup<Value> {
        var newGroup = self
        newGroup.isDisabled = isDisabled || disabled
        return newGroup
    }

    /// Sets a custom focus identifier for this radio button group.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A group with the specified focus identifier.
    public func focusID(_ id: String) -> RadioButtonGroup<Value> {
        var copy = self
        copy.focusID = id
        return copy
    }
}

@MainActor extension RadioButtonGroup: FormControlRow {}
