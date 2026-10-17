//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizationKeys.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Localization Keys

/// Type-safe localization keys for all framework strings.
///
/// Provides compile-time safety and IDE autocomplete for all localized strings
/// in the framework. Keys are organized by category matching the JSON structure.
///
/// # Example
///
/// ```swift
/// Text(localized: LocalizationKey.Button.ok)
/// Text(localized: LocalizationKey.Error.notFound)
/// ```
///
/// Pass the key itself, not its `rawValue`: the typed overloads read it as one
/// of TUIkit's own words, which an app's `Localizable.strings` does not
/// change, while a `String` is read as the app's own key — so
/// `Text(localized: LocalizationKey.Button.ok.rawValue)` shows an app's
/// `"button.ok"` from `Localizable.strings` where TUIkit's OK is meant (see
/// ``LocalizationService``).
public enum LocalizationKey {
    /// Button labels and actions
    public enum Button: String {
        case ok = "button.ok"
        case cancel = "button.cancel"
        case yes = "button.yes"
        case no = "button.no"
        case save = "button.save"
        case delete = "button.delete"
        case close = "button.close"
        case apply = "button.apply"
        case reset = "button.reset"
        case submit = "button.submit"
        case search = "button.search"
        case clear = "button.clear"
        case add = "button.add"
        case remove = "button.remove"
        case edit = "button.edit"
        case done = "button.done"
        case next = "button.next"
        case previous = "button.previous"
        case back = "button.back"
        case forward = "button.forward"
        case refresh = "button.refresh"
        case rename = "button.rename"
        case paste = "button.paste"
        /// The screen selection's context-menu item.
        case copy = "button.copy"
        case replace = "button.replace"
        case replaceAll = "button.replaceAll"
    }

    /// Label and field names
    /// `CaseIterable` for the same reason as ``StatusBar``: so the consistency
    /// tests enumerate the group rather than restating it.
    public enum Label: String, CaseIterable {
        case search = "label.search"
        case name = "label.name"
        case description = "label.description"
        case value = "label.value"
        case status = "label.status"
        case error = "label.error"
        case warning = "label.warning"
        case info = "label.info"
        case success = "label.success"
        case loading = "label.loading"
        case empty = "label.empty"
        case none = "label.none"
        case page = "label.page"
        case item = "label.item"
        case items = "label.items"
        case total = "label.total"
        case from = "label.from"
        case to = "label.to"
        case gradient = "label.gradient"
        /// What an empty `List` or `Table` shows by default.
        case noItems = "label.noItems"
        /// `ToneCurveEditorPanel`'s readout caption.
        case position = "label.position"
        // `ColorPickerPanel`'s nine semantic roles; the other four are above.
        case foreground = "label.foreground"
        case secondary = "label.secondary"
        case accent = "label.accent"
        case border = "label.border"
        case background = "label.background"

        // `ContentUnavailableView.search`'s prose. Framework text, so it is
        // keyed here rather than written as a `Text` literal: a literal IS
        // looked up, but under the key "No Results", which is prose and so can
        // collide with an app's own — the reason every framework key is
        // dot-separated.
        case noResults = "label.noResults"
        /// Carries the query as `%@`, so a translation can move it.
        case noResultsFor = "label.noResultsFor"
        case noResultsHint = "label.noResultsHint"
        /// The default title of `dialogSuppressionToggle(isSuppressed:)`.
        case suppressDialog = "label.suppressDialog"
        case find = "label.find"
        case replaceWith = "label.replaceWith"
        /// A table's column menu: the item that hides the column it was opened
        /// on, its title as `%@`.
        case hideColumn = "label.hideColumn"
        /// A toolbar's sidebar button, while the sidebar is hidden: its help.
        case showSidebar = "label.showSidebar"
        /// A toolbar's sidebar button, while the sidebar shows: its help.
        case hideSidebar = "label.hideSidebar"
        /// A toolbar's inspector button, while the inspector is hidden: its help.
        case showInspector = "label.showInspector"
        /// A toolbar's inspector button, while the inspector shows: its help.
        case hideInspector = "label.hideInspector"
        /// A toolbar's content-column button, while a three-column split
        /// view's content column is hidden: its help.
        case showContentColumn = "label.showContentColumn"
        /// A toolbar's content-column button, while the content column shows:
        /// its help.
        case hideContentColumn = "label.hideContentColumn"
        /// A toolbar's panel button a label named, while the panel is hidden:
        /// its help, the name as `%@`.
        case showNamedPanel = "label.showNamedPanel"
        /// A toolbar's panel button a label named, while the panel shows: its
        /// help, the name as `%@`.
        case hideNamedPanel = "label.hideNamedPanel"
    }

