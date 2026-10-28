//  🖥️ TUI — A Terminal UI framework for Swift
//  View+Presentation.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIChrome
import TUIFoundation

// MARK: - Alert Presentation

extension View {
    /// Presents an alert when a binding to a Boolean value is true.
    ///
    /// This modifier mirrors SwiftUI's `.alert(isPresented:)` pattern. When
    /// `isPresented` is `true`, the base content is dimmed and the alert is
    /// displayed centered on top.
    ///
    /// Choosing any action closes the alert, so an action does not flip
    /// `isPresented` itself. Escape chooses the `.cancel`-role button.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @State var showAlert = false
    ///
    /// VStack {
    ///     Button("Show Alert") { showAlert = true }
    /// }
    /// .alert("Warning", isPresented: $showAlert) {
    ///     Button("Yes") { save() }
    ///     Button("Cancel", role: .cancel) {}
    /// } message: {
    ///     Text("Are you sure?")
    /// }
    /// ```
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. A `String` you computed binds to the overload
    /// below and is shown as written.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title.
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the alert.
    ///   - actions: A ViewBuilder returning the alert action buttons.
    ///   - message: A ViewBuilder returning the alert message content.
    ///   - borderStyle: Custom border style for the alert (TUI extension, default: nil).
    ///   - borderColor: Custom border color (TUI extension, default: nil).
    ///   - titleColor: Custom title text color (TUI extension, default: nil).
    /// - Returns: A view that presents an alert conditionally.
    public func alert<Actions: View, Message: View>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) -> some View {
        titledAlert(
            titleKey, isPresented: isPresented, actions: actions(), message: message(),
            colours: (borderStyle, borderColor, titleColor))
    }

    /// Presents an alert whose title is displayed as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the alert.
    ///   - actions: A ViewBuilder returning the alert action buttons.
    ///   - message: A ViewBuilder returning the alert message content.
    ///   - borderStyle: Custom border style for the alert (TUI extension, default: nil).
    ///   - borderColor: Custom border color (TUI extension, default: nil).
    ///   - titleColor: Custom title text color (TUI extension, default: nil).
    /// - Returns: A view that presents an alert conditionally.
    @_disfavoredOverload
    public func alert<S: StringProtocol, Actions: View, Message: View>(
        _ title: S,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) -> some View {
        AlertPresentationModifier<Self, Actions, Message>(
            content: self,
            isPresented: isPresented,
            title: String(title),
            message: message(),
            actions: actions(),
            borderStyle: borderStyle,
            borderColor: borderColor,
            titleColor: titleColor
        )
    }

    /// Presents an alert with title and actions only (no message).
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the alert title.
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the alert.
    ///   - actions: A ViewBuilder returning the alert action buttons.
    ///   - borderStyle: Optional border style.
    ///   - borderColor: Optional border color.
    ///   - titleColor: Optional title color.
    /// - Returns: A view that presents an alert conditionally.
    public func alert<Actions: View>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) -> some View {
        titledAlert(
            titleKey, isPresented: isPresented, actions: actions(), message: EmptyView?.none,
            colours: (borderStyle, borderColor, titleColor))
    }

    /// Presents an alert with actions only, whose title is shown as written.
    ///
    /// Generic over `StringProtocol` for the same reason as the form above:
    /// that is what keeps a *literal* binding to the key overload rather than
    /// to this one — see ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - title: The alert title.
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the alert.
    ///   - actions: A ViewBuilder returning the alert action buttons.
    ///   - borderStyle: Optional border style.
    ///   - borderColor: Optional border color.
    ///   - titleColor: Optional title color.
    /// - Returns: A view that presents an alert conditionally.
    @_disfavoredOverload
    public func alert<S: StringProtocol, Actions: View>(
        _ title: S,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil
    ) -> some View {
        AlertPresentationModifier<Self, Actions, EmptyView>(
            content: self,
            isPresented: isPresented,
            title: String(title),
            message: nil,
            actions: actions(),
            borderStyle: borderStyle,
            borderColor: borderColor,
            titleColor: titleColor
        )
    }
}

