//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationDragIndicator.swift
//
//  `presentationDragIndicator(_:)`: whether a detented sheet shows the grabber
//  on its top edge, which the reader drags — or moves with the keys — between
//  the sheet's detents.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Modifier

extension View {
    /// Sets the visibility of the drag indicator on top of a sheet. Mirrors
    /// SwiftUI's `presentationDragIndicator(_:)`.
    ///
    /// Apply it to the sheet's **content**, with its detents:
    ///
    /// ```swift
    /// .sheet(isPresented: $showSettings) {
    ///     SettingsView()
    ///         .presentationDetents([.medium, .large])
    ///         .presentationDragIndicator(.visible)
    /// }
    /// ```
    ///
    /// The indicator is the sheet's **grabber**: a rule across its top edge
    /// with a handle in the middle — the divider of a `VSplitView`, between the
    /// sheet and the page. It is a focus stop after the sheet's own controls:
    /// ↑ moves the sheet to its next larger detent and ↓ to its next smaller,
    /// ↖ and ↘ (Home and End) to the smallest and the largest — where the
    /// terminal sends them to the app, which is not yet measured for every
    /// terminal's default profile, so ↑ and ↓ are the route that always
    /// works — and ↩ or Space to the next, round to the smallest after the
    /// largest. A mouse drags it,
    /// snapping from detent to detent as it goes. The detent it moves to is
    /// written to the `selection:` binding of
    /// ``View/presentationDetents(_:selection:)`` when there is one.
    ///
    /// `.automatic` shows the grabber when the sheet has two detents or more
    /// to move between, and `.visible` likewise: on a sheet with one height
    /// there is nothing to drag it to, and a handle that cannot move is a
    /// promise the drag would not keep. `.hidden` takes the grabber away — its
    /// rule, its handle, its drag and its keys together, since a sheet that
    /// can be resized by the pointer and not by the keyboard is one this
    /// framework does not make — and the sheet stays at its detent, which the
    /// binding still moves.
    ///
    /// Detents that a short terminal resolves to the same number of rows count
    /// once. A popover and a full-screen cover have no detents, and the
    /// indicator does nothing there, as on macOS.
    ///
    /// - Parameter visibility: The preferred visibility of the drag indicator.
    public func presentationDragIndicator(_ visibility: Visibility) -> some View {
        _PresentationDragIndicatorView(content: self, dragIndicatorVisibility: visibility)
    }
}

// MARK: - The trait

/// Content that has said whether its sheet shows the grabber.
@MainActor
protocol PresentationDragIndicatorProviding {
    /// The visibility the content asked for.
    var dragIndicatorVisibility: Visibility { get }
}

/// The wrapper ``View/presentationDragIndicator(_:)`` produces. Renders and
/// measures as its content; carrying the visibility is its whole job.
struct _PresentationDragIndicatorView<Content: View>: View, PresentationDragIndicatorProviding {
    let content: Content
    let dragIndicatorVisibility: Visibility

    var body: Never {
        fatalError("_PresentationDragIndicatorView renders via Renderable")
    }
}

extension _PresentationDragIndicatorView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context)
    }
}

extension _PresentationDragIndicatorView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _PresentationDragIndicatorView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _PresentationDragIndicatorView: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _PresentationDragIndicatorView: DrawsContentUnchanged {}