    /// Border appearance names, as shown in a settings screen.
    ///
    /// ``Appearance/name`` is the identifier capitalised, which is right for a
    /// `Cyclable`'s identity and wrong for a label — see
    /// ``Appearance/localizedName``.
    public enum Appearance: String {
        case rounded = "appearance.rounded"
        case line = "appearance.line"
        case doubleLine = "appearance.doubleLine"
        case heavy = "appearance.heavy"
        case braille = "appearance.braille"
        case braille2 = "appearance.braille2"
        case block = "appearance.block"
        case blank = "appearance.blank"
    }

    /// Error messages
    public enum Error: String {
        case invalidInput = "error.invalid_input"
        case requiredField = "error.required_field"
        case notFound = "error.not_found"
        case accessDenied = "error.access_denied"
        case networkError = "error.network_error"
        case unknown = "error.unknown"
        case invalidFormat = "error.invalid_format"
        case operationFailed = "error.operation_failed"
        case timeout = "error.timeout"
        case fileNotFound = "error.file_not_found"
        case permissionDenied = "error.permission_denied"
    }

    /// Placeholder text for input fields
    public enum Placeholder: String {
        case search = "placeholder.search"
        case enterText = "placeholder.enter_text"
        case enterValue = "placeholder.enter_value"
        case selectOption = "placeholder.select_option"
        case enterName = "placeholder.enter_name"
        case chooseFile = "placeholder.choose_file"
    }

    /// Menu items and sections
    public enum Menu: String {
        case file = "menu.file"
        case edit = "menu.edit"
        case view = "menu.view"
        case help = "menu.help"
        case new = "menu.new"
        case open = "menu.open"
        case save = "menu.save"
        case exit = "menu.exit"
        /// The Undo command, before the action's name.
        case undo = "menu.undo"
        /// The Redo command, before the action's name.
        case redo = "menu.redo"
        /// A link's context menu: show its destination, in the popover
        /// activating it raises.
        case showLink = "menu.showLink"
        /// A link's context menu: copy its destination.
        case copyLink = "menu.copyLink"
        /// A link's context menu: copy the words it shows, where they are not
        /// its destination.
        case copyLinkLabel = "menu.copyLinkLabel"
        /// A link's context menu: copy it as a Markdown link.
        case copyLinkAsMarkdown = "menu.copyLinkAsMarkdown"
        /// A text field's or editor's context menu: cut the selection.
        case cut = "menu.cut"
        /// A text field's or editor's context menu: select all the text.
        case selectAll = "menu.selectAll"
        /// A text field's or editor's context menu: insert the text the last
        /// kill (Ctrl-K) removed, as Ctrl-Y does.
        case yank = "menu.yank"
    }

    /// Dialog titles and messages
    public enum Dialog: String {
        case confirm = "dialog.confirm"
        case deleteConfirmation = "dialog.delete_confirmation"
        case unsavedChanges = "dialog.unsaved_changes"
        case overwriteConfirmation = "dialog.overwrite_confirmation"
        case exitConfirmation = "dialog.exit_confirmation"
        case success = "dialog.success"
        case error = "dialog.error"
    }

    /// Validation messages
    public enum Validation: String {
        case emailInvalid = "validation.email_invalid"
        case passwordTooShort = "validation.password_too_short"
        case usernameTaken = "validation.username_taken"
        case fieldRequired = "validation.field_required"
    }

