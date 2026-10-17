//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextField.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - TextField

/// A control that displays an editable text interface.
///
/// You create a text field with a label and a binding to a string value.
/// The text field updates this value continuously as the user types.
///
/// ## Rendering
///
/// The text field renders as `[ text content ]` with a visible cursor when focused.
/// When empty, it displays the prompt text in dim styling — or, with no prompt,
/// its title, as SwiftUI's field "uses either the prompt or label as
/// placeholder text, depending on whether the initializer provided a prompt".
/// A form row written `LabeledContent("Name") { TextField("", text: $name) }`
/// has neither, and stays blank.
///
/// ```
/// Unfocused, empty:     [ Enter username... ]    (prompt in dim)
/// Unfocused, with text: [ john.doe           ]   (text in normal)
/// Focused, empty:       [ █                  ]   (cursor, brackets pulse)
/// Focused, with text:   [ john.d█e           ]   (cursor in text)
/// ```
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | Any printable | Insert character at cursor |
/// | Backspace | Delete character before cursor |
/// | Delete | Delete character at cursor |
/// | Option+Backspace / Option+Delete | Delete the word before / after the cursor |
/// | Left / Right | Move cursor one character |
/// | Option+Left | Move cursor to the start of the current (or previous) word |
/// | Option+Right | Move cursor to the end of the current (or next) word |
/// | Home / End | Move cursor to start / end of text |
/// | Shift+Left / Shift+Right | Extend selection one character |
/// | Shift+Option+Left / Right | Extend selection to the previous / next word boundary |
/// | Ctrl+A / Ctrl+E | Start / end of line |
/// | Ctrl+B / Ctrl+F | Back / forward one character |
/// | Ctrl+D | Delete forward (the selection, if there is one) |
/// | Ctrl+K | Kill to the end (yank with Ctrl+Y) |
/// | Ctrl+Y | Yank the last kill (replacing the selection) |
/// | Ctrl+T | Transpose the two characters around the cursor |
/// | Option+Ctrl+A | Select all |
/// | Ctrl+C / Ctrl+X / Ctrl+V | Copy / cut the selection, paste (with nothing selected, Ctrl+C and Ctrl+X pass on to the app) |
/// | Ctrl+Z | Undo |
/// | Ctrl+Shift+Z | Redo, where the terminal tells it from Ctrl+Z (the kitty keyboard protocol) |
/// | Ctrl+U | Erase the entire field |
/// | Enter | Trigger onSubmit action |
///
/// Each change is registered with the app's undo manager
/// (``EnvironmentValues/undoManager``), so Ctrl-minus and the status bar's
/// "undo" take it back too, and Ctrl+Z is the app's undo, as ⌘Z is a window's
/// on macOS: it undoes the newest step in the app, which is the field's last
/// change unless the app registered something since. The app's undo manager
/// makes each event's changes one step — one key while keys arrive one at a
/// time, several when they arrive together (a fast typist, a burst over ssh);
/// outside a running app, Ctrl+Z takes back one key's change at a time from
/// the field's own history. Either way the last 50 are kept, and a change
/// older than that leaves the app's history too. The field's steps stay in
/// the app's history after it loses the focus, as its own history always
/// stayed, and leave it when the field leaves the screen.
/// It never brings back text the field did not produce: when the app replaces
/// the bound text, clearing the field in `onSubmit` or loading other text into
/// it, the field forgets its history. A ``SecureField`` keeps its own history
/// and registers nothing with the app's.
///
/// The Emacs-style Control chords name the same commands as in ``TextEditor``,
/// read from one table, but a field is a single line with a keyboard
/// selection, so some do something else:
///
/// - Ctrl+V pastes, where the editor pages down. Ctrl+O, Ctrl+P and Ctrl+N,
///   the editor's open a line, previous line and next line, do nothing in a
///   field and pass on to the rest of the app.
/// - Ctrl+D deletes a selection, as Delete does, and Ctrl+Y replaces one, as a
///   paste does. The editor drops its selection first and acts at the cursor.
/// - Option is read before Control, so Option+Ctrl+B and F move by a word,
///   as Option+B and F do. In the editor they move by a character.
///
/// An app's own keyboard shortcut on Ctrl+A, E, B, F, D, K, Y or T, or on
/// Option+B or F, wins the chord: under the default
/// ``EnvironmentValues/commandKey``, `.keyboardShortcut("f")` (Find) is Ctrl+F,
/// and pressing it in a focused field runs Find and leaves the field alone.
/// The keys and arrows do what those chords do, and a kill, yank or transpose
/// can be done by selecting and typing. The field keeps Option+Ctrl+A, which
/// has no other key, and its clipboard, undo and erase chords; Ctrl+C and
/// Ctrl+X only while text is selected, so with nothing selected an app's ⌘C
/// and ⌘X fire, and `QuitShortcut.ctrlC` quits. See <doc:KeyboardShortcuts>.
///
/// ## Vertical fields
///
/// `TextField("Notes", text: $notes, axis: .vertical)` wraps its text over
/// rows instead of scrolling one line sideways. It starts one row tall and
/// grows a row at a time as the text wraps or breaks, with no limit unless the
/// environment's line limit sets one; at the limit it stops growing and
/// scrolls to keep the caret in view. A range sets a floor as well:
///
/// ```swift
/// TextField("Notes", text: $notes, axis: .vertical)
///     .lineLimit(2...5)    // two rows to start, five at most
/// ```
///
/// The text wraps as the macOS text system wraps it: after a run of spaces,
/// which stays at the end of the row it breaks, or between the characters of
/// a word too long for a row, and always at a newline. The last cell of the
/// row is kept for the caret, so text wraps one cell short of the field's
/// edge. While the field is empty it grows to show its whole prompt.
///
/// It is still a text field, with a text field's keys — SwiftUI's vertical
/// field is the same field editor as one on a single line — so Return
/// submits, and these change:
///
/// | Key | Action |
/// |-----|--------|
/// | Up / Down, Ctrl+P / Ctrl+N | Move a row; from the first row Up goes to the start, from the last Down to the end |
/// | Shift+Up / Shift+Down | Extend the selection a row |
/// | Option+Return | Insert a newline |
/// | Ctrl+O | Insert a newline in front of the caret (open a line) |
/// | Ctrl+A / Ctrl+E | Start / end of the line the caret is on |
/// | Ctrl+K | Kill to the end of the line, or the newline at its end |
///
/// A paste keeps its line breaks. Option+Return is the macOS key, and reaches
/// the field where the terminal sends Option as Meta (see the note on
/// ``TextEditor``); elsewhere it arrives as a plain Return and submits. Ctrl+O
/// is macOS's too, and arrives from every terminal. macOS's Ctrl+Return, which
/// inserts a line separator, arrives from a terminal as a plain Return.
///
/// ## The selection and the caret where the terminal decides the colours
///
/// A selection is a tint of the palette's accent over the field, and a block
/// caret is the caret's own colour with the character punched out of it. A
/// palette may name colours the terminal decides instead — its own foreground
/// or background, or one of its sixteen slots — and until the terminal says
/// what it paints for those, there is no tint between them to draw: the
/// selection would be a solid accent under text nobody can check, or the field
/// itself, which marks nothing.
///
/// Selected cells then draw in **reverse video**, exchanging the cell's own ink
/// and field, and a block caret flips whatever the cell under it does — a plain
/// cell is reversed, and a cell already reversed by the selection is drawn
/// plain, so the caret marks itself the way a terminal's own block cursor does
/// over a selection. A blinking caret alternates the two; a pulsing one holds.
/// A bar or underscore caret is unaffected, as is a palette that states
/// ordinary colours, on any terminal. ``SecureField`` and ``TextEditor`` draw
/// the same way: the three share one renderer.
///
/// # Basic Example
///
/// ```swift
/// @State var username = ""
///
/// TextField("Username", text: $username)
/// ```
///
/// # With Prompt
///
/// ```swift
/// TextField("Email", text: $email, prompt: Text("you@example.com"))
/// ```
///
/// # With ViewBuilder Label
///
/// ```swift
/// TextField(text: $username, prompt: Text("Required")) {
///     Text("Username").bold()
/// }
/// ```
///
/// # With Submit Action
///
/// ```swift
/// TextField("Search", text: $query)
///     .onSubmit {
///         performSearch()
///     }
/// ```
public struct TextField<Label: View>: View {
    /// The label view describing the field's purpose.
    let label: Label