// MARK: - Confirmation Dialog

extension View {
    /// Presents a confirmation dialog (action sheet) with a message when a
    /// binding is true. Mirrors SwiftUI's `confirmationDialog(_:isPresented:...)`.
    ///
    /// Presented like `.alert` — a centred, dimming overlay dismissible with
    /// Escape — but with the action buttons stacked **vertically** (an action
    /// sheet). A `.cancel`-role button sorts to the bottom.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. A `String` you computed binds to the overload
    /// below and is shown as written.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the dialog title (suppressed when
    ///     `titleVisibility` is `.hidden`).
    ///   - isPresented: A binding controlling presentation.
    ///   - titleVisibility: Whether the title is shown (default `.automatic`).
    ///   - actions: A ViewBuilder returning the dialog's action buttons.
    ///   - message: A ViewBuilder returning the dialog's message.
    public func confirmationDialog<Actions: View, Message: View>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        titledAlert(
            titleVisibility == .hidden ? nil : titleKey, isPresented: isPresented, actions: actions(),
            message: message(), verticalButtons: true)
    }

    /// Presents a confirmation dialog whose title is displayed as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, Actions: View, Message: View>(
        _ title: S,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        AlertPresentationModifier<Self, Actions, Message>(
            content: self,
            isPresented: isPresented,
            title: titleVisibility == .hidden ? "" : String(title),
            message: message(),
            actions: actions(),
            borderStyle: nil,
            borderColor: nil,
            titleColor: nil,
            verticalButtons: true
        )
    }

    /// Presents a confirmation dialog (action sheet) with actions only.
    public func confirmationDialog<Actions: View>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        titledAlert(
            titleVisibility == .hidden ? nil : titleKey, isPresented: isPresented, actions: actions(),
            message: EmptyView?.none, verticalButtons: true)
    }

    /// Presents an actions-only dialog whose title is displayed as written.
    ///
    /// Generic over `StringProtocol` for the same reason as the form above:
    /// that is what keeps a *literal* binding to the key overload rather than
    /// to this one — see ``LocalizedStringKey``.
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, Actions: View>(
        _ title: S,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        AlertPresentationModifier<Self, Actions, EmptyView>(
            content: self,
            isPresented: isPresented,
            title: titleVisibility == .hidden ? "" : String(title),
            message: nil,
            actions: actions(),
            borderStyle: nil,
            borderColor: nil,
            titleColor: nil,
            verticalButtons: true
        )
    }
}

// MARK: - Modal Presentation