    /// Built-in status bar labels: the three standing items, and the verbs the
    /// framework publishes for the two common keys.
    ///
    /// The verbs are the framework's own words, not the app's — a focused
    /// `Toggle` says what Return does to it, a `NavigationStack` says what
    /// Escape does over it — so they belong here beside `quit`/`appearance`/
    /// `theme` rather than being spelled as literals at the sites that publish
    /// them. They were literals until they were not: a translated app showed
    /// "go back" and "close popover" in English next to a correctly translated
    /// "beenden".
    ///
    /// `CaseIterable` so the consistency tests can enumerate the group instead
    /// of restating it: the hand-written list they kept was already three
    /// entries out of date the moment this enum grew, and a key absent from
    /// that list is a key nothing checks.
    public enum StatusBar: String, CaseIterable {
        case quit = "statusbar.quit"
        case appearance = "statusbar.appearance"
        case theme = "statusbar.theme"
        /// The app's undo manager's undo, while it has a step to undo.
        case undo = "statusbar.undo"
        /// The app's undo manager's redo, while it has a step to redo.
        case redo = "statusbar.redo"

        // MARK: What Return does to the focused control

        /// A button on the page.
        case activate = "statusbar.activate"
        /// A row of an open menu, or an open drop-down's option.
        case choose = "statusbar.choose"
        /// A `Toggle`.
        case toggle = "statusbar.toggle"
        /// A list row that has an action of its own.
        case open = "statusbar.open"
        /// A list row that has not — Return settles the selection on it.
        case select = "statusbar.select"
        /// A text field the caller gave something to submit to.
        case submit = "statusbar.submit"
        /// A split view's ▶ edge column, which brings a hidden column back.
        case showColumn = "statusbar.showColumn"
        /// A split view's leftmost divider, whose ◀ hides the column to its left.
        case hideColumn = "statusbar.hideColumn"
        /// A toolbar's sidebar button, while the sidebar is hidden.
        case showSidebar = "statusbar.showSidebar"
        /// A toolbar's sidebar button, while the sidebar shows.
        case hideSidebar = "statusbar.hideSidebar"
        /// A toolbar's inspector button, while the inspector is hidden.
        case showInspector = "statusbar.showInspector"
        /// A toolbar's inspector button, or the divider before an inspector,
        /// while the inspector shows.
        case hideInspector = "statusbar.hideInspector"
        /// A toolbar's content-column button, while the content column is
        /// hidden.
        case showContentColumn = "statusbar.showContentColumn"
        /// A toolbar's content-column button, while the content column shows.
        case hideContentColumn = "statusbar.hideContentColumn"
        /// A control that shows a panel a toolbar item's label named, the name
        /// as `%@`.
        case showNamedPanel = "statusbar.showNamedPanel"
        /// A control that hides a panel a toolbar item's label named, the name
        /// as `%@`.
        case hideNamedPanel = "statusbar.hideNamedPanel"

        // MARK: What Escape does over a surface or a mode

        /// A modal or an alert.
        case dismiss = "statusbar.dismiss"
        /// A sheet's, cover's or popover's cancel button, which Escape presses
        /// in place of the presentation's own dismissal
        /// (`DismissalGate.escapePressesCancelButton`).
        case cancel = "statusbar.cancel"
        /// A pushed `NavigationStack` destination.
        case goBack = "statusbar.goBack"
        case closePopover = "statusbar.closePopover"
        case closeSuggestions = "statusbar.closeSuggestions"
        /// A keyboard drag in progress.
        case cancelMove = "statusbar.cancelMove"
        case clearSelection = "statusbar.clearSelection"
        case stopExtendingSelection = "statusbar.stopExtendingSelection"
        /// A table's column picked from the keyboard (Ctrl-K).
        case stopEditingColumns = "statusbar.stopEditingColumns"

        // MARK: What became of a copy (`ClipboardWriter`)