    /// The binding to the text content.
    let text: Binding<String>

    /// Optional prompt text shown when the field is empty.
    let prompt: Text?

    /// The unique focus identifier.
    var focusID: String?

    /// Whether the text field is disabled.
    var isDisabled: Bool

    /// Action to perform when the user submits (presses Enter).
    var onSubmitAction: (() -> Void)?

    /// Action fired when editing begins (`true`) and ends (`false`).
    var onEditingChangedAction: ((Bool) -> Void)?

    /// Set when the field edits a typed value rather than a `String` — see
    /// ``init(value:format:prompt:label:)``. `text` is then unused: the string
    /// being edited is a draft the bridging view holds, not the caller's.
    var formatting: _FieldValueFormatting?

    /// The axis the field's text runs along when it does not fit: one line
    /// scrolling sideways, or rows growing downward — the `axis:` initialisers.
    var axis: Axis = .horizontal

    /// The app's selection binding, as the field reads and writes it, or `nil`
    /// for none — the `selection:` initialisers.
    var selection: _TextSelectionChannel?

    /// Where the field's context menu finds its handler — the same object
    /// frame after frame, so the menu and a memo of it see one value.
    @State private var menuTarget = TextEditingMenuTarget()

    @ViewBuilder
    public var body: some View {
        if let formatting {
            _FormattedFieldBody(
                formatting: formatting,
                prompt: fieldPrompt(prompt, title: label),
                label: label,
                focusID: focusID,
                isDisabled: isDisabled,
                onSubmitAction: onSubmitAction,
                onEditingChangedAction: onEditingChangedAction
            )
        } else {
            _StyledFieldFrame(
                content: _TextFieldCore(
                    label: label,
                    text: text,
                    prompt: fieldPrompt(prompt, title: label),
                    focusID: focusID,
                    isDisabled: isDisabled,
                    onSubmitAction: onSubmitAction,
                    onEditingChangedAction: onEditingChangedAction,
                    axis: axis,
                    selection: selection,
                    menuTarget: menuTarget
                )
            )
            .textEditingMenu(menuTarget)
        }
    }
}