extension View {
    /// Presents a modal overlay when a binding to a Boolean value is true.
    ///
    /// This modifier dims the base content and displays the provided content
    /// centered on top when `isPresented` is `true`. Use this for custom modal
    /// content that doesn't fit the alert pattern.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @State var showSettings = false
    ///
    /// VStack {
    ///     Button("Settings") { showSettings = true }
    /// }
    /// .modal(isPresented: $showSettings) {
    ///     Dialog(title: "Settings") {
    ///         Text("Option 1")
    ///         Text("Option 2")
    ///         Button("Close") { showSettings = false }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the modal.
    ///   - onDismiss: A closure run after the modal is dismissed, or `nil` for
    ///     no callback.
    ///   - content: A ViewBuilder returning the modal content, called only
    ///     while the modal is presented, each time it is drawn.
    /// - Returns: A view that presents a modal overlay conditionally.
    public func modal<Modal: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Modal
    ) -> some View {
        modalPresentation(
            isPresented: isPresented, style: .sheet, itemKey: nil, onDismiss: onDismiss, modal: content)
    }

    /// The one place a modal presentation is assembled — panel or cover, about
    /// an item or about nothing.
    ///
    /// Four call sites: ``modal(isPresented:onDismiss:content:)`` (which
    /// ``sheet(isPresented:onDismiss:content:)`` forwards to),
    /// ``sheet(item:onDismiss:content:)``, and the two `fullScreenCover`
    /// spellings. What they share is not just the modifier but the `onDismiss`
    /// wiring: it fires on the presented → dismissed transition, which covers
    /// every route that clears the binding — a Close button, Escape,
    /// `@Environment(\.dismiss)`, or a programmatic change. Written
    /// per-spelling it was already duplicated once.
    ///
    /// Not the always-on `modal { … }` in `View+Modal.swift`, which
    /// builds the modifier itself: it has no binding to watch and so nothing
    /// for this wiring to do.
    ///
    /// - Parameters:
    ///   - isPresented: The binding that presents and dismisses.
    ///   - style: Panel over a dimmed page, or the whole content area.
    ///   - itemKey: The presented item's identity key, or `nil` when the
    ///     presentation is about nothing in particular. See
    ///     ``ModalPresentationModifier/itemKey``.
    ///   - isAboutAnItem: Whether this is an `item:` form, whose dismissed
    ///     sheet can never dock (``ModalPresentationModifier/postsDockWhileDismissed``).
    ///   - onDismiss: Run on the presented → dismissed transition.
    ///   - modal: Builds the content to present — only while it is presented
    ///     (``ModalPresentationModifier/modal``).
    private func modalPresentation<Modal: View>(
        isPresented: Binding<Bool>,
        style: ModalPresentationModifier<Self, Modal>.Style,
        itemKey: String?,
        isAboutAnItem: Bool = false,
        onDismiss: (() -> Void)?,
        modal: @escaping () -> Modal
    ) -> some View {
        _AdaptiveModal(
            base: self, isPresented: isPresented, modal: modal, style: style, itemKey: itemKey,
            postsDockWhileDismissed: !isAboutAnItem)
            // On the app's binding, not the presenter's: a sheet that becomes a
            // cover as the size class changes is not dismissed.
            .onChange(of: isPresented.wrappedValue) { wasPresented, isPresentedNow in
                if wasPresented, !isPresentedNow { onDismiss?() }
            }
    }

    /// Presents content modally when a binding to a Boolean value is true.
    ///
    /// A SwiftUI-compatible spelling of ``modal(isPresented:onDismiss:content:)``:
    /// the terminal presents the content as a centred overlay that dims the
    /// background rather than as a sliding sheet, but a call site written against
    /// SwiftUI's `.sheet(isPresented:onDismiss:content:)` works unchanged.
    ///
    /// In a vertically compact size class — which TUI's never is unless the
    /// app writes one into the environment — it is presented as a full-screen
    /// cover instead, as SwiftUI's is on an iPhone in landscape, or as the
    /// content's ``View/presentationCompactAdaptation(_:)`` asks.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the sheet.
    ///   - onDismiss: An optional closure run when the sheet is dismissed.
    ///   - content: A ViewBuilder returning the sheet content, called only
    ///     while the sheet is presented, each time it is drawn.
    /// - Returns: A view that presents the content modally.
    public func sheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modal(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }

    /// Presents a sheet for a currently-selected item.
    ///
    /// SwiftUI-compatible: a non-`nil` `Identifiable` value presents the sheet;
    /// clearing the binding (or the content setting it to `nil`) dismisses it and
    /// runs `onDismiss`. As with the `isPresented:` form, the terminal presents a
    /// centred, background-dimming overlay rather than a sliding sheet.
    ///
    /// The item's **id is the content's identity**, which is what this form has
    /// over closing over a value and presenting on a flag: change the item and
    /// the sheet is a different view — `@State` back at its initial values,
    /// `onAppear`/`task` firing again — rather than the same view handed a new
    /// row to describe. Moving a selection from one row to another while the
    /// sheet is up used to leave the first row's half-typed draft, scroll
    /// position and selection sitting in the second row's editor. Keep the ids
    /// distinct: two items whose ids are equal are one view, as in SwiftUI.
    ///
    /// ```swift
    /// @State var editing: Row?
    /// List(rows, selection: $sel) { … }
    ///     .sheet(item: $editing) { row in EditView(row) }
    /// ```
    ///
    /// - Parameters:
    ///   - item: A binding to an optional, identifiable item; non-`nil` presents.
    ///   - onDismiss: An optional closure run when the sheet is dismissed.
    ///   - content: A ViewBuilder building the sheet from the unwrapped item,
    ///     called only while the sheet is presented.
    /// - Returns: A view that presents a sheet for the selected item.
    public func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in if !presented { item.wrappedValue = nil } }
        )
        // Assembled here rather than through the `isPresented:` spelling, which
        // has no way to name the item: the identity key has to be read from the
        // same binding, at the same moment, as the item the content is built
        // from — once it is presented.
        let shown = item.wrappedValue
        return modalPresentation(
            isPresented: isPresented,
            style: .sheet,
            itemKey: shown.map { identityKey($0.id) },
            isAboutAnItem: true,
            onDismiss: onDismiss,
            modal: { shown.map(content) })
    }
}

