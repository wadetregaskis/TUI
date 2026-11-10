//  🖥️ TUI — A Terminal UI framework for Swift
//  DialogEnvironment.swift
//
//  How the alerts and confirmation dialogs presented inside a view look:
//  `dialogSeverity(_:)` and `dialogIcon(_:)`, SwiftUI's, and
//  `dialogBorder(_:style:titleColor:)`, TUI's. Written outside the presenting
//  modifier, as SwiftUI's are, and read by the alert as it draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - DialogSeverity

/// The severity of an alert or confirmation dialog. Mirrors SwiftUI's
/// `DialogSeverity`.
///
/// Use it to say that people need to take extra care with a dialog — when an
/// action in it permanently deletes data, say:
///
/// ```swift
/// Button("Erase") { confirming = true }
///     .confirmationDialog("Erase every item?", isPresented: $confirming) {
///         Button("Erase", role: .destructive) { eraseAll() }
///     }
///     .dialogSeverity(.critical)
/// ```
///
/// macOS draws a critical dialog with a large caution symbol. A terminal starts
/// its title with the ⚠️ emoji, and draws its border and title in the
/// palette's warning colour unless the alert was given colours of its own.
public struct DialogSeverity: Equatable, Sendable {
    private enum Kind: Equatable, Sendable {
        case automatic, standard, critical
    }

    private let kind: Kind

    /// The default dialog severity. Alerts that present an error use
    /// ``critical`` and all others use ``standard``.
    public static let automatic = Self(kind: .automatic)

    /// A severity that indicates the dialog is being displayed for the purpose
    /// of presenting information to the user.
    public static let standard = Self(kind: .standard)

    /// A severity that indicates extra attention should be given to the
    /// dialog, for example when unexpected data loss may occur as a result of
    /// the action taken.
    public static let critical = Self(kind: .critical)
}

// MARK: - Environment

private struct DialogSeverityKey: EnvironmentKey {
    static let defaultValue = DialogSeverity.automatic
}

private struct DialogIconKey: EnvironmentKey {
    static let defaultValue: Image? = nil
}

private struct DialogBorderKey: EnvironmentKey {
    static let defaultValue = DialogBorder()
}

/// The border ``View/dialogBorder(_:style:titleColor:)`` gives the dialogs
/// presented in a view: each part `nil` where the dialog keeps its default.
package struct DialogBorder: Equatable, Sendable {
    /// The border's colour.
    package var color: Color?
    /// The box-drawing characters.
    package var style: BorderStyle?
    /// The colour of the title drawn in the top border.
    package var titleColor: Color?

    package init(color: Color? = nil, style: BorderStyle? = nil, titleColor: Color? = nil) {
        self.color = color
        self.style = style
        self.titleColor = titleColor
    }
}

private struct DialogPresentsErrorKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The severity of the dialogs presented in this environment — set by
    /// ``View/dialogSeverity(_:)``.
    package var dialogSeverity: DialogSeverity {
        get { self[DialogSeverityKey.self] }
        set { self[DialogSeverityKey.self] = newValue }
    }

    /// The icon the dialogs presented in this environment show — set by
    /// ``View/dialogIcon(_:)``.
    package var dialogIcon: Image? {
        get { self[DialogIconKey.self] }
        set { self[DialogIconKey.self] = newValue }
    }

    /// The border the dialogs presented in this environment are drawn with —
    /// set by ``View/dialogBorder(_:style:titleColor:)``.
    package var dialogBorder: DialogBorder {
        get { self[DialogBorderKey.self] }
        set { self[DialogBorderKey.self] = newValue }
    }

    /// Whether the alert being drawn describes an error — set on the alert's
    /// own context by the `error:` forms of `alert`, and what an
    /// ``DialogSeverity/automatic`` severity resolves by.
    var dialogPresentsError: Bool {
        get { self[DialogPresentsErrorKey.self] }
        set { self[DialogPresentsErrorKey.self] = newValue }
    }

    /// Whether the alert being drawn is critical, as its severity and its
    /// subject decide.
    var dialogIsCritical: Bool {
        dialogSeverity == .critical || (dialogSeverity == .automatic && dialogPresentsError)
    }
}