/// What a field shows while it is empty: its prompt, or with none its title,
/// as SwiftUI's field does — "the text field uses either the prompt or label
/// as placeholder text, depending on whether the initializer provided a
/// prompt". A title of the app's own views, or an empty one — the
/// `LabeledContent("Name") { TextField("", …) }` a form row is written with —
/// gives none.
@MainActor
func fieldPrompt<Title: View>(_ prompt: Text?, title: Title) -> Text? {
    if let prompt { return prompt }
    guard let title = title as? Text, !title.content.isEmpty else { return nil }
    return title
}

// MARK: - TextField Initializers (Label == Text)

extension TextField where Label == Text {
    /// Creates a text field with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the field's title, describing its purpose.
    ///   - text: The text to display and edit.
    @inlinable
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(verbatimTitle: titleKey.localized, text: text, prompt: nil)
    }

    /// Creates a text field with a localized label and a prompt.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the field's title, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A `Text` providing guidance on what to type into the field.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
        self.init(verbatimTitle: titleKey.localized, text: text, prompt: prompt)
    }

    /// Creates a text field with a text label generated from a title string.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    ///
    /// - Parameters:
    ///   - title: The title of the text field, describing its purpose.
    ///   - text: The text to display and edit.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>) {
        self.init(verbatimTitle: String(title), text: text, prompt: nil)
    }

    /// Creates a text field with a prompt.
    ///
    /// Generic over `StringProtocol` for the same reason as
    /// ``init(_:text:)-(S,_)``. Only the title is a key: `prompt` is already a
    /// ``Text``, which did its own lookup where it was written.
    ///
    /// - Parameters:
    ///   - title: The title of the text field, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A Text representing the prompt which provides users with
    ///     guidance on what to type into the text field.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) {
        self.init(verbatimTitle: String(title), text: text, prompt: prompt)
    }

    /// The text field every `Text`-labelled initializer above makes: `title`
    /// drawn as it is, never looked up (the key initializers look it up first).
    ///
    /// Concrete, so a generic or key initializer that ends here builds the
    /// same field whatever string type it was given. The two key initializers
    /// used to go through the generic ones, and the generic ones each spelled
    /// the fields out.
    ///
    /// `@usableFromInline` for the `@inlinable` ``init(_:text:)-(LocalizedStringKey,_)``
    /// (module split step A3). It is not inlinable itself: it writes every stored
    /// property, and those would all have to be exported.
    @usableFromInline
    init(verbatimTitle title: String, text: Binding<String>, prompt: Text?) {
        self.label = Text(verbatim: title)
        self.text = text
        self.prompt = prompt
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
        self.onSubmitAction = nil
        self.onEditingChangedAction = nil
        self.formatting = nil
    }

    /// Creates a text field with a preferred axis and a localized label.
    ///
    /// On `.vertical` the text wraps over rows, and the field grows a row at a
    /// time as it is typed, up to its ``View/lineLimit(_:)-(Int?)``, then scrolls —
    /// see "Vertical fields" on ``TextField``. `.horizontal` is the field on
    /// one line.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the field's title, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - axis: The axis in which to scroll text when it doesn't fit in the
    ///     available space.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) {
        self.init(titleKey, text: text)
        self.axis = axis
    }

    /// Creates a text field with a preferred axis and a label generated from a
    /// title string.
    ///
    /// - Parameters:
    ///   - title: The title of the text field, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - axis: The axis in which to scroll text when it doesn't fit in the
    ///     available space.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis) {
        self.init(title, text: text)
        self.axis = axis
    }

    /// Creates a text field with a preferred axis, a localized label and a
    /// prompt.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the field's title, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A `Text` providing guidance on what to type into the field.
    ///     A vertical field grows to show all of it while the field is empty.
    ///   - axis: The axis in which to scroll text when it doesn't fit in the
    ///     available space.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?, axis: Axis) {
        self.init(titleKey, text: text, prompt: prompt)
        self.axis = axis
    }

    /// Creates a text field with a preferred axis, a label generated from a
    /// title string, and a prompt.
    ///
    /// - Parameters:
    ///   - title: The title of the text field, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - prompt: A `Text` providing guidance on what to type into the field.
    ///   - axis: The axis in which to scroll text when it doesn't fit in the
    ///     available space.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?, axis: Axis) {
        self.init(title, text: text, prompt: prompt)
        self.axis = axis
    }

    /// Creates a text field with a binding to the current selection and a
    /// localized label.
    ///
    /// The field writes its caret and selection to `selection` as they move,
    /// and a selection the app writes moves them — a ``TextSelection`` whose
    /// range is empty is the caret. A field selects one range, so a multiple
    /// selection selects its first.
    ///
    /// ```swift
    /// @State private var message = ""
    /// @State private var selection: TextSelection? = nil
    ///
    /// TextField("Message", text: $message, selection: $selection)
    /// ```
    ///
    /// - Parameters:
    ///   - titleKey: The key for the field's title, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - selection: The current selection.
    ///   - prompt: A `Text` providing guidance on what to type into the field.
    ///   - axis: The axis in which to scroll text when it doesn't fit in the
    ///     available space; `nil` for the field on one line.
    @available(macOS 15, *)
    public init(
        _ titleKey: LocalizedStringKey, text: Binding<String>, selection: Binding<TextSelection?>,
        prompt: Text? = nil, axis: Axis? = nil
    ) {
        self.init(titleKey, text: text, prompt: prompt, axis: axis ?? .horizontal)
        self.selection = _TextSelectionChannel(selection, text: text)
    }

    /// Creates a text field with a binding to the current selection and a
    /// label generated from a title string.
    ///
    /// - Parameters:
    ///   - title: The title of the text field, describing its purpose.
    ///   - text: The text to display and edit.
    ///   - selection: The current selection.
    ///   - prompt: A `Text` providing guidance on what to type into the field.
    ///   - axis: The axis in which to scroll text when it doesn't fit in the
    ///     available space; `nil` for the field on one line.
    @available(macOS 15, *)
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, text: Binding<String>, selection: Binding<TextSelection?>, prompt: Text? = nil,
        axis: Axis? = nil
    ) {
        self.init(title, text: text, prompt: prompt, axis: axis ?? .horizontal)
        self.selection = _TextSelectionChannel(selection, text: text)
    }
}