// MARK: - The adapting presenter

/// A sheet or a cover, presented as a cover where a sheet adapts to one
/// (``sheetIsCover(_:horizontal:vertical:)``).
///
/// One presenter whose style follows the size classes: it reads them every
/// frame, and its presenter resolves them against the content once that is
/// built, while it is presented — so a class written while the sheet is up
/// changes no part of the structure, and both the presenting view and the
/// presented content keep their state.
struct _AdaptiveModal<Base: View, Modal: View>: View {
    let base: Base
    let isPresented: Binding<Bool>
    let modal: () -> Modal
    let style: ModalPresentationModifier<Base, Modal>.Style
    let itemKey: String?
    let postsDockWhileDismissed: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ModalPresentationModifier(
            content: base,
            isPresented: isPresented,
            modal: modal,
            style: style,
            sizeClasses: PresentationSizeClasses(horizontal: horizontalSizeClass, vertical: verticalSizeClass),
            postsDockWhileDismissed: postsDockWhileDismissed,
            itemKey: itemKey)
    }
}

/// A sheet or a full-screen cover written on a form row goes around the row
/// the form lays out, which keeps its place, as SwiftUI's form keeps a row
/// under a sheet (measured, `Tools/SwiftUIProbes/Form rows`).
extension _AdaptiveModal: FormRowRewrapping {
    var formRowContent: Base { base }

    func rewrappingFormRow<V: View>(_ row: V) -> any View {
        // The style is a type of each specialisation's own, so it is spelled
        // again for the new one.
        let style: ModalPresentationModifier<V, Modal>.Style =
            switch self.style {
            case .sheet: .sheet
            case .fullScreen: .fullScreen
            }
        return _AdaptiveModal<V, Modal>(
            base: row, isPresented: isPresented, modal: modal, style: style, itemKey: itemKey,
            postsDockWhileDismissed: postsDockWhileDismissed)
    }
}

// MARK: - Full-Screen Cover

