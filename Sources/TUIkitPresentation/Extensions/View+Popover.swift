//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Popover.swift
//
//  `popover(isPresented:…)` and `popover(item:…)`: an anchored popover in a
//  regular size class, adapting to a sheet or a cover in a compact one
//  (decisions A21). Declared here, beside the sheet and the cover, rather than
//  beside `PopoverPresentationModifier` in TUIkitFoundation, which cannot
//  reach them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - popover(…)

extension View {
    /// Presents a popover anchored to this view. Matches SwiftUI's
    /// `popover(isPresented:attachmentAnchor:arrowEdge:content:)`.
    ///
    /// Unlike ``View/sheet(isPresented:onDismiss:content:)``, which centres a panel
    /// over a dimmed screen, a popover stays *next to the thing it belongs to* —
    /// a bordered panel below (or above, or beside) the presenting view, over an
    /// undimmed page. It is the same presentation `.contextMenu` and the
    /// `Picker` drop-down use, with your content instead of menu rows.
    ///
    /// Escape closes it, and so does a click anywhere outside it.
    ///
    /// ```swift
    /// Button("Details") { showing = true }
    ///     .popover(isPresented: $showing) {
    ///         VStack(alignment: .leading) {
    ///             Text("Ganymede").bold()
    ///             Text("Largest moon in the solar system")
    ///         }
    ///     }
    /// ```
    ///
    /// In a compact size class — which TUIkit's never is unless the app writes
    /// one into the environment — it is presented as a sheet instead, as
    /// SwiftUI's is on iOS, or as the content's
    /// ``View/presentationCompactAdaptation(_:)`` asks.
    ///
    /// - Parameters:
    ///   - isPresented: A binding controlling presentation.
    ///   - attachmentAnchor: Where on this view the popover attaches.
    ///   - arrowEdge: Which side of this view the popover sits on. A terminal
    ///     draws no arrow, but the edge still decides the side; `nil` (the
    ///     default) means below.
    ///   - content: A ViewBuilder returning the popover's content.
    public func popover<Content: View>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        _AdaptivePopover(
            base: self, isPresented: isPresented, popover: content(), attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge ?? .bottom, itemKey: nil)
    }

    /// Presents a popover for a currently-selected item. Matches SwiftUI's
    /// `popover(item:attachmentAnchor:arrowEdge:content:)`.
    ///
    /// The item's id is the content's identity, exactly as in
    /// ``View/sheet(item:onDismiss:content:)`` — a popover reopened for a
    /// different item starts with fresh state.
    ///
    /// - Parameters:
    ///   - item: A binding to an optional, identifiable item; non-`nil` presents.
    ///   - attachmentAnchor: Where on this view the popover attaches.
    ///   - arrowEdge: Which side of this view the popover sits on.
    ///   - content: A ViewBuilder building the popover from the unwrapped item.
    public func popover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in if !presented { item.wrappedValue = nil } }
        )
        // Built here rather than through the `isPresented:` spelling, which has
        // no way to name the item: the key has to be read from the same binding,
        // at the same moment, as the content built from it.
        return _AdaptivePopover(
            base: self, isPresented: isPresented, popover: item.wrappedValue.map(content),
            attachmentAnchor: attachmentAnchor, arrowEdge: arrowEdge ?? .bottom,
            itemKey: item.wrappedValue.map { identityKey($0.id) })
    }
}

// MARK: - The adapting presenter

/// A popover that is a sheet or a cover where the size classes say so
/// (``popoverForm(of:horizontal:vertical:)``).
///
/// The three presenters are always all there, nested in one order around the
/// presenting view, and the form decides only which of their bindings is
/// live: a size class written while the view is up changes no part of its
/// structure, so the presenting view keeps its state. The presented content
/// is a different view in each — it starts over when the form changes, as a
/// presentation that changes form does.
struct _AdaptivePopover<Base: View, Popover: View>: View {
    let base: Base
    let isPresented: Binding<Bool>
    let popover: Popover
    let attachmentAnchor: PopoverAttachmentAnchor
    let arrowEdge: Edge
    let itemKey: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let form = popoverForm(of: popover, horizontal: horizontalSizeClass, vertical: verticalSizeClass)
        let popover = self.popover
        PopoverPresentationModifier(
            content: ModalPresentationModifier(
                content: ModalPresentationModifier(
                    content: base, isPresented: isPresented(as: .sheet, when: form), modal: { popover },
                    style: .sheet, itemKey: itemKey),
                isPresented: isPresented(as: .fullScreenCover, when: form), modal: { popover }, style: .fullScreen,
                itemKey: itemKey),
            isPresented: isPresented(as: .popover, when: form), popover: popover,
            attachmentAnchor: attachmentAnchor, arrowEdge: arrowEdge, itemKey: itemKey)
    }

    /// `isPresented` as `wanted` sees it: presented when it is, and the form
    /// is `wanted`. Writing it — a dismissal — writes the app's binding.
    private func isPresented(as wanted: PopoverForm, when form: PopoverForm) -> Binding<Bool> {
        let isPresented = self.isPresented
        return Binding(
            get: { form == wanted && isPresented.wrappedValue },
            set: { isPresented.wrappedValue = $0 })
    }
}

// MARK: - In a Form

/// A popover written on a form row goes around the row the form lays out,
/// which keeps its place, as SwiftUI's form keeps it (measured, `Tools/SwiftUIProbes/Form rows`).
extension _AdaptivePopover: FormRowRewrapping {
    var formRowContent: Base { base }

    func rewrappingFormRow<V: View>(_ row: V) -> any View {
        _AdaptivePopover<V, Popover>(
            base: row, isPresented: isPresented, popover: popover, attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge, itemKey: itemKey)
    }
}