// MARK: - TextField Initializers (Generic Label)

extension TextField {
    /// Creates a text field with a prompt generated from a `Text` and a custom label.
    ///
    /// Use this initializer when you need a custom label view instead of a simple string.
    ///
    /// # Example
    ///
    /// ```swift
    /// TextField(text: $username, prompt: Text("Required")) {
    ///     HStack {
    ///         Text("Username").bold()
    ///         Text("*").foregroundStyle(.red)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - text: The text to display and edit.
    ///   - prompt: A Text representing the prompt which provides users with
    ///     guidance on what to type into the text field.
    ///   - label: A view that describes the purpose of the text field.
    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.text = text
        self.prompt = prompt
        self.focusID = nil
        self.isDisabled = false
        self.onSubmitAction = nil
        self.onEditingChangedAction = nil
        self.formatting = nil
    }

    /// Creates a text field with a preferred axis, a prompt generated from a
    /// `Text`, and a custom label.
    ///
    /// - Parameters:
    ///   - text: The text to display and edit.
    ///   - prompt: A `Text` providing guidance on what to type into the field.
    ///   - axis: The axis in which to scroll text when it doesn't fit in the
    ///     available space.
    ///   - label: A view that describes the purpose of the text field.
    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        axis: Axis,
        @ViewBuilder label: () -> Label
    ) {
        self.init(text: text, prompt: prompt, label: label)
        self.axis = axis
    }

    /// Creates a text field with a binding to the current selection, a prompt
    /// generated from a `Text`, and a custom label.
    ///
    /// The field writes its caret and selection to `selection` as they move,
    /// and a selection the app writes moves them. A field selects one range,
    /// so a multiple selection selects its first.
    ///
    /// - Parameters:
    ///   - text: The text to display and edit.
    ///   - selection: The current selection.
    ///   - prompt: A `Text` providing guidance on what to type into the field.
    ///   - axis: The axis in which to scroll text when it doesn't fit in the
    ///     available space; `nil` for the field on one line.
    ///   - label: A view that describes the purpose of the text field.
    @available(macOS 15, *)
    public init(
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.init(text: text, prompt: prompt, axis: axis ?? .horizontal, label: label)
        self.selection = _TextSelectionChannel(selection, text: text)
    }
}