extension View {
    /// Presents content covering the whole screen. Matches SwiftUI's
    /// `fullScreenCover(isPresented:onDismiss:content:)`.
    ///
    /// The difference from ``sheet(isPresented:onDismiss:content:)`` is the same
    /// one SwiftUI draws: a sheet is a panel over the (dimmed) page, a cover
    /// replaces it. The cover fills the content area between the app header and
    /// the status bar, nothing of the page shows through, and it cannot be
    /// dragged — there is nowhere for it to go.
    ///
    /// Content smaller than that area is CENTRED in it, as SwiftUI centres it —
    /// unlike a bare ``View/frame(width:height:alignment:)``, which is
    /// top-leading by default here. Add your own `Spacer`s or `frame` alignment
    /// if you want the content pinned to an edge instead.
    ///
    /// Escape dismisses it, as with every presentation.
    ///
    /// - Parameters:
    ///   - isPresented: A binding controlling presentation.
    ///   - onDismiss: An optional closure run when the cover is dismissed.
    ///   - content: A ViewBuilder returning the cover's content, called only
    ///     while the cover is presented, each time it is drawn.
    public func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modalPresentation(
            isPresented: isPresented, style: .fullScreen, itemKey: nil, onDismiss: onDismiss, modal: content)
    }

    /// Presents a full-screen cover for a currently-selected item. Matches
    /// SwiftUI's `fullScreenCover(item:onDismiss:content:)`.
    ///
    /// The item's id is the content's identity, exactly as in
    /// ``sheet(item:onDismiss:content:)`` — a cover shown for a different item
    /// starts with fresh state.
    ///
    /// - Parameters:
    ///   - item: A binding to an optional, identifiable item; non-`nil` presents.
    ///   - onDismiss: An optional closure run when the cover is dismissed.
    ///   - content: A ViewBuilder building the cover from the unwrapped item,
    ///     called only while the cover is presented.
    public func fullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in if !presented { item.wrappedValue = nil } }
        )
        // Keyed by the item, for the reason ``sheet(item:onDismiss:content:)``
        // states: a cover reopened for a different item is a different view.
        let shown = item.wrappedValue
        return modalPresentation(
            isPresented: isPresented,
            style: .fullScreen,
            itemKey: shown.map { identityKey($0.id) },
            isAboutAnItem: true,
            onDismiss: onDismiss,
            modal: { shown.map(content) })
    }
}

// MARK: - Notification Host

extension View {
    /// Makes this view the notification rendering host.
    ///
    /// Attach this modifier **once, at the root of your view tree** (e.g. on the
    /// content of your `WindowGroup`). Notifications are posted to a process-wide
    /// ``NotificationService`` and live there until they expire, independently of
    /// the view tree — so the host's placement decides only *where they are
    /// drawn*. Hosting at the root means a toast posted on one screen stays
    /// visible until it expires even after the user navigates elsewhere, which is
    /// almost always what transient status messages want. Hosting it on a single
    /// screen instead scopes the toast to that screen: it disappears the moment
    /// you navigate away (the notification is still active, but nothing is drawing
    /// it). Apply it on exactly one view — two hosts would draw every toast twice.
    ///
    /// It reads active notifications from the environment's ``NotificationService``
    /// and renders them as a stacked overlay at the configured position.
    ///
    /// Notifications are posted via the service, not declared in the view tree:
    ///
    /// ```swift
    /// // At the root:
    /// ContentView()
    ///     .notificationHost()
    ///
    /// // Anywhere in the hierarchy:
    /// NotificationService.current.post("Saved!")
    /// ```
    ///
    /// The base content remains fully interactive — notifications do not dim
    /// or block the background.
    ///
    /// - Parameter width: Fixed width of each notification box in characters (default: 40).
    /// - Returns: A view that renders notifications from the environment service.
    public func notificationHost(
        width: Int = 40
    ) -> some View {
        NotificationHostModifier(
            content: self,
            width: width
        )
    }
}

// MARK: - A dialog titled with a key

extension View {
    /// An alert or confirmation dialog titled with `titleKey` — read now, and
    /// read again where the dialog is drawn under a subtree's `\.locale` that
    /// names another language (``AlertPresentationModifier/titleSource``) —
    /// or untitled where it is `nil`, a dialog whose title is hidden. What
    /// the key-titled overloads make, where the ones titled as written make
    /// the modifier with no source.
    func titledAlert<Actions: View, Message: View>(
        _ titleKey: LocalizedStringKey?, isPresented: Binding<Bool>, actions: Actions, message: Message?,
        colours: (BorderStyle?, Color?, Color?) = (nil, nil, nil), verticalButtons: Bool = false
    ) -> AlertPresentationModifier<Self, Actions, Message> {
        var modifier = AlertPresentationModifier(
            content: self, isPresented: isPresented, title: titleKey?.localized ?? "", message: message,
            actions: actions, borderStyle: colours.0, borderColor: colours.1, titleColor: colours.2,
            verticalButtons: verticalButtons)
        modifier.titleSource = titleKey?.textSource
        return modifier
    }
}