        /// On the clipboard: written here while the user is here, or sent to a
        /// terminal that writes OSC 52 by default.
        case copied = "statusbar.copied"
        /// Sent by OSC 52 to a terminal that may not write it — a setting
        /// decides, or tmux passes it on. No terminal acknowledges one.
        case sentToTerminalClipboard = "statusbar.sentToTerminalClipboard"
        /// No route reaches the user's clipboard.
        case notCopiedNoClipboard = "statusbar.notCopiedNoClipboard"
        /// This machine's clipboard helper ran and failed.
        case notCopiedHelperFailed = "statusbar.notCopiedHelperFailed"
        /// A paste chord found neither this machine's clipboard (it is not the
        /// user's) nor a copy of the app's own: the terminal's paste is the
        /// way in.
        case pasteWithTerminal = "statusbar.pasteWithTerminal"
        /// A paste chord found not this machine's clipboard (it is not known
        /// to be the user's) but the app's own latest copy, and pasted that:
        /// the user's own clipboard is the terminal's paste.
        case pastedAppCopy = "statusbar.pastedAppCopy"

        // MARK: The menu pair

        // A verb and a noun rather than four whole phrases, because the pair is
        // read as a pair — see ``MenuPresentationLabels``. The noun is
        // substituted with `%@`, so a translation places it wherever its
        // grammar wants ("%@ öffnen", "%@を開く") rather than being forced into
        // English word order.
        case openMenu = "statusbar.menu.open"
        case closeMenu = "statusbar.menu.close"
        case menuDropDown = "statusbar.menu.dropDown"
        case menuPopUp = "statusbar.menu.popUp"
    }

    /// The keys whose name is a word wherever TUIkit names a key (see
    /// `KeySymbols`): only the space bar, the one key macOS names in a menu
    /// rather than drawing a symbol for, in the words macOS uses. Internal: an
    /// app names a key through ``KeyboardShortcut/displayString``.
    package enum KeyName: String, CaseIterable {
        case space = "key.space"
    }

    /// The names of years and months in a span, for the platforms whose
    /// Foundation cannot spell them (`TimeSpan.tableUnitList`): a pattern per
    /// unit, width and CLDR plural category, `%@` standing for the count.
    /// Looked up by the locale's language, not the app's. Internal: they are
    /// the framework's own words for Foundation's, not an app's to reuse.
    enum TimeSpan: String, CaseIterable {
        case yearWideOne = "timeSpan.year.wide.one"
        case yearWideOther = "timeSpan.year.wide.other"
        case yearAbbreviatedOne = "timeSpan.year.abbreviated.one"
        case yearAbbreviatedOther = "timeSpan.year.abbreviated.other"
        case monthWideOne = "timeSpan.month.wide.one"
        case monthWideOther = "timeSpan.month.wide.other"
        case monthAbbreviatedOne = "timeSpan.month.abbreviated.one"
        case monthAbbreviatedOther = "timeSpan.month.abbreviated.other"
    }
}

extension LocalizationService {
    /// Retrieves a localized string for a typed key.
    ///
    /// # Example
    ///
    /// ```swift
    /// let okText = LocalizationService.shared.string(for: LocalizationKey.Button.ok)
    /// let errorText = LocalizationService.shared.string(for: LocalizationKey.Error.notFound)
    /// ```
    public func string(for key: LocalizationKey.Button) -> String {
        frameworkString(for: key.rawValue)
    }

    /// Retrieves a localized string for a label key.
    public func string(for key: LocalizationKey.Label) -> String {
        frameworkString(for: key.rawValue)
    }

    /// Retrieves a localized string for an error key.
    public func string(for key: LocalizationKey.Error) -> String {
        frameworkString(for: key.rawValue)
    }

    /// Retrieves a localized string for a placeholder key.
    public func string(for key: LocalizationKey.Placeholder) -> String {
        frameworkString(for: key.rawValue)
    }

    /// Retrieves a localized string for a menu key.
    public func string(for key: LocalizationKey.Menu) -> String {
        frameworkString(for: key.rawValue)
    }

    /// Retrieves a localized string for a dialog key.
    public func string(for key: LocalizationKey.Dialog) -> String {
        frameworkString(for: key.rawValue)
    }

    /// Retrieves a localized string for a validation key.
    public func string(for key: LocalizationKey.Validation) -> String {
        frameworkString(for: key.rawValue)
    }

    /// Retrieves a localized string for a status bar key.
    public func string(for key: LocalizationKey.StatusBar) -> String {
        frameworkString(for: key.rawValue)
    }
}