// MARK: - TextField Modifiers

extension TextField {
    /// Creates a disabled version of this text field.
    ///
    /// Disabled once, it stays disabled: as with `View.disabled(_:)`, a later
    /// `.disabled(false)` does not enable it again.
    ///
    /// - Parameter disabled: Whether the text field is disabled.
    /// - Returns: A new text field with the disabled state.
    public func disabled(_ disabled: Bool = true) -> TextField {
        var copy = self
        copy.isDisabled = isDisabled || disabled
        return copy
    }

    /// Adds an action to perform when the user submits (presses Enter).
    ///
    /// Use this modifier to invoke an action when the user presses Enter
    /// while the text field has focus.
    ///
    /// # Example
    ///
    /// ```swift
    /// TextField("Search", text: $query)
    ///     .onSubmit {
    ///         performSearch()
    ///     }
    /// ```
    ///
    /// Applied more than once, every action runs, the first applied first, as
    /// SwiftUI runs every `.onSubmit` a submission reaches, the nearest first.
    ///
    /// - Parameter action: The action to perform on submit.
    /// - Returns: A text field that performs the action on submit.
    public func onSubmit(_ action: @escaping () -> Void) -> TextField {
        var copy = self
        copy.onSubmitAction = onSubmitAction.map { first in { first(); action() } } ?? action
        return copy
    }

    /// Adds an action fired when editing begins and ends: `true` as the
    /// field gains focus, `false` as it loses it.
    ///
    /// The `false` call is the "editing ended" commit point — a combo box
    /// records the entered value to its recents there, so a value that
    /// applied live isn't lost just because the user tabbed away instead of
    /// pressing Enter.
    ///
    /// (SwiftUI carries this signal as the classic
    /// `TextField(_:text:onEditingChanged:)` initializer parameter; TUIkit
    /// exposes it as a modifier, per its modifier-first convention for
    /// options beyond the core SwiftUI signatures.)
    ///
    /// - Parameter action: Receives `true` when editing begins, `false` when
    ///   it ends.
    /// - Returns: A text field that reports editing transitions.
    public func onEditingChanged(_ action: @escaping (Bool) -> Void) -> TextField {
        var copy = self
        copy.onEditingChangedAction = action
        return copy
    }

    /// Sets a custom focus identifier for this text field.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A text field with the specified focus identifier.
    public func focusID(_ id: String) -> TextField {
        var copy = self
        copy.focusID = id
        return copy
    }
}

// MARK: - Internal Core View

/// StateStorage property indices for ``_TextFieldCore``.
/// Lifted out of the generic struct because Swift does not
/// allow static stored properties in generic types.
enum TextFieldStateIndex {
    static let handler = 0
    static let focusID = 1
    static let isHovered = 2
}

/// Internal view that handles the actual rendering of TextField.
struct _TextFieldCore<Label: View>: View, Renderable, Layoutable {
    let label: Label
    let text: Binding<String>
    let prompt: Text?
    let focusID: String?
    let isDisabled: Bool
    let onSubmitAction: (() -> Void)?
    let onEditingChangedAction: ((Bool) -> Void)?

    /// `.vertical` for a field whose text wraps over rows — drawn by
    /// `TextField+Vertical.swift` — or `.horizontal` for one line.
    let axis: Axis

    /// The app's selection binding, or `nil` for none: set on the handler each
    /// render, which adopts what the app wrote there.
    let selection: _TextSelectionChannel?

    /// Where the field's context menu finds the handler, which the core
    /// writes there as it resolves it.
    let menuTarget: TextEditingMenuTarget

