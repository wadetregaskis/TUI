//  🖥️ TUI — A Terminal UI framework for Swift
//  StyleScope.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIStyling

// MARK: - Control kind

/// A built-in interactive control, used to scope a style entry to the text of
/// every control of that kind in a subtree:
///
/// ```swift
/// SettingsForm().style(.control(.toggle)) { $0.italic = true }
/// ```
///
/// Each kind styles its control's *text* only; the control's chrome (brackets,
/// indicators, tracks, arrows) keeps its own colours. `.list` and `.table` name
/// the text of a `List`'s rows and of a `Table`'s cells, claimed by the list or
/// the table unless a control around it has claimed its text first (a
/// `Picker`'s, say, which keeps `.picker`).
public enum ControlKind: Sendable, Hashable {
    /// A button's label. Its brackets, background and focus glow are
    /// unchanged, and a `.destructive` role's error colour stays: a broad
    /// entry does not override it. ``StyleScope/buttonVariant(_:)`` narrows to
    /// one look.
    case button
    /// A toggle's label; the checkbox or switch is unaffected.
    case toggle
    /// A slider's value read-out; the track and arrows keep the tint.
    case slider
    /// A picker's label and option text.
    case picker
    /// A stepper's value read-out; the arrows are unaffected.
    case stepper
    /// A text field's entered text. The cursor, the selection highlight and the
    /// (dim) prompt keep their own colours.
    case textField
    /// A secure field's masked text.
    case secureField
    /// A radio button's label; the ●/○ indicator is unaffected.
    case radioButton
    /// A list row's text.
    case list
    /// A table cell's text.
    case table
    /// A colour picker's text.
    case colorPicker
}

// MARK: - Chrome role

/// A non-control structural element that draws text (so it can be styled by the
/// theme), e.g. a `Section`'s header in a `List` — outside a list a section's
/// header and footer are drawn as written, with no role.
public enum ChromeRole: Sendable, Hashable {
    case sectionHeader
    case sectionFooter
    case listRow

    /// The text attributes this role renders with by default — the baseline the
    /// style cascade overrides. Preserves TUI's established look: section
    /// headers are bold + dim, footers dim.
    public var defaultTextAttributes: StyleAttributes {
        switch self {
        case .sectionHeader: return StyleAttributes(bold: true, dim: true)
        case .sectionFooter: return StyleAttributes(dim: true)
        case .listRow: return StyleAttributes()
        }
    }
}

// MARK: - Style scope

/// *What* a scoped style entry applies to — its reach, not its priority.
///
/// A view matches a set of scopes (its "scope path"): a plain ``Text`` matches
/// `.all` and `.text` (plus `.semanticColor(role)` when it draws with a palette
/// role); a default button's label additionally matches `.control(.button)` and
/// `.buttonVariant(.automatic)`. Resolution (see ``StyleCascade``) is
/// **proximity-dominant** — the entry applied closest to the view wins — so a
/// scope governs *reach*; precedence between ancestors is decided by position,
/// matching SwiftUI's environment.
///
/// Specificity (below) is used only to order entries that live at the *same*
/// place — within one `Theme` bundle or a single multi-scope application — where
/// the more specific entry should win.
public enum StyleScope: Sendable, Hashable {
    /// Everything.
    case all
    /// Any rendered text.
    case text
    /// Text drawn with a specific palette role, e.g. `.foregroundSecondary`.
    case semanticColor(SemanticColor)
    /// Any control of a kind.
    case control(ControlKind)
    /// Buttons of one built-in look, e.g. `.buttonVariant(.borderedProminent)`:
    /// narrower than `.control(.button)`, which reaches every button.
    ///
    /// Typed, and a case of its own rather than a `(ControlKind, variant)`
    /// pair, because a button is the only control with variants: a pair would
    /// have to carry the variant as a string every other kind leaves unused.
    /// A control that grows variants later gets a case beside this one.
    case buttonVariant(Button.Variant)
    /// A structural chrome element, e.g. a section header.
    case chrome(ChromeRole)
    /// Text carrying a semantic ``Font/TextStyle``, e.g. `.headline`. Lets a
    /// theme redefine what a semantic style looks like, since the mapping in
    /// ``Font`` is only a default.
    case font(Font.TextStyle)

    /// How narrow this scope is. Used only to order entries within a single
    /// application point (a `Theme` bundle); across the view tree, proximity
    /// decides (see ``StyleCascade``).
    public var specificity: Int {
        switch self {
        case .all: return 0
        case .text, .control: return 1
        case .semanticColor, .buttonVariant, .chrome, .font: return 2
        }
    }
}

// MARK: - Value Hash

/// Read by a `switch` — a multi-payload enum's smaller payloads leave bytes
/// uninitialised, so its bytes cannot be read whole — and each case's payload
/// by its own plan. See `_ValueHashing`.
extension StyleScope: _ValueHashing {
    package static func _mixValueHash(
        at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans
    ) -> Bool {
        switch unsafe pointer.assumingMemoryBound(to: Self.self).pointee {
        case .all: plans.mixCase(0, (), into: &hash)
        case .text: plans.mixCase(1, (), into: &hash)
        case .semanticColor(let color): plans.mixCase(2, color, into: &hash)
        case .control(let kind): plans.mixCase(3, kind, into: &hash)
        case .buttonVariant(let variant): plans.mixCase(4, variant, into: &hash)
        case .chrome(let role): plans.mixCase(5, role, into: &hash)
        case .font(let style): plans.mixCase(6, style, into: &hash)
        }
    }
}