// MARK: - Modifiers

extension View {
    /// Sets the severity of the alerts and confirmation dialogs presented in
    /// this view. Mirrors SwiftUI's `dialogSeverity(_:)`.
    ///
    /// Apply it outside the presenting modifier, as SwiftUI's examples do; it
    /// reaches every dialog presented within the view.
    ///
    /// - Parameter severity: The severity to use for confirmation dialogs and
    ///   alerts.
    nonisolated public func dialogSeverity(_ severity: DialogSeverity) -> some View {
        environment(\.dialogSeverity, severity)
    }

    /// Configures the icon used by the alerts and confirmation dialogs
    /// presented in this view. Mirrors SwiftUI's `dialogIcon(_:)`.
    ///
    /// The icon is drawn at the leading edge of the dialog's message: an SF
    /// Symbol as its glyph, an image fitted into eight columns by four rows
    /// (about square in a terminal's cells). Passing `nil` uses the default,
    /// which in a terminal — with no app icon to show — is no icon.
    ///
    /// - Parameter icon: The custom icon to use for confirmation dialogs and
    ///   alerts, or `nil`.
    nonisolated public func dialogIcon(_ icon: Image?) -> some View {
        environment(\.dialogIcon, icon)
    }

    /// Sets the border of the alerts and confirmation dialogs presented in
    /// this view: its colour, its box-drawing characters, and the colour of
    /// the title drawn in it.
    ///
    /// TUI-specific: SwiftUI's dialogs are drawn by the system and take no
    /// styling. Apply it outside the presenting modifier, as
    /// ``dialogSeverity(_:)``; it reaches every `alert` and
    /// `confirmationDialog` presented within the view, whatever their form,
    /// and every ``AlertPanel`` drawn there:
    ///
    /// ```swift
    /// ContentView()
    ///     .alert("Delete this item?", isPresented: $confirming) {
    ///         Button("Delete", role: .destructive) { deleteItem() }
    ///     }
    ///     .dialogBorder(.palette.accent, style: .doubleLine)
    /// ```
    ///
    /// Each part left `nil` keeps the dialog's default: the appearance's
    /// border characters, the palette's border colour and its accent for the
    /// title — or, for a critical dialog (``dialogSeverity(_:)``), the
    /// palette's warning colour for both. An ``AlertPanel``'s own
    /// `borderStyle`, `borderColor` and `titleColor` win over this. A
    /// `dialogBorder` nearer the dialog replaces one further out whole, so
    /// `dialogBorder()` puts the defaults back.
    ///
    /// - Parameters:
    ///   - color: The border's colour, or `nil` for the default.
    ///   - style: The box-drawing characters, or `nil` for the appearance's.
    ///   - titleColor: The colour of the title in the top border, or `nil`
    ///     for the default.
    /// - Returns: A view whose presented dialogs are drawn with that border.
    nonisolated public func dialogBorder(
        _ color: Color? = nil, style: BorderStyle? = nil, titleColor: Color? = nil
    ) -> some View {
        environment(\.dialogBorder, DialogBorder(color: color, style: style, titleColor: titleColor))
    }
}

// MARK: - Drawing

/// An alert's message, with the dialog icon at its leading edge when the
/// environment names one.
struct _AlertMessage: View {
    let message: String
    let icon: Image?

    /// The box a raster icon is fitted into: eight columns by four rows, about
    /// square in a terminal's two-to-one cells, and small enough to sit beside
    /// a sentence.
    static let rasterIconSize = (width: 8, height: 4)

    var body: some View {
        if let icon {
            HStack(alignment: .top, spacing: 2) {
                iconView(icon)
                messageText
            }
        } else {
            messageText
        }
    }

    /// The whole message: a `.lineLimit` around where the alert was written is
    /// about what is written there, not about what the alert has to say.
    private var messageText: Text {
        Text(message).lineLimit(nil)
    }

    @ViewBuilder
    private func iconView(_ icon: Image) -> some View {
        switch icon.content {
        case .symbol:
            icon
        case .raster:
            icon.frame(width: Self.rasterIconSize.width, height: Self.rasterIconSize.height)
        }
    }
}