    /// Minimum width for the text field content area. Small, so an explicit
    /// narrow `.frame(width:)` is honoured (e.g. a 0–255 / "100%" numeric field
    /// that only needs room for a few characters plus the cursor); fields without
    /// a frame still open at ``defaultContentWidth``.
    let minContentWidth = 3

    /// Default visible width for the text field content area when no proposal is given.
    let defaultContentWidth = 20

    var body: Never {
        fatalError("_TextFieldCore renders via Renderable")
    }

    /// Returns the size this text field needs.
    ///
    /// TextField is width-flexible: it has a minimum width but expands
    /// to fill available horizontal space in HStack.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if axis == .vertical { return verticalSize(proposal: proposal, context: context) }
        // The rendered field is `openCap + content + closeCap`, so the total
        // width is the content width plus the two caps. Report that total so a
        // parent (e.g. HStack) allocates the field accurately. A `.plain` field
        // draws no caps, so they cost nothing — the number comes from the style
        // in both passes, through the one helper, so they cannot disagree.
        let capWidth = FieldChrome.width(for: context.environment.textFieldStyle)
        let proposedTotal = proposal.width ?? (defaultContentWidth + capWidth)
        return ViewSize(
            width: max(minContentWidth + capWidth, proposedTotal),
            height: 1,
            isWidthFlexible: true,
            isHeightFlexible: false
        )
    }

    typealias StateIndex = TextFieldStateIndex

    /// What Return does to this field, for the status bar — `nil` when the
    /// caller gave it nothing to submit to, which is what suppresses the entry.
    ///
    /// A property rather than a `let` in `renderToBuffer`: resolving it inline
    /// took that function to 101 lines against SwiftLint's 100-line ceiling,
    /// and the lookup is a self-contained question about this field anyway.
    var submitVerb: String? {
        guard onSubmitAction != nil else { return nil }
        return LocalizationService.shared.string(for: LocalizationKey.StatusBar.submit)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if axis == .vertical { return renderVertical(context: context) }
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let stateStorage = context.stateStorage!
        let palette = context.environment.palette
        let cursorStyle = context.environment.textCursorStyle

        // TextField expands to fill available width, less whatever chrome the
        // style draws (two cap cells, or none for `.plain`).
        let chrome = FieldChrome(
            style: context.environment.textFieldStyle, palette: palette,
            isHovered: false, on: context.environment.surfaceBackground,
            appearance: context.environment.appearance)
        let contentWidth = max(minContentWidth, context.availableWidth - chrome.width)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID,
            defaultPrefix: "textfield", propertyIndex: StateIndex.focusID)

        let handler = resolveHandler(
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            isDisabled: isDisabled,
            context: context)
        FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        FocusRegistration.publishActivationLabel(submitVerb, context: context, isFocused: isFocused)

        // Hover state persists across renders; the dispatcher
        // flips it on .entered / .exited events synthesised from
        // motion. Disabled fields suppress the visual effect.
        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && hoverBox.value

        // Diagnostic (TUIKIT_DEBUG_FOCUS=1): on every render, log
        // what *this* field's binding is reading, what focus it
        // has, and its identity path. When the visible bug is
        // "I typed Z into Search but it's showing up in Input",
        // the per-field render lines for the surrounding frames
        // tell us immediately whether Input's binding is actually
        // reading searchQuery's @State value, or whether the value
        // is right but landing in the wrong screen position.
        if !context.isMeasuring {
            debugFocusLog("""
                TextField render
                  focusID: \(persistedFocusID)
                  text.wrappedValue: \(text.wrappedValue.debugDescription)
                  isFocused: \(isFocused)
                  isMeasuring: \(context.isMeasuring)
                """)
        }

        // Input suggestions (``View/textInputSuggestions(_:)``): sync the
        // handler's completions and reserve two trailing columns for the ▾
        // affordance that marks the field as a combo box.
        let suggestionMenu = TextFieldSuggestions.prepare(
            isDisabled: isDisabled, handler: handler, currentText: text.wrappedValue,
            isFocused: isFocused, context: context)
        let textWidth =
            suggestionMenu != nil ? max(minContentWidth, contentWidth - 2) : contentWidth

        // Build the text field content using shared renderer. The entered text
        // honours a `.control(.textField)` cascade foreground (`.textFieldTextStyle`).
        let cascaded = context.environment.styleCascade.resolve(
            for: [.all, .text, .control(.textField)])
        // Identity: a text field draws what was typed. Written out rather than
        // passed as `{ $0 }` so the secure field's bullet has a visible twin.
        let displayCharacter: (Character) -> Character = { $0 }
        let renderer = TextFieldContentRenderer(
            prompt: prompt,
            isDisabled: isDisabled,
            displayCharacter: displayCharacter,
            surface: chrome.surface,
            contentForeground: cascaded.foreground,
            cursorSpeed: context.environment.indicatorAnimationSpeeds.speed(for: .textCursor),
            appearsActive: context.environment.appearsActive,
            legibilityWeight: context.environment.legibilityWeight
        )

        let fieldContent = renderer.buildContent(
            text: text.wrappedValue,
            cursorPosition: handler.cursorPosition,
            selectionRange: handler.selectionRange,
            isFocused: isFocused,
            palette: palette,
            cursorStyle: cursorStyle,
            cursorTimer: context.environment.cursorTimer,
            cursorTiming: context.environment.indicatorCycleTiming,
            contentWidth: textWidth
        )

        // The caps are half-block glyphs painted in the field surface — they
        // read as the field's rounded ends on any palette. Hover tints them
        // toward the accent so the affordance reads as "I'm clickable" without
        // mimicking the focused look (a focused field signals through its
        // caret, from the text renderer rather than the caps). A `.plain` field
        // has neither cap; `hoveredChrome` is the same chrome the width above
        // came from, re-derived with the hover tint.
        let hoveredChrome = FieldChrome(
            style: context.environment.textFieldStyle, palette: palette,
            isHovered: isHovered, on: context.environment.surfaceBackground,
            appearance: context.environment.appearance)

        // The ▾/▴ combo-box affordance sits inside the field surface, against
        // the trailing cap.
        let disclosure = Self.disclosureGlyph(
            isOpen: suggestionMenu?.isOpen, palette: palette, surface: chrome.surface)
        var buffer = FrameBuffer(
            text: hoveredChrome.open + fieldContent.line + disclosure.text
                + hoveredChrome.close)

        // The caret animates itself: its cells go to the run loop, which
        // repaints them on the cursor clock without re-rendering anything. Past
        // the opening cap, which is the only chrome before the content. See
        // ``AnimatedCellRun``.
        if !context.isMeasuring, let caret = fieldContent.caret {
            buffer.animatedCells = [caret.shifted(byX: chrome.leadingCells, y: 0)]
        }

        Self.attachFieldClaims(
            to: &buffer, content: fieldContent.claims, chrome: hoveredChrome,
            disclosure: disclosure.claims, contentStart: chrome.leadingCells,
            textWidth: textWidth)

        // Mouse: click focuses the field and drops the caret at the clicked
        // column; dragging selects. Hover rides on the same region. Shared with
        // SecureField. No-op while measuring or disabled.
        if !isDisabled {
            Self.attachMouse(
                to: &buffer, context: context, handler: handler,
                persistedFocusID: persistedFocusID, hoverBox: hoverBox, chrome: chrome,
                textWidth: textWidth, hasSuggestions: suggestionMenu != nil)
        }

        if let suggestionMenu, suggestionMenu.isOpen {
            TextFieldSuggestions.attach(
                menu: suggestionMenu, to: &buffer, handler: handler, context: context)
        }

        return buffer
    }

    /// Fetches (or creates) the persistent editing handler from StateStorage
    /// — it maintains the cursor position across renders — and syncs the
    /// per-frame bindings on it.
    /// Registers the click, drag and hover regions.
    ///
    /// The ▾ disclosure occupies the two cells between the content and the closing cap;
    /// clicks there toggle the menu, not the caret. Plus the cap itself, which is leeway
    /// rather than sloppiness: the arrow is ONE cell, the pad to its left already
    /// counts, and a pointer a single cell wide of a target that small has no way to see
    /// the miss coming. The cap is chrome with no click behaviour of its own, so nothing
    /// is taken from anything else — a press on it used to focus the field and drop the
    /// caret at the end, which is not what someone reaching for the arrow meant.
    private static func attachMouse(
        to buffer: inout FrameBuffer, context: RenderContext, handler: TextFieldHandler,
        persistedFocusID: String, hoverBox: StateBox<Bool>, chrome: FieldChrome,
        textWidth: Int, hasSuggestions: Bool
    ) {
        let leading = chrome.leadingCells
        let disclosureRange: Range<Int>? =
            hasSuggestions
            ? (leading + textWidth)..<(leading + textWidth + 2 + chrome.trailingCells) : nil
        TextFieldMouseHandler.register(
            buffer: &buffer,
            context: context,
            handler: handler,
            persistedFocusID: persistedFocusID,
            hoverBox: hoverBox,
            contentWidth: textWidth,
            // A text field draws what was typed. Written out here rather than threaded
            // through as a ninth parameter, and the secure field's bullet is the visible
            // twin of this line.
            displayCharacter: { $0 },
            leadingCapWidth: leading,
            disclosureRange: disclosureRange)
    }

    /// Everything a field's line owes, in the line's own columns.
    ///
    /// Three sources, each in a different frame, which is the whole reason this is one
    /// function: the CONTENT's claims are in the content's own frame and shift by the
    /// opening cap (the only chrome before it — the same shift the caret takes); the
    /// CAPS' need the finished line's width, because the trailing one sits at its end;
    /// and the ▾'s sit past the content. A faded `.textFieldTextStyle` foreground, a
    /// theme that faded the field surface, and a faded page whose surface now carries
    /// its alpha (§39) all arrive here rather than being spent on the escape.
    static func attachFieldClaims(
        to buffer: inout FrameBuffer, content: [OpacityRegion], chrome: FieldChrome,
        disclosure: [OpacityRegion], contentStart: Int, textWidth: Int
    ) {
        buffer.opacityRegions += content.map { $0.shifted(byX: contentStart, y: 0) }
        buffer.opacityRegions += chrome.claims(lineWidth: buffer.width)
        buffer.opacityRegions += disclosure.map {
            $0.shifted(byX: contentStart + textWidth, y: 0)
        }
    }

    /// The combo box's ▾/▴ affordance, drawn inside the field surface against
    /// the trailing cap, or `""` when the field has no suggestion menu.
    static func disclosureGlyph(
        isOpen: Bool?, palette: any Palette, surface: Color?
    ) -> ClaimingRow {
        var row = ClaimingRow()
        guard let isOpen else { return row }
        let caret = isOpen ? DropdownMenu.openCaret : DropdownMenu.closedCaret
        // Two cells — a pad and the arrow — in one run, which is what it always
        // emitted; `ClaimingRow` adds the claim its colours owe and states them
        // opaquely. Both can be faded: the ink is `foregroundSecondary` and the field
        // is the derived field surface.
        row.append(
            " " + caret, cells: 2, ink: palette.foregroundSecondary, field: surface)
        return row
    }
    func resolveHandler(
        persistedFocusID: String,
        stateStorage: StateStorage,
        isDisabled: Bool,
        context: RenderContext
    ) -> TextFieldHandler {
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<TextFieldHandler> = stateStorage.storage(
            for: handlerKey,
            default: TextFieldHandler(
                focusID: persistedFocusID,
                text: text,
                canBeFocused: !isDisabled,
                clipboard: context.environment.clipboardAccess,
                bell: context.environment.terminalBell
            )
        )
        let handler = handlerBox.value
        handler.text = text
        handler.canBeFocused = !isDisabled
        menuTarget.handler = handler
        // Compose the per-field closure with any cascading `.onSubmit(of:)` in
        // scope that matches this field's role (.text by default). Stays nil when
        // there's nothing to run, so Return still falls through to a dialog's
        // default button.
        handler.onSubmit = combinedSubmitAction(
            perField: onSubmitAction,
            cascading: context.environment.submitActions,
            role: context.environment.submitTriggerRole)
        handler.onEditingChanged = onEditingChangedAction
        handler.textContentType = context.environment.textContentType
        // The app's undo manager, which the field's edits are registered with,
        // and where the field leaves them when it goes away. `SecureField`
        // resolves its own handler and leaves both nil: a secure field's typing
        // is not something to undo from elsewhere.
        handler.undoManager = context.environment.undoManager
        handler.departedUndoSteps = context.environment.departedUndoSteps
        // Text the app replaced since the field wrote it (cleared on submit):
        // its steps leave the manager now, not at the field's next key, so the
        // bar and the undo keys do not go on offering undos that do nothing.
        if !context.isMeasuring { handler.forgetHistoryIfReplaced() }
        handler.selectionAffinity = context.environment.textSelectionAffinity
        // One line until a vertical field's render says otherwise, so a field
        // that changes axis between frames does not keep the old one's keys.
        // A drawing render's to say: a measure's probe width would leave the
        // keys moving by rows nobody sees (`TextField+Vertical`).
        if !context.isMeasuring { handler.wrapWidth = nil }
        handler.clampCursorPosition()
        handler.selectionChannel = selection
        // The app's selection is taken by the render that draws it.
        if !context.isMeasuring { handler.adoptSelectionFromApp() }
        return handler
    }
}

extension View {
    /// Styles the entered *text* of every text field in this view's subtree
    /// (a `.control(.textField)`-scoped style entry). The cursor, selection
    /// highlight, and the (dim) prompt keep their own colours.
    public func textFieldTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.textField), build)
    }
}
